import 'dart:convert';

import 'package:rodplayer/core/models/server_identity.dart';
import 'package:rodplayer/core/models/server_registry.dart';
import 'package:rodplayer/core/models/server_registry_store.dart';
import 'package:rodplayer/core/security/credential_migration.dart';
import 'package:rodplayer/core/security/credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Resolves an authenticated login to an app-owned server record. Endpoint
/// equality is used only to find configured aliases; a known Jellyfin system
/// ID mismatch is rejected before any account credential is persisted.
enum ServerIdentityConflict { endpointMismatch, ambiguousVerifiedIdentity }

final class ServerIdentityConflictException implements Exception {
  const ServerIdentityConflictException(this.reason);
  final ServerIdentityConflict reason;
}

final class ServerIdentityResolver {
  ServerIdentityResolver({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  ServerId resolveLogin({
    required ServerRegistrySnapshot registry,
    required ServerEndpoint endpoint,
    required String verifiedSystemId,
    required ServerId provisionalServerId,
  }) {
    final endpointMatches = registry.servers
        .where((server) => server.endpoints.contains(endpoint))
        .toList(growable: false);
    if (endpointMatches.any(
      (server) =>
          server.verifiedSystemId != null &&
          server.verifiedSystemId != verifiedSystemId,
    )) {
      throw const ServerIdentityConflictException(
        ServerIdentityConflict.endpointMismatch,
      );
    }
    final verified = registry.servers
        .where((server) => server.verifiedSystemId == verifiedSystemId)
        .toList(growable: false);
    if (verified.length > 1 ||
        endpointMatches.length > 1 ||
        (verified.length == 1 &&
            endpointMatches.length == 1 &&
            verified.single.id != endpointMatches.single.id)) {
      throw const ServerIdentityConflictException(
        ServerIdentityConflict.ambiguousVerifiedIdentity,
      );
    }
    if (endpointMatches.length == 1) return endpointMatches.single.id;
    if (verified.length == 1) return verified.single.id;
    if (registry.servers.isEmpty) return provisionalServerId;
    return ServerId(_uuid.v4());
  }
}

/// Copies a legacy installation into the versioned registry.
/// The legacy token is never removed here; the new secure-store value and its
/// registry reference are verified first, allowing safe retries and rollback.
final class ServerRegistryMigration {
  ServerRegistryMigration({
    required this.preferences,
    required this.credentials,
    required this.registry,
  });

  final SharedPreferences preferences;
  final CredentialStore credentials;
  final PreferencesServerRegistryStore registry;

  Future<bool> migrateLegacyInstallation() async {
    final url = preferences.getString(CredentialMigration.serverUrlKey);
    final userId = preferences.getString(CredentialMigration.userIdKey);
    final token = await credentials.readToken(CredentialMigration.tokenKey);
    if (url == null ||
        url.trim().isEmpty ||
        userId == null ||
        userId.trim().isEmpty ||
        userId != userId.trim() ||
        (token == null || token.isEmpty)) {
      return false;
    }

    final endpoint = ServerEndpoint(url);
    final store = ConfiguredServerIdStore(preferences);
    final provisionalServerId = await store.loadOrCreate();
    final snapshot = await registry.load();
    final endpointMatches = snapshot.servers
        .where((server) => server.endpoints.contains(endpoint))
        .toList(growable: false);
    final accountMatches = endpointMatches
        .where(
          (server) => server.accounts.any(
            (account) => account.identity.userId == userId,
          ),
        )
        .toList(growable: false);
    final activeServer = snapshot.activeServerId == null
        ? null
        : snapshot.server(snapshot.activeServerId!);
    final activeAccount = snapshot.activeAccountId;
    ServerId? preservedServerId;
    if (activeServer != null &&
        activeAccount != null &&
        activeAccount.userId == userId &&
        activeAccount.serverId == activeServer.id &&
        activeServer.accounts.any(
          (account) => account.identity == activeAccount,
        )) {
      final activeToken = await credentials.readToken(
        credentialReferenceFor(activeAccount),
      );
      if (activeToken == token) preservedServerId = activeServer.id;
    }
    final serverId =
        preservedServerId ??
        (accountMatches.length == 1
            ? accountMatches.single.id
            : endpointMatches.length == 1 &&
                  endpointMatches.single.verifiedSystemId == null
            ? endpointMatches.single.id
            : snapshot.servers.isEmpty
            ? provisionalServerId
            : store.createNew());
    final accountId = ServerAccountId(serverId: serverId, userId: userId);
    final credentialReference = credentialReferenceFor(accountId);
    final existing = snapshot.server(serverId);

    if (existing != null &&
        existing.accounts.any((account) => account.identity == accountId) &&
        await credentials.readToken(credentialReference) == token) {
      // Endpoint location may change while the configured server identity stays
      // stable. Put the current legacy endpoint first without deriving a new ID.
      final account = ServerUserAccount(
        identity: accountId,
        credentialReference: credentialReference,
      );
      final updated = ServerRecord(
        id: existing.id,
        displayName: existing.displayName,
        endpoints: <ServerEndpoint>{endpoint, ...existing.endpoints}.toList(),
        accounts: <ServerUserAccount>[
          ...existing.accounts.where((item) => item.identity != accountId),
          account,
        ],
        verifiedSystemId: existing.verifiedSystemId,
      );
      await registry.updateServer(updated);
      await registry.setActiveServer(serverId, accountId: accountId);
      return true;
    }
    await credentials.writeToken(credentialReference, token);
    if (await credentials.readToken(credentialReference) != token) {
      throw StateError('Could not verify migrated server credential');
    }

    final account = ServerUserAccount(
      identity: accountId,
      credentialReference: credentialReference,
    );
    final displayName = endpoint.uri.host;
    final record = existing == null
        ? ServerRecord(
            id: serverId,
            displayName: displayName,
            endpoints: <ServerEndpoint>[endpoint],
            accounts: <ServerUserAccount>[account],
          )
        : ServerRecord(
            id: existing.id,
            displayName: existing.displayName,
            endpoints: <ServerEndpoint>{
              ...existing.endpoints,
              endpoint,
            }.toList(),
            accounts: <ServerUserAccount>[
              ...existing.accounts.where((item) => item.identity != accountId),
              account,
            ],
            verifiedSystemId: existing.verifiedSystemId,
          );

    if (existing == null) {
      await registry.addServer(record);
    } else {
      await registry.updateServer(record);
    }
    await registry.setActiveServer(serverId, accountId: accountId);
    final saved = await registry.load();
    ServerUserAccount? savedAccount;
    for (final candidate
        in saved.server(serverId)?.accounts ?? const <ServerUserAccount>[]) {
      if (candidate.identity == accountId) {
        savedAccount = candidate;
        break;
      }
    }
    if (saved.activeServerId != serverId ||
        savedAccount?.credentialReference != credentialReference ||
        await credentials.readToken(credentialReference) != token) {
      throw StateError('Could not verify migrated server account');
    }
    return true;
  }

  static String credentialReferenceFor(ServerAccountId identity) =>
      'nautilus.account.${_keySegment(identity.serverId.value)}.${_keySegment(identity.userId)}';

  static String _keySegment(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');
}
