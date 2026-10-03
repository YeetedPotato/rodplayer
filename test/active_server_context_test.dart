import 'dart:convert';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/device/installation_identity.dart';
import 'package:rodplayer/core/events/jellyfin_server_events.dart';
import 'package:rodplayer/core/models/server_identity.dart';
import 'package:rodplayer/core/models/server_registry.dart';
import 'package:rodplayer/core/models/server_registry_store.dart';
import 'package:rodplayer/core/security/credential_migration.dart';
import 'package:rodplayer/core/security/credential_store.dart';
import 'package:rodplayer/core/security/server_registry_migration.dart';
import 'package:rodplayer/core/session/active_server_context.dart';
import 'package:rodplayer/core/session/server_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _identity = InstallationIdentity(
  clientName: 'Test',
  deviceName: 'Test device',
  deviceId: 'device',
  appVersion: '1',
);

ServerUserAccount _account(ServerId server, String user) => ServerUserAccount(
      identity: ServerAccountId(serverId: server, userId: user),
      credentialReference: 'credential-${server.value}-$user',
    );

ServerRecord _record(String id, {String? user = 'user', String? verified}) {
  final serverId = ServerId(id);
  return ServerRecord(
    id: serverId,
    displayName: id,
    endpoints: <ServerEndpoint>[
      ServerEndpoint('https://$id.example.test/jellyfin'),
    ],
    accounts: user == null
        ? const <ServerUserAccount>[]
        : <ServerUserAccount>[_account(serverId, user)],
    verifiedSystemId: verified,
  );
}

JellyfinApiClient _client(ServerId id, ServerAccountId account) =>
    JellyfinApiClient(
      baseUrl: 'https://${id.value}.example.test',
      identity: _identity,
      serverId: id,
      userId: account.userId,
      accessToken: 'test-token',
      client: MockClient((_) async => http.Response('{}', 200)),
    );

ServerSession _session(ServerRecord record, ServerUserAccount account) =>
    ServerSession(
      serverId: record.id,
      accountId: account.identity,
      verifiedSystemId: record.verifiedSystemId ?? 'machine-${record.id.value}',
      client: _client(record.id, account.identity),
    );

ServerSession _sessionWithThrowingEventCleanup(
  ServerRecord record,
  ServerUserAccount account,
) {
  final session = _session(record, account);
  return ServerSession(
    serverId: session.serverId,
    accountId: session.accountId,
    verifiedSystemId: session.verifiedSystemId,
    client: session.client,
    events: JellyfinServerEventSessionController(
      source: _ThrowingEventSource(),
      isCurrent: () => true,
      onLibraryInvalidated: () {},
      onUserDataInvalidated: () {},
      onItemsInvalidated: (_) {},
    ),
  );
}

final class _Sessions implements ServerSessionFactory {
  final Map<String,
          Future<ServerSession> Function(ServerRecord, ServerUserAccount)>
      handlers = {};
  final List<String> opened = [];
  final Map<String, bool Function()> currentChecks = {};

  @override
  Future<ServerSession> open(
    ServerRecord server,
    ServerUserAccount account, {
    bool Function()? isCurrent,
  }) {
    opened.add(server.id.value);
    if (isCurrent != null) currentChecks[server.id.value] = isCurrent;
    return handlers[server.id.value]?.call(server, account) ??
        Future<ServerSession>.value(_session(server, account));
  }
}

final class _ThrowingEventSource implements ServerEventSource {
  @override
  ServerEventsSupport get support => ServerEventsSupport.unsupported;
  @override
  Stream<JellyfinServerEvent> get events =>
      const Stream<JellyfinServerEvent>.empty();
  @override
  Future<void> close() async => throw StateError('cleanup failure');
}

void main() {
  test('restore disposal while persistence is held never publishes candidate',
      () async {
    final sessions = _Sessions();
    final record = _record('a');
    final candidate = _session(record, record.accounts.single);
    sessions.handlers['a'] = (_, __) async => candidate;
    final entered = Completer<void>();
    final release = Completer<void>();
    final controller = ActiveServerController(
        sessions: sessions,
        persistActiveServer: (_, __, ___) async {
          entered.complete();
          await release.future;
        },
        hasActivePlayback: () => false);
    var publications = 0;
    var closes = 0;
    controller.current.addListener(() {
      if (controller.active != null) publications++;
    });
    candidate.cancellation.addListener(() {
      if (candidate.cancellation.value) closes++;
    });
    final restoring = controller.restore(ServerRegistrySnapshot(
        servers: [record],
        activeServerId: record.id,
        activeAccountId: record.accounts.single.identity));
    await entered.future;
    final disposal = controller.dispose();
    release.complete();
    expect(await restoring, isFalse);
    await disposal;
    expect(publications, 0);
    expect(closes, 1);
    expect(candidate.isClosed, isTrue);
    expect(controller.active, isNull);
  });
  test(
      'production session factory switches A to B with isolated credentials and failed B preserves A',
      () async {
    final a = _record('a', verified: 'machine-a');
    final b = _record('b', verified: 'machine-b');
    final credentials = _TestCredentials()
      ..tokens[a.accounts.single.credentialReference] = 'token-a'
      ..tokens[b.accounts.single.credentialReference] = 'token-b';
    var failB = true;
    final used = <String, String>{};
    final clients = <JellyfinApiClient>[];
    final factory = JellyfinServerSessionFactory(
        credentials: credentials,
        buildClient: (
            {required endpoint,
            required serverId,
            required userId,
            required accessToken}) {
          used[serverId.value] = accessToken;
          final client = JellyfinApiClient(
              baseUrl: endpoint,
              identity: _identity,
              serverId: serverId,
              userId: userId,
              accessToken: accessToken,
              client: MockClient((request) async {
                if (serverId == b.id && failB) return http.Response('', 503);
                return http.Response(
                    jsonEncode(request.url.path.endsWith('/System/Info/Public')
                        ? {'Id': 'machine-${serverId.value}'}
                        : {'Id': userId, 'Name': 'User'}),
                    200);
              }));
          clients.add(client);
          return client;
        });
    final persisted = <ServerId>[];
    final controller = ActiveServerController(
        sessions: factory,
        persistActiveServer: (record, _, __) async => persisted.add(record.id),
        hasActivePlayback: () => false);
    addTearDown(controller.dispose);
    await controller.switchTo(a, a.accounts.single);
    final first = controller.active!;
    await expectLater(controller.switchTo(b, b.accounts.single),
        throwsA(isA<ServerConnectionException>()));
    expect(controller.active, same(first));
    expect(first.session.isClosed, isFalse);
    expect(persisted, [a.id]);
    failB = false;
    await controller.switchTo(b, b.accounts.single);
    expect(used, {'a': 'token-a', 'b': 'token-b'});
    expect(first.session.isClosed, isTrue);
    expect(controller.active!.session.client.accessToken, 'token-b');
    expect(controller.active!.session.client.serverId, b.id);
    expect(persisted, [a.id, b.id]);
  });
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('registry stores multiple servers and permits shared endpoints',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final registry = PreferencesServerRegistryStore(preferences);
    final a = _record('a');
    final b = ServerRecord(
      id: ServerId('b'),
      displayName: 'Second',
      endpoints: a.endpoints,
      accounts: <ServerUserAccount>[_account(ServerId('b'), 'user')],
    );
    await registry.addServer(a);
    await registry.addServer(b);
    final restored = await registry.load();
    expect(
        restored.servers.map((server) => server.id.value), <String>['a', 'b']);
    expect(restored.servers.first.endpoints, restored.servers.last.endpoints);
    expect(restored.servers.first.accounts.single.identity.userId, 'user');
    expect(
        restored.servers.last.accounts.single.identity.serverId, ServerId('b'));
  });

  test(
      'registry rejects duplicate IDs, missing active IDs, and cross-server accounts',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final registry = PreferencesServerRegistryStore(preferences);
    final a = _record('a');
    await registry.addServer(a);
    await expectLater(registry.addServer(a), throwsStateError);
    await expectLater(
        registry.setActiveServer(ServerId('missing')), throwsStateError);
    expect(
      () => ServerRecord(
        id: ServerId('a'),
        displayName: 'A',
        endpoints: <ServerEndpoint>[ServerEndpoint('https://a.example.test')],
        accounts: <ServerUserAccount>[_account(ServerId('b'), 'user')],
      ),
      throwsArgumentError,
    );
  });

  test('registry round-trips active server and its account together', () async {
    final preferences = await SharedPreferences.getInstance();
    final registry = PreferencesServerRegistryStore(preferences);
    final a = _record('a');
    await registry.addServer(a);
    await registry.setActiveServer(a.id, accountId: a.accounts.single.identity);
    final restored = await registry.load();
    expect(restored.activeServerId, a.id);
    expect(restored.activeAccountId, a.accounts.single.identity);
    expect(
      () => ServerRegistrySnapshot(
        servers: <ServerRecord>[a],
        activeServerId: a.id,
        activeAccountId: _account(ServerId('b'), 'user').identity,
      ),
      throwsArgumentError,
    );
  });

  test('one server can retain distinct account identities', () async {
    final preferences = await SharedPreferences.getInstance();
    final registry = PreferencesServerRegistryStore(preferences);
    final server = _record('a');
    await registry.addServer(server.withAccount(_account(server.id, 'other')));
    final restored = await registry.load();
    expect(restored.servers.single.accounts.map((item) => item.identity.userId),
        containsAll(<String>['user', 'other']));
  });

  test('remove clears active reference and returns credential refs for cleanup',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final registry = PreferencesServerRegistryStore(preferences);
    final a = _record('a');
    await registry.addServer(a);
    await registry.setActiveServer(a.id, accountId: a.accounts.single.identity);
    final refs = await registry.removeServer(a.id);
    expect(refs, <String>['credential-a-user']);
    expect((await registry.load()).activeServerId, isNull);
    expect((await registry.load()).servers, isEmpty);
  });

  test('removing an inactive server preserves the active account', () async {
    final preferences = await SharedPreferences.getInstance();
    final registry = PreferencesServerRegistryStore(preferences);
    final a = _record('a');
    final b = _record('b');
    await registry.addServer(a);
    await registry.addServer(b);
    await registry.setActiveServer(a.id, accountId: a.accounts.single.identity);

    await registry.removeServer(b.id);
    final saved = await registry.load();
    expect(saved.activeServerId, a.id);
    expect(saved.activeAccountId, a.accounts.single.identity);
    expect(saved.servers.map((server) => server.id), <ServerId>[a.id]);
  });

  test('corrupt registry fails without overwriting its stored bytes', () async {
    const corrupt = '{invalid registry';
    SharedPreferences.setMockInitialValues(<String, Object>{
      ServerRegistrySnapshot.preferenceKey: corrupt,
    });
    final preferences = await SharedPreferences.getInstance();
    final registry = PreferencesServerRegistryStore(preferences);
    await expectLater(
        registry.load(), throwsA(isA<ServerRegistryCorruptException>()));
    await expectLater(registry.addServer(_record('a')),
        throwsA(isA<ServerRegistryCorruptException>()));
    expect(
        preferences.getString(ServerRegistrySnapshot.preferenceKey), corrupt);
  });

  test('registry rejects malformed optional identity fields', () {
    expect(
      () => ServerRegistrySnapshot.decode(
        '{"schemaVersion":1,"servers":[],"activeAccountId":"not-an-object"}',
      ),
      throwsFormatException,
    );
    expect(
      () => ServerRegistrySnapshot.decode(
        '{"schemaVersion":1,"servers":[],"activeServerId":3}',
      ),
      throwsFormatException,
    );
  });

  test('server ID and account/item keys isolate equal IDs across servers', () {
    final a = ServerAccountId(serverId: ServerId('a'), userId: 'same-user');
    final b = ServerAccountId(serverId: ServerId('b'), userId: 'same-user');
    expect(a, isNot(b));
    expect(
      ServerMediaItemId(accountId: a, itemId: 'same-item'),
      isNot(ServerMediaItemId(accountId: b, itemId: 'same-item')),
    );
  });

  test('failed B setup leaves A active and closes no active resources',
      () async {
    final sessions = _Sessions();
    final a = _record('a');
    final b = _record('b');
    final controller = ActiveServerController(
      sessions: sessions,
      persistActiveServer: (_, __, ___) async {},
      hasActivePlayback: () => false,
    );
    await controller.switchTo(a, a.accounts.single);
    final previous = controller.active!;
    sessions.handlers['b'] = (_, __) async => throw StateError('offline');
    await expectLater(
        controller.switchTo(b, b.accounts.single), throwsStateError);
    expect(controller.active, same(previous));
    expect(previous.session.isClosed, isFalse);
    expect(previous.session.cancellation.value, isFalse);
    await controller.dispose();
  });

  test('successful A to B transition advances generation and cancels A',
      () async {
    final sessions = _Sessions();
    final a = _record('a');
    final b = _record('b');
    final savedActive = <ServerId>[];
    final controller = ActiveServerController(
      sessions: sessions,
      persistActiveServer: (record, _, __) async => savedActive.add(record.id),
      hasActivePlayback: () => false,
    );
    await controller.switchTo(a, a.accounts.single);
    final previous = controller.active!;
    expect(sessions.currentChecks['a']!(), isTrue);
    await controller.switchTo(b, b.accounts.single);
    expect(controller.active!.serverId, b.id);
    expect(controller.active!.generation, previous.generation + 1);
    expect(previous.session.isClosed, isTrue);
    expect(previous.session.cancellation.value, isTrue);
    expect(sessions.currentChecks['a']!(), isFalse);
    expect(sessions.currentChecks['b']!(), isTrue);
    expect(savedActive, <ServerId>[a.id, b.id]);
    await controller.dispose();
  });

  test('event ownership moves only when the candidate server commits',
      () async {
    final sessions = _Sessions();
    final a = _record('a');
    final b = _record('b');
    final bPersistenceStarted = Completer<void>();
    final allowBCommit = Completer<void>();
    final controller = ActiveServerController(
      sessions: sessions,
      persistActiveServer: (record, _, __) async {
        if (record.id == b.id) {
          bPersistenceStarted.complete();
          await allowBCommit.future;
        }
      },
      hasActivePlayback: () => false,
    );
    await controller.switchTo(a, a.accounts.single);
    final switching = controller.switchTo(b, b.accounts.single);
    await bPersistenceStarted.future;

    expect(controller.active?.serverId, a.id);
    expect(sessions.currentChecks['a']!(), isTrue);
    expect(sessions.currentChecks['b']!(), isFalse);

    allowBCommit.complete();
    await switching;
    expect(controller.active?.serverId, b.id);
    expect(sessions.currentChecks['a']!(), isFalse);
    expect(sessions.currentChecks['b']!(), isTrue);
    await controller.dispose();
  });

  test('one hundred sequential server switches preserve exact active owner',
      () async {
    final sessions = _Sessions();
    final a = _record('stress-a');
    final b = _record('stress-b');
    final controller = ActiveServerController(
      sessions: sessions,
      persistActiveServer: (_, __, ___) async {},
      hasActivePlayback: () => false,
    );
    await controller.switchTo(a, a.accounts.single);
    for (var index = 0; index < 100; index++) {
      final next = index.isEven ? b : a;
      await controller.switchTo(next, next.accounts.single);
      expect(controller.active?.serverId, next.id);
      expect(controller.active?.accountId, next.accounts.single.identity);
    }
    expect(sessions.opened, hasLength(101));
    expect(controller.active?.generation, 101);
    await controller.dispose();
  });

  test('A to B to C switch makes an in-flight A result stale', () async {
    final sessions = _Sessions();
    final a = _record('a');
    final b = _record('b');
    final c = _record('c');
    final controller = ActiveServerController(
      sessions: sessions,
      persistActiveServer: (_, __, ___) async {},
      hasActivePlayback: () => false,
    );
    await controller.switchTo(a, a.accounts.single);
    final aContext = controller.active!;
    final pending = Completer<String>();
    final staleOperation = controller.run<String>((_) => pending.future);

    final switchB = controller.switchTo(b, b.accounts.single);
    final switchC = controller.switchTo(c, c.accounts.single);
    expect(await switchB, ServerSwitchOutcome.activated);
    expect(await switchC, ServerSwitchOutcome.activated);
    pending.complete('late A result');

    final result = await staleOperation;
    expect(result.isCurrent, isFalse);
    expect(result.generation, aContext.generation);
    expect(controller.active!.serverId, c.id);
    expect(aContext.session.isClosed, isTrue);
    await controller.dispose();
  });

  test('switch atomically saves verified identity and active account',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final registry = PreferencesServerRegistryStore(preferences);
    final a = _record('a');
    await registry.addServer(a);
    final sessions = _Sessions();
    final controller = ActiveServerController(
      sessions: sessions,
      persistActiveServer: (server, account, systemId) =>
          registry.activateServer(server, account, systemId),
      hasActivePlayback: () => false,
    );
    await controller.switchTo(a, a.accounts.single);
    final stored = await registry.load();
    expect(stored.activeServerId, a.id);
    expect(stored.activeAccountId, a.accounts.single.identity);
    expect(stored.server(a.id)!.verifiedSystemId, 'machine-a');
    await controller.dispose();
  });

  test('late result from A is marked stale after switching to B', () async {
    final sessions = _Sessions();
    final a = _record('a');
    final b = _record('b');
    final controller = ActiveServerController(
      sessions: sessions,
      persistActiveServer: (_, __, ___) async {},
      hasActivePlayback: () => false,
    );
    await controller.switchTo(a, a.accounts.single);
    final delayed = Completer<String>();
    final result = controller.run<String>((_) => delayed.future);
    await controller.switchTo(b, b.accounts.single);
    delayed.complete('stale A payload');
    final operation = await result;
    expect(operation.isCurrent, isFalse);
    expect(operation.value, isNull);
    expect(operation.generation, 1);
    await controller.dispose();
  });

  test('concurrent switches serialize in request order', () async {
    final sessions = _Sessions();
    final a = _record('a');
    final b = _record('b');
    final allowA = Completer<ServerSession>();
    sessions.handlers['a'] = (_, __) => allowA.future;
    final controller = ActiveServerController(
      sessions: sessions,
      persistActiveServer: (_, __, ___) async {},
      hasActivePlayback: () => false,
    );
    final first = controller.switchTo(a, a.accounts.single);
    final second = controller.switchTo(b, b.accounts.single);
    await Future<void>.delayed(Duration.zero);
    expect(sessions.opened, <String>['a']);
    allowA.complete(_session(a, a.accounts.single));
    await Future.wait(<Future<ServerSwitchOutcome>>[first, second]);
    expect(sessions.opened, <String>['a', 'b']);
    expect(controller.active!.serverId, b.id);
    expect(controller.active!.generation, 2);
    await controller.dispose();
  });

  test('queued request back to active server is not lost behind another switch',
      () async {
    final sessions = _Sessions();
    final a = _record('a');
    final b = _record('b');
    final allowB = Completer<ServerSession>();
    sessions.handlers['b'] = (_, __) => allowB.future;
    final controller = ActiveServerController(
      sessions: sessions,
      persistActiveServer: (_, __, ___) async {},
      hasActivePlayback: () => false,
      initial: ActiveServerContext(
        generation: 1,
        session: _session(a, a.accounts.single),
      ),
    );

    final toB = controller.switchTo(b, b.accounts.single);
    await Future<void>.delayed(Duration.zero);
    final backToA = controller.switchTo(a, a.accounts.single);
    allowB.complete(_session(b, b.accounts.single));
    await Future.wait(<Future<ServerSwitchOutcome>>[toB, backToA]);

    expect(sessions.opened, <String>['b', 'a']);
    expect(controller.active?.serverId, a.id);
    await controller.dispose();
  });

  test('restore opens only the persisted active account', () async {
    final sessions = _Sessions();
    final a = _record('a');
    final snapshot = ServerRegistrySnapshot(
      servers: <ServerRecord>[a],
      activeServerId: a.id,
      activeAccountId: a.accounts.single.identity,
    );
    final controller = ActiveServerController(
      sessions: sessions,
      persistActiveServer: (_, __, ___) async {},
      hasActivePlayback: () => false,
    );
    expect(await controller.restore(snapshot), isTrue);
    expect(controller.active!.accountId, a.accounts.single.identity);
    expect(controller.active!.generation, 1);
    await controller.dispose();
  });

  test('restore does not guess when there is no active account preference',
      () async {
    final sessions = _Sessions();
    final a = _record('a');
    final controller = ActiveServerController(
      sessions: sessions,
      persistActiveServer: (_, __, ___) async {},
      hasActivePlayback: () => false,
    );
    expect(
      await controller.restore(ServerRegistrySnapshot(
        servers: <ServerRecord>[a],
        activeServerId: a.id,
      )),
      isFalse,
    );
    expect(sessions.opened, isEmpty);
    await controller.dispose();
  });

  test('active playback rejects server switch before session creation',
      () async {
    final sessions = _Sessions();
    final a = _record('a');
    final b = _record('b');
    final controller = ActiveServerController(
      sessions: sessions,
      persistActiveServer: (_, __, ___) async {},
      hasActivePlayback: () => true,
      initial: ActiveServerContext(
          generation: 1, session: _session(a, a.accounts.single)),
    );
    await expectLater(
      controller.switchTo(b, b.accounts.single),
      throwsA(isA<ActivePlaybackPreventsServerSwitch>()),
    );
    expect(controller.active?.serverId, a.id);
    expect(sessions.opened, isEmpty);
    await controller.dispose();
  });

  test('persistence failure keeps previous active context', () async {
    final sessions = _Sessions();
    final a = _record('a');
    final b = _record('b');
    var failPersist = false;
    final controller = ActiveServerController(
      sessions: sessions,
      persistActiveServer: (_, __, ___) async {
        if (failPersist) throw StateError('storage failure');
      },
      hasActivePlayback: () => false,
    );
    await controller.switchTo(a, a.accounts.single);
    final previous = controller.active!;
    failPersist = true;
    await expectLater(
        controller.switchTo(b, b.accounts.single), throwsStateError);
    expect(controller.active, same(previous));
    await controller.dispose();
  });

  test('old-session cleanup failure does not undo a committed server switch',
      () async {
    final a = _record('a');
    final b = _record('b');
    final controller = ActiveServerController(
      sessions: _Sessions(),
      persistActiveServer: (_, __, ___) async {},
      hasActivePlayback: () => false,
      initial: ActiveServerContext(
        generation: 1,
        session: _sessionWithThrowingEventCleanup(a, a.accounts.single),
      ),
    );

    expect(
      await controller.switchTo(b, b.accounts.single),
      ServerSwitchOutcome.activated,
    );
    expect(controller.active?.serverId, b.id);
    expect(controller.lastPreviousSessionCleanupFailed, isTrue);
    await controller.dispose();
  });

  test('Jellyfin session factory verifies the selected authenticated server',
      () async {
    final server = _record('a', verified: 'machine-a');
    final account = server.accounts.single;
    final credentials = _TestCredentials()
      ..tokens[account.credentialReference] = 'stored-token';
    var builds = 0;
    final factory = JellyfinServerSessionFactory(
      credentials: credentials,
      buildClient: ({
        required endpoint,
        required serverId,
        required userId,
        required accessToken,
      }) {
        builds++;
        return JellyfinApiClient(
          baseUrl: endpoint,
          identity: _identity,
          serverId: serverId,
          userId: userId,
          accessToken: accessToken,
          client: MockClient((request) async => http.Response(
                jsonEncode(request.url.path.endsWith('/System/Info/Public')
                    ? {'Id': 'machine-a'}
                    : {'Id': 'user', 'Name': 'User'}),
                200,
              )),
        );
      },
    );
    final session = await factory.open(server, account);
    expect(builds, 1);
    expect(session.verifiedSystemId, 'machine-a');
    expect(session.accountId, account.identity);
    await session.close();
  });

  test('Jellyfin session factory does not fall through to a second endpoint',
      () async {
    final server = ServerRecord(
      id: ServerId('a'),
      displayName: 'A',
      endpoints: <ServerEndpoint>[
        ServerEndpoint('https://private.example.test'),
        ServerEndpoint('https://public.example.test'),
      ],
      accounts: <ServerUserAccount>[_account(ServerId('a'), 'user')],
    );
    final account = server.accounts.single;
    final credentials = _TestCredentials()
      ..tokens[account.credentialReference] = 'stored-token';
    var builds = 0;
    final factory = JellyfinServerSessionFactory(
      credentials: credentials,
      buildClient: ({
        required endpoint,
        required serverId,
        required userId,
        required accessToken,
      }) {
        builds++;
        return JellyfinApiClient(
          baseUrl: endpoint,
          identity: _identity,
          serverId: serverId,
          userId: userId,
          accessToken: accessToken,
          client: MockClient((_) async => http.Response('', 503)),
        );
      },
    );
    await expectLater(factory.open(server, account),
        throwsA(isA<ServerConnectionException>()));
    expect(builds, 1);
  });

  test('client/account mismatch is rejected and candidate is closed', () async {
    final sessions = _Sessions();
    final a = _record('a');
    final b = _record('b');
    sessions.handlers['a'] = (_, __) async => _session(b, b.accounts.single);
    final controller = ActiveServerController(
      sessions: sessions,
      persistActiveServer: (_, __, ___) async {},
      hasActivePlayback: () => false,
    );
    await expectLater(
        controller.switchTo(a, a.accounts.single), throwsStateError);
    await controller.dispose();
  });

  test(
      'registry migration copies legacy credential only to secure store and retries safely',
      () async {
    const legacyToken = 'sensitive-but-test-only';
    SharedPreferences.setMockInitialValues(<String, Object>{
      CredentialMigration.serverUrlKey: 'https://legacy.example.test/jellyfin',
      CredentialMigration.userIdKey: 'legacy-user',
    });
    final preferences = await SharedPreferences.getInstance();
    final credentials = _TestCredentials()
      ..tokens[CredentialMigration.tokenKey] = legacyToken;
    final registry = PreferencesServerRegistryStore(preferences);
    final migration = ServerRegistryMigration(
      preferences: preferences,
      credentials: credentials,
      registry: registry,
    );
    expect(await migration.migrateLegacyInstallation(), isTrue);
    final id =
        ServerId(preferences.getString(ConfiguredServerIdStore.preferenceKey)!);
    final account = ServerAccountId(serverId: id, userId: 'legacy-user');
    final reference = ServerRegistryMigration.credentialReferenceFor(account);
    expect(await credentials.readToken(reference), legacyToken);
    expect(preferences.getString(ServerRegistrySnapshot.preferenceKey),
        isNot(contains(legacyToken)));
    expect(preferences.getString(CredentialMigration.userIdKey), 'legacy-user');
    expect(preferences.getString(CredentialMigration.serverUrlKey),
        'https://legacy.example.test/jellyfin');
    expect(await migration.migrateLegacyInstallation(), isTrue);
    expect(
        (await registry.load())
            .servers
            .single
            .accounts
            .single
            .credentialReference,
        reference);
  });

  test('migration retries a changed endpoint without changing server identity',
      () async {
    const legacyToken = 'stored-securely';
    SharedPreferences.setMockInitialValues(<String, Object>{
      CredentialMigration.serverUrlKey: 'https://first.example.test',
      CredentialMigration.userIdKey: 'user',
    });
    final preferences = await SharedPreferences.getInstance();
    final credentials = _TestCredentials()
      ..tokens[CredentialMigration.tokenKey] = legacyToken;
    final registry = PreferencesServerRegistryStore(preferences);
    final migration = ServerRegistryMigration(
      preferences: preferences,
      credentials: credentials,
      registry: registry,
    );
    expect(await migration.migrateLegacyInstallation(), isTrue);
    final stableId = ServerId(
      preferences.getString(ConfiguredServerIdStore.preferenceKey)!,
    );
    await preferences.setString(
      CredentialMigration.serverUrlKey,
      'https://second.example.test',
    );
    expect(await migration.migrateLegacyInstallation(), isTrue);
    final saved = await registry.load();
    expect(saved.servers.single.id, stableId);
    expect(saved.servers.single.endpoints.first.value,
        'https://second.example.test');
    expect(saved.servers.single.endpoints, hasLength(2));
    expect(saved.activeAccountId!.serverId, stableId);
  });

  test('migration does not reuse an active identity for a different token',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      CredentialMigration.serverUrlKey: 'https://first.example.test',
      CredentialMigration.userIdKey: 'user',
    });
    final preferences = await SharedPreferences.getInstance();
    final credentials = _TestCredentials()
      ..tokens[CredentialMigration.tokenKey] = 'token-for-first';
    final registry = PreferencesServerRegistryStore(preferences);
    final migration = ServerRegistryMigration(
      preferences: preferences,
      credentials: credentials,
      registry: registry,
    );
    await migration.migrateLegacyInstallation();
    final firstId = (await registry.load()).activeServerId;

    await preferences.setString(
      CredentialMigration.serverUrlKey,
      'https://second.example.test',
    );
    credentials.tokens[CredentialMigration.tokenKey] = 'token-for-second';
    await migration.migrateLegacyInstallation();

    final snapshot = await registry.load();
    expect(snapshot.servers, hasLength(2));
    expect(snapshot.activeServerId, isNot(firstId));
    expect(snapshot.server(firstId!)!.endpoints.single.uri.host,
        'first.example.test');
  });

  test('missing legacy credential does not create a partial record', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      CredentialMigration.serverUrlKey: 'https://legacy.example.test',
      CredentialMigration.userIdKey: 'legacy-user',
    });
    final preferences = await SharedPreferences.getInstance();
    final registry = PreferencesServerRegistryStore(preferences);
    final migrated = await ServerRegistryMigration(
      preferences: preferences,
      credentials: _TestCredentials(),
      registry: registry,
    ).migrateLegacyInstallation();
    expect(migrated, isFalse);
    expect((await registry.load()).servers, isEmpty);
  });
}

final class _TestCredentials implements CredentialStore {
  final Map<String, String> tokens = <String, String>{};

  @override
  Future<void> writeToken(String key, String token) async =>
      tokens[key] = token;

  @override
  Future<String?> readToken(String key) async => tokens[key];

  @override
  Future<void> deleteToken(String key) async => tokens.remove(key);
}
