import 'package:flutter/foundation.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/models/server_identity.dart';
import 'package:rodplayer/core/models/server_registry.dart';
import 'package:rodplayer/core/security/credential_store.dart';
import 'package:rodplayer/core/events/jellyfin_server_events.dart';
import 'package:rodplayer/core/events/jellyfin_server_event_session_factory.dart';

abstract interface class ServerSessionFactory {
  Future<ServerSession> open(
    ServerRecord server,
    ServerUserAccount account, {
    bool Function()? isCurrent,
  });
}

/// Runtime resources bound to exactly one configured server and account.
final class ServerSession {
  ServerSession({
    required this.serverId,
    required this.accountId,
    this.verifiedSystemId,
    this.events,
    required this.client,
  }) {
    if (client.serverId != serverId || client.accountIdentity != accountId) {
      throw ArgumentError('Client identity does not match server session');
    }
    if (verifiedSystemId != null && verifiedSystemId!.trim().isEmpty) {
      throw ArgumentError.value(verifiedSystemId, 'verifiedSystemId');
    }
  }

  final ServerId serverId;
  final ServerAccountId accountId;
  final String? verifiedSystemId;
  final JellyfinApiClient client;
  final JellyfinServerEventSessionController? events;
  final ValueNotifier<bool> cancellation = ValueNotifier<bool>(false);
  bool _closed = false;

  bool get isClosed => _closed;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    cancellation.value = true;
    try {
      await events?.close();
    } finally {
      client.close();
      cancellation.dispose();
    }
  }
}

typedef ServerClientBuilder = JellyfinApiClient Function({
  required String endpoint,
  required ServerId serverId,
  required String userId,
  required String accessToken,
});

/// Opens and verifies an authenticated connection before publishing a session.
/// Endpoint candidates come only from the selected record; private endpoint
/// policy is enforced by the injected client's ServiceTransport.
final class JellyfinServerSessionFactory implements ServerSessionFactory {
  JellyfinServerSessionFactory({
    required this.credentials,
    required this.buildClient,
    this.serverEventSessionBuilder,
    this.onLibraryInvalidated = _ignoreServerEvent,
    this.onUserDataInvalidated = _ignoreServerEvent,
    this.onItemsInvalidated = _ignoreItemEvents,
  });

  final CredentialStore credentials;
  final ServerClientBuilder buildClient;
  final ServerEventSessionBuilder? serverEventSessionBuilder;
  final ServerEventInvalidationHandler onLibraryInvalidated;
  final ServerEventInvalidationHandler onUserDataInvalidated;
  final ServerItemInvalidationHandler onItemsInvalidated;

  @override
  Future<ServerSession> open(
    ServerRecord server,
    ServerUserAccount account, {
    bool Function()? isCurrent,
  }) async {
    if (account.identity.serverId != server.id ||
        !server.accounts.any((known) => known.identity == account.identity)) {
      throw StateError('Account is not associated with the selected server');
    }
    final token = JellyfinApiClient.cleanToken(
      await credentials.readToken(account.credentialReference),
    );
    if (token == null)
      throw StateError('Server account credential is unavailable');

    // Select one configured endpoint; never silently fall through from a
    // required private endpoint to a public one after failure.
    final endpoint = server.endpoints.first;
    final client = buildClient(
      endpoint: endpoint.value,
      serverId: server.id,
      userId: account.identity.userId,
      accessToken: token,
    );
    JellyfinServerEventSessionController? events;
    try {
      final systemId = await client.getVerifiedServerSystemId();
      if (server.verifiedSystemId != null &&
          systemId != server.verifiedSystemId) {
        throw StateError('Configured server identity did not match');
      }
      final currentUser = await client.getCurrentUser();
      if (currentUser.id != account.identity.userId) {
        throw StateError(
            'Authenticated account did not match the selected user');
      }
      ServerSession? openedSession;
      events = serverEventSessionBuilder?.call(
        client: client,
        isCurrent: isCurrent ?? () => openedSession?.isClosed == false,
        onLibraryInvalidated: onLibraryInvalidated,
        onUserDataInvalidated: onUserDataInvalidated,
        onItemsInvalidated: onItemsInvalidated,
      );
      openedSession = ServerSession(
        serverId: server.id,
        accountId: account.identity,
        verifiedSystemId: systemId,
        events: events,
        client: client,
      );
      return openedSession;
    } on Object {
      await events?.close();
      client.close();
      rethrow;
    }
  }
}

void _ignoreServerEvent() {}

void _ignoreItemEvents(Set<String> _) {}
