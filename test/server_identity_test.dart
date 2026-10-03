import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/models/server_identity.dart';
import 'package:rodplayer/core/models/server_registry.dart';
import 'package:rodplayer/core/security/server_registry_migration.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('ServerId equality and serialization are stable', () {
    final first = ServerId('server-one');
    final restored = ServerId.fromJson(first.toJson());

    expect(restored, first);
    expect(restored.hashCode, first.hashCode);
    expect(restored.toJson(), 'server-one');
    expect(() => ServerId.fromJson(3), throwsFormatException);
    expect(
      () => ServerId('https://server.example.test'),
      throwsFormatException,
    );
  });

  test('server registry rejects unbounded configured server inventories', () {
    final servers = <ServerRecord>[
      for (var i = 0; i <= ServerRegistrySnapshot.maximumServers; i++)
        ServerRecord(
          id: ServerId('server-$i'),
          displayName: 'Server $i',
          endpoints: <ServerEndpoint>[
            ServerEndpoint('https://server-$i.example.test'),
          ],
        ),
    ];
    expect(() => ServerRegistrySnapshot(servers: servers), throwsArgumentError);
  });

  test('server/account/item identity isolates equal Jellyfin item IDs', () {
    final serverA = ServerId('server-a');
    final serverB = ServerId('server-b');
    final accountA = ServerAccountId(serverId: serverA, userId: 'same-user');
    final accountB = ServerAccountId(serverId: serverB, userId: 'same-user');
    final itemA = ServerMediaItemId(accountId: accountA, itemId: 'same-item');
    final itemB = ServerMediaItemId(accountId: accountB, itemId: 'same-item');

    expect(accountA, isNot(accountB));
    expect(itemA, isNot(itemB));
    expect(ServerAccountId.fromJson(accountA.toJson()), accountA);
    expect(accountA.toJson().keys, unorderedEquals(['serverId', 'userId']));
  });

  test(
    'credential references encode server and user without delimiter clashes',
    () {
      final first = ServerAccountId(
        serverId: ServerId('server.a'),
        userId: 'b',
      );
      final second = ServerAccountId(
        serverId: ServerId('server'),
        userId: 'a.b',
      );

      expect(
        ServerRegistryMigration.credentialReferenceFor(first),
        isNot(ServerRegistryMigration.credentialReferenceFor(second)),
      );
    },
  );

  test('configured server ID persists independently of endpoint URL', () async {
    SharedPreferences.setMockInitialValues({
      'serverUrl': 'https://lan.example.test',
    });
    final preferences = await SharedPreferences.getInstance();
    final first = await ConfiguredServerIdStore(preferences).loadOrCreate();
    await preferences.setString('serverUrl', 'https://remote.example.test');
    final second = await ConfiguredServerIdStore(preferences).loadOrCreate();

    expect(second, first);
    expect(
      preferences.getString(ConfiguredServerIdStore.preferenceKey),
      first.toJson(),
    );
  });

  test(
    'login identity reuses verified aliases and rejects endpoint conflicts',
    () {
      final serverId = ServerId('configured-server');
      final record = ServerRecord(
        id: serverId,
        displayName: 'Media',
        endpoints: <ServerEndpoint>[ServerEndpoint('https://one.example.test')],
        verifiedSystemId: 'jellyfin-system-one',
      );
      final registry = ServerRegistrySnapshot(servers: <ServerRecord>[record]);
      final resolver = ServerIdentityResolver();
      final provisional = ServerId('install-slot');

      expect(
        resolver.resolveLogin(
          registry: registry,
          endpoint: ServerEndpoint('https://one.example.test/'),
          verifiedSystemId: 'jellyfin-system-one',
          provisionalServerId: provisional,
        ),
        serverId,
      );
      expect(
        resolver.resolveLogin(
          registry: registry,
          endpoint: ServerEndpoint('https://two.example.test'),
          verifiedSystemId: 'jellyfin-system-two',
          provisionalServerId: provisional,
        ),
        isNot(serverId),
      );
      expect(
        () => resolver.resolveLogin(
          registry: registry,
          endpoint: ServerEndpoint('https://one.example.test'),
          verifiedSystemId: 'different-system',
          provisionalServerId: provisional,
        ),
        throwsA(isA<ServerIdentityConflictException>()),
      );
      final moved = resolver.resolveLogin(
        registry: registry,
        endpoint: ServerEndpoint('https://new.example.test'),
        verifiedSystemId: 'jellyfin-system-one',
        provisionalServerId: provisional,
      );
      expect(moved, serverId);
      final oldAccount = ServerAccountId(serverId: serverId, userId: 'user');
      final movedAccount = ServerAccountId(serverId: moved, userId: 'user');
      expect(
        ServerRegistryMigration.credentialReferenceFor(movedAccount),
        ServerRegistryMigration.credentialReferenceFor(oldAccount),
      );
      expect(
        ServerMediaItemId(accountId: movedAccount, itemId: 'item'),
        ServerMediaItemId(accountId: oldAccount, itemId: 'item'),
      );
      final duplicate = ServerRecord(
        id: ServerId('duplicate'),
        displayName: 'Duplicate',
        endpoints: [ServerEndpoint('https://duplicate.example.test')],
        verifiedSystemId: 'jellyfin-system-one',
      );
      expect(
        () => resolver.resolveLogin(
          registry: ServerRegistrySnapshot(servers: [record, duplicate]),
          endpoint: ServerEndpoint('https://new.example.test'),
          verifiedSystemId: 'jellyfin-system-one',
          provisionalServerId: provisional,
        ),
        throwsA(isA<ServerIdentityConflictException>()),
      );
    },
  );
}
