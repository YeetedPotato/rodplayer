import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'server_identity.dart';
import 'server_registry.dart';

class ServerRegistryCorruptException implements Exception {
  const ServerRegistryCorruptException();

  @override
  String toString() => 'ServerRegistryCorruptException';
}

/// Durable nonsecret configuration store. Credentials are kept separately by
/// CredentialStore, addressed only by each account's secure-store reference.
/// One versioned JSON value keeps this bounded configuration snapshot atomic;
/// relational jobs/outbox data should use a database when those features land.
final class PreferencesServerRegistryStore {
  PreferencesServerRegistryStore(this.preferences);

  final SharedPreferences preferences;
  Future<void> _writes = Future<void>.value();

  Future<ServerRegistrySnapshot> load() async {
    await _writes;
    return _read();
  }

  ServerRegistrySnapshot _read() {
    final raw = preferences.getString(ServerRegistrySnapshot.preferenceKey);
    if (raw == null) return ServerRegistrySnapshot();
    try {
      return ServerRegistrySnapshot.decode(raw);
    } on Object {
      // Preserve corrupt bytes for recovery. Never replace a document that
      // may contain the only record of configured server/account ownership.
      throw const ServerRegistryCorruptException();
    }
  }

  Future<void> addServer(ServerRecord record) => _update((snapshot) {
        if (snapshot.server(record.id) != null) {
          throw StateError('Server ID already exists');
        }
        return snapshot
            .copyWith(servers: <ServerRecord>[...snapshot.servers, record]);
      });

  Future<void> updateServer(ServerRecord record) => _update((snapshot) {
        if (snapshot.server(record.id) == null) {
          throw StateError('Server does not exist');
        }
        return snapshot.copyWith(
          servers: <ServerRecord>[
            for (final existing in snapshot.servers)
              if (existing.id == record.id) record else existing,
          ],
        );
      });

  Future<List<String>> removeServer(ServerId id) async {
    late List<String> credentialReferences;
    await _update((snapshot) {
      final record = snapshot.server(id);
      if (record == null) throw StateError('Server does not exist');
      credentialReferences = record.accounts
          .map((account) => account.credentialReference)
          .toList(growable: false);
      return snapshot.copyWith(
        servers: snapshot.servers.where((item) => item.id != id),
        clearActiveServer: snapshot.activeServerId == id,
      );
    });
    return credentialReferences;
  }

  /// Commits verified identity and active selection in one registry snapshot.
  Future<void> activateServer(
    ServerRecord record,
    ServerAccountId accountId,
    String verifiedSystemId,
  ) =>
      _update((snapshot) {
        final existing = snapshot.server(record.id);
        if (existing == null ||
            !existing.accounts.any((item) => item.identity == accountId)) {
          throw StateError(
              'Account is not associated with the selected server');
        }
        if (record.id != accountId.serverId ||
            verifiedSystemId.trim().isEmpty ||
            (existing.verifiedSystemId != null &&
                existing.verifiedSystemId != verifiedSystemId)) {
          throw StateError('Verified server identity did not match registry');
        }
        final verified = existing.verifiedSystemId == null
            ? existing.withVerifiedSystemId(verifiedSystemId)
            : existing;
        return ServerRegistrySnapshot(
          servers: <ServerRecord>[
            for (final item in snapshot.servers)
              if (item.id == record.id) verified else item,
          ],
          activeServerId: record.id,
          activeAccountId: accountId,
        );
      });

  Future<void> setActiveServer(
    ServerId? id, {
    ServerAccountId? accountId,
  }) =>
      _update((snapshot) {
        if (id == null) {
          if (accountId != null) {
            throw StateError('An active account requires an active server');
          }
          return ServerRegistrySnapshot(servers: snapshot.servers);
        }
        final server = snapshot.server(id);
        if (server == null) {
          throw StateError('Active server must exist in the registry');
        }
        if (accountId != null &&
            (accountId.serverId != id ||
                !server.accounts.any((item) => item.identity == accountId))) {
          throw StateError('Active account must belong to the selected server');
        }
        return ServerRegistrySnapshot(
          servers: snapshot.servers,
          activeServerId: id,
          activeAccountId: accountId,
        );
      });

  Future<void> setActiveAccount(ServerAccountId? accountId) =>
      _update((snapshot) {
        final serverId = snapshot.activeServerId;
        if (accountId != null &&
            (serverId != accountId.serverId ||
                snapshot.server(serverId!)?.accounts.any(
                          (item) => item.identity == accountId,
                        ) !=
                    true)) {
          throw StateError('Active account must belong to the active server');
        }
        return ServerRegistrySnapshot(
          servers: snapshot.servers,
          activeServerId: serverId,
          activeAccountId: accountId,
        );
      });

  Future<void> _update(
    ServerRegistrySnapshot Function(ServerRegistrySnapshot) mutate,
  ) {
    final result = Completer<void>();
    _writes = _writes.then((_) async {
      final oldValue =
          preferences.getString(ServerRegistrySnapshot.preferenceKey);
      try {
        final next = mutate(_read());
        final encoded = next.encode();
        final saved = await preferences.setString(
          ServerRegistrySnapshot.preferenceKey,
          encoded,
        );
        if (!saved || _read().encode() != encoded) {
          throw StateError('Server registry write verification failed');
        }
        result.complete();
      } on Object catch (error, stack) {
        // SharedPreferences writes one complete string, but restore the prior
        // snapshot if a platform backend reports a failed/invalid write.
        try {
          if (oldValue == null) {
            await preferences.remove(ServerRegistrySnapshot.preferenceKey);
          } else {
            await preferences.setString(
              ServerRegistrySnapshot.preferenceKey,
              oldValue,
            );
          }
        } on Object {
          // Keep the original persistence error authoritative.
        }
        result.completeError(error, stack);
      }
    });
    return result.future;
  }
}
