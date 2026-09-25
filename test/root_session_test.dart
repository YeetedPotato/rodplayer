import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/models/jellyfin_user_profile.dart';
import 'package:rodplayer/core/network/private_network_runtime.dart';
import 'package:rodplayer/core/network/private_transport_profile_association.dart';
import 'package:rodplayer/core/network/private_transport_profile.dart';
import 'package:rodplayer/core/security/credential_migration.dart';
import 'package:rodplayer/core/security/credential_store.dart';
import 'package:rodplayer/main.dart';
import 'package:rodplayer/ui/screens/login_screen.dart';
import 'package:rodplayer/ui/shell/rodplayer_app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('login discovery and sign-in share one pending private session',
      (tester) async {
    const server = 'https://server';
    SharedPreferences.setMockInitialValues({
      CredentialMigration.serverUrlKey: server,
    });
    final prefs = await SharedPreferences.getInstance();
    await PrivateTransportProfileStore(prefs).put(_profile('owner:one'));
    await PrivateTransportProfileAssociation(prefs)
        .associate(server, 'owner:one');
    final resume = Completer<PrivateNetworkStatus>();
    final resumeStarted = Completer<void>();
    final runtime = _RootPrivateNetworkRuntime(
        resumePending: resume.future, resumeStarted: resumeStarted);
    final requests = <http.Request>[];
    var runtimeCreations = 0;
    final clients = <JellyfinApiClient>[];
    await tester.pumpWidget(RodPlayerApp(
      preferences: prefs,
      credentialStore: MemoryCredentialStore(),
      privateNetworkRuntimeFactory: () {
        runtimeCreations++;
        return runtime;
      },
      clientFactory: (url, identity) {
        final client = JellyfinApiClient(
          baseUrl: url,
          identity: identity,
          client: http_testing.MockClient((request) async {
            requests.add(request);
            if (request.url.path.endsWith('/Users/Public')) {
              return http.Response('[{"Id":"user","Name":"Alice"}]', 200);
            }
            if (request.url.path.endsWith('/Users/AuthenticateByName')) {
              return http.Response('{"AccessToken":"token","User":{"Id":"user"}}', 200);
            }
            if (request.url.path.endsWith('/Users/user')) {
              return http.Response('{"Id":"user","Name":"Alice"}', 200);
            }
            return http.Response('{"Items":[]}', 200);
          }),
        );
        clients.add(client);
        return client;
      },
    ));
    await tester.pump();
    await tester.pump();
    await resumeStarted.future;
    expect(requests, isEmpty);
    expect(find.text('Could not load public profiles.'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'Username'), 'Alice');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(requests, isEmpty);
    expect(runtimeCreations, 1);
    expect(runtime.resumeCalls, 1);
    expect(clients, hasLength(2));

    resume.complete(const PrivateNetworkStatus(
      state: PrivateNetworkState.starting,
      path: PrivateNetworkPath.none,
      hasPersistedIdentity: true,
      unavailableReason: PrivateNetworkUnavailableReason.none,
    ));
    await tester.pump();
    expect(requests, isEmpty);
    runtime.events.add(PrivateNetworkStatus.fromPayload({
      'state': 'ready', 'path': 'direct', 'hasPersistedIdentity': true,
      'reason': 'none', 'gatewayUrl': 'http://127.0.0.1:45000',
    }));
    await tester.pumpAndSettle();
    expect(requests.where((r) => r.url.path == '/Users/Public'), hasLength(1));
    expect(requests.where((r) => r.url.path == '/Users/AuthenticateByName'),
        hasLength(1));
    expect(requests, everyElement(isA<http.Request>().having(
        (r) => r.url.host, 'host', '127.0.0.1')));
    expect(requests.first.headers['host'], 'server');
    expect(find.byType(RodPlayerAppShell), findsOneWidget);
    expect(runtimeCreations, 1);
    expect(runtime.resumeCalls, 1);
  });

  testWidgets(
    'ordinary public app does not start or enroll a private identity',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final runtime = _RootPrivateNetworkRuntime();
      var factoryCalls = 0;

      await tester.pumpWidget(RodPlayerApp(
        preferences: prefs,
        credentialStore: MemoryCredentialStore(),
        privateNetworkRuntimeFactory: () {
          factoryCalls++;
          return runtime;
        },
      ));
      await tester.pumpAndSettle();
      await tester.pumpWidget(RodPlayerApp(
        preferences: prefs,
        credentialStore: MemoryCredentialStore(),
        privateNetworkRuntimeFactory: () {
          factoryCalls++;
          return runtime;
        },
      ));
      await tester.pumpAndSettle();

      await PrivateTransportProfileStore(prefs).put(_profile('unrelated'));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(RodPlayerApp(
        preferences: prefs,
        credentialStore: MemoryCredentialStore(),
        privateNetworkRuntimeFactory: () {
          factoryCalls++;
          return runtime;
        },
      ));
      await tester.pumpAndSettle();
      expect(factoryCalls, 0);
      expect(runtime.resumeCalls, 0);
      expect(runtime.bootstrapCalls, 0);
      expect(runtime.resetCalls, 0);
    },
  );

  testWidgets('only a configured associated profile starts private transport',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      CredentialMigration.serverUrlKey: 'https://server',
      CredentialMigration.userIdKey: 'user',
    });
    final prefs = await SharedPreferences.getInstance();
    await PrivateTransportProfileAssociation(prefs)
        .associate('https://server', 'invite:one');
    await PrivateTransportProfileStore(prefs).put(_profile('custom:two'));
    final store = MemoryCredentialStore();
    await store.writeToken(CredentialMigration.tokenKey, 'token');
    final runtime = _RootPrivateNetworkRuntime();
    var factoryCalls = 0;
    final clients = <_RootClient>[];
    await tester.pumpWidget(RodPlayerApp(
      preferences: prefs,
      credentialStore: store,
      privateNetworkRuntimeFactory: () {
        factoryCalls++;
        return runtime;
      },
      clientFactory: (url, identity) {
        final client = _RootClient(baseUrl: url, identity: identity);
        clients.add(client);
        return client;
      },
    ));
    await tester.pumpAndSettle();
    expect(factoryCalls, 0);
    expect(clients.single.usesPrivateTransport, isTrue);
    expect(
        () =>
            clients.single.resolveServiceUri(Uri.parse('https://server/Items')),
        throwsA(isA<PrivateNetworkException>()));
    await tester.pumpWidget(const SizedBox.shrink());
    await PrivateTransportProfileStore(prefs).put(_profile('invite:one'));
    await tester.pumpWidget(RodPlayerApp(
      preferences: prefs,
      credentialStore: store,
      privateNetworkRuntimeFactory: () {
        factoryCalls++;
        return runtime;
      },
      clientFactory: (url, identity) {
        final client = _RootClient(baseUrl: url, identity: identity);
        clients.add(client);
        return client;
      },
    ));
    await tester.pumpAndSettle();
    expect(factoryCalls, 1);
    expect(clients.last.usesPrivateTransport, isTrue);
    expect(runtime.resumeCalls, 1);
    expect(runtime.lastClaim?.profileId, 'invite:one');
    expect(runtime.bootstrapCalls, 0);
    expect(runtime.resetCalls, 0);
  });

  testWidgets('saved ordinary server ignores unrelated private profiles',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      CredentialMigration.serverUrlKey: 'https://public.example.test',
      CredentialMigration.userIdKey: 'user',
    });
    final prefs = await SharedPreferences.getInstance();
    await PrivateTransportProfileStore(prefs).put(_profile('owner:unrelated'));
    final credentials = MemoryCredentialStore();
    await credentials.writeToken(CredentialMigration.tokenKey, 'token');
    var runtimeCalls = 0;
    late _RootClient client;
    await tester.pumpWidget(RodPlayerApp(
      preferences: prefs,
      credentialStore: credentials,
      privateNetworkRuntimeFactory: () {
        runtimeCalls++;
        return _RootPrivateNetworkRuntime();
      },
      clientFactory: (url, identity) =>
          client = _RootClient(baseUrl: url, identity: identity),
    ));
    await tester.pumpAndSettle();
    expect(runtimeCalls, 0);
    expect(client.usesPrivateTransport, isFalse);
    expect(
        client
            .resolveServiceUri(Uri.parse('https://public.example.test/Items')),
        Uri.parse('https://public.example.test/Items'));
  });

  testWidgets('deleted associated profile remains fail-closed after restart',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      CredentialMigration.serverUrlKey: 'https://server',
      CredentialMigration.userIdKey: 'user',
    });
    final prefs = await SharedPreferences.getInstance();
    final profiles = PrivateTransportProfileStore(prefs);
    await profiles.put(_profile('owner:one'));
    await PrivateTransportProfileAssociation(prefs)
        .associate('https://server', 'owner:one');
    final credentials = MemoryCredentialStore();
    await credentials.writeToken(CredentialMigration.tokenKey, 'token');
    var runtimeCalls = 0;
    final clients = <_RootClient>[];
    Widget app() => RodPlayerApp(
          preferences: prefs,
          credentialStore: credentials,
          privateNetworkRuntimeFactory: () {
            runtimeCalls++;
            return _RootPrivateNetworkRuntime();
          },
          clientFactory: (url, identity) {
            final client = _RootClient(baseUrl: url, identity: identity);
            clients.add(client);
            return client;
          },
        );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(runtimeCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await profiles.remove('owner:one');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(runtimeCalls, 1);
    expect(clients.last.usesPrivateTransport, isTrue);
    expect(
        () => clients.last.resolveServiceUri(Uri.parse('https://server/Items')),
        throwsA(isA<PrivateNetworkException>()));
    expect(
        PrivateTransportProfileAssociation(prefs)
            .lookupFor('https://server')
            .profileId,
        'owner:one');
  });

  for (final corrupt in <bool>[false, true]) {
    testWidgets(
        'associated ${corrupt ? "corrupt" : "missing"} profile fails closed',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        CredentialMigration.serverUrlKey: 'https://server',
        CredentialMigration.userIdKey: 'user',
      });
      final prefs = await SharedPreferences.getInstance();
      await PrivateTransportProfileAssociation(prefs)
          .associate('https://server', 'owner:missing');
      if (corrupt) {
        await prefs.setString(
            PrivateTransportProfileStore.preferenceKey, '{bad');
      }
      final credentials = MemoryCredentialStore();
      await credentials.writeToken(CredentialMigration.tokenKey, 'token');
      var factoryCalls = 0;
      late _RootClient client;
      await tester.pumpWidget(RodPlayerApp(
        preferences: prefs,
        credentialStore: credentials,
        privateNetworkRuntimeFactory: () {
          factoryCalls++;
          return _RootPrivateNetworkRuntime();
        },
        clientFactory: (url, identity) =>
            client = _RootClient(baseUrl: url, identity: identity),
      ));
      await tester.pumpAndSettle();
      expect(factoryCalls, 0);
      expect(client.usesPrivateTransport, isTrue);
      expect(() => client.resolveServiceUri(Uri.parse('https://server/Items')),
          throwsA(isA<PrivateNetworkException>()));
      await expectLater(client.getPublicUsers(),
          throwsA(isA<PrivateNetworkException>()));
    });
  }

  testWidgets(
      'native identity mismatch cannot make associated server proxyable',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      CredentialMigration.serverUrlKey: 'https://server',
      CredentialMigration.userIdKey: 'user',
    });
    final prefs = await SharedPreferences.getInstance();
    await PrivateTransportProfileStore(prefs).put(_profile('owner:one'));
    await PrivateTransportProfileAssociation(prefs)
        .associate('https://server', 'owner:one');
    final credentials = MemoryCredentialStore();
    await credentials.writeToken(CredentialMigration.tokenKey, 'token');
    final runtime = _RootPrivateNetworkRuntime(allowedProfileId: 'owner:two');
    late _RootClient client;
    await tester.pumpWidget(RodPlayerApp(
      preferences: prefs,
      credentialStore: credentials,
      privateNetworkRuntimeFactory: () => runtime,
      clientFactory: (url, identity) =>
          client = _RootClient(baseUrl: url, identity: identity),
    ));
    await tester.pumpAndSettle();
    expect(runtime.resumeCalls, 1);
    expect(runtime.lastClaim?.profileId, 'owner:one');
    expect(() => client.resolveServiceUri(Uri.parse('https://server/Items')),
        throwsA(isA<PrivateNetworkException>()));
  });

  for (final associationRecord in <String>[
    '{broken',
    jsonEncode({'serverUrl': 'https://server', 'profileId': ''}),
  ]) {
    testWidgets('corrupt private association fails closed: $associationRecord',
        (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        CredentialMigration.serverUrlKey: 'https://server',
        CredentialMigration.userIdKey: 'user',
        PrivateTransportProfileAssociation.preferenceKey: associationRecord,
      });
      final prefs = await SharedPreferences.getInstance();
      final store = MemoryCredentialStore();
      await store.writeToken(CredentialMigration.tokenKey, 'token');
      final clients = <_RootClient>[];
      var runtimeCreated = false;
      await tester.pumpWidget(RodPlayerApp(
        preferences: prefs,
        credentialStore: store,
        privateNetworkRuntimeFactory: () {
          runtimeCreated = true;
          return _RootPrivateNetworkRuntime();
        },
        clientFactory: (url, identity) {
          final client = _RootClient(baseUrl: url, identity: identity);
          clients.add(client);
          return client;
        },
      ));
      await tester.pumpAndSettle();
      expect(runtimeCreated, isFalse);
      expect(clients.single.usesPrivateTransport, isTrue);
      expect(
          () => clients.single
              .resolveServiceUri(Uri.parse('https://server/Items')),
          throwsA(isA<PrivateNetworkException>()));
    });
  }

  testWidgets('same-server user switch keeps association; new server clears it',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{
      CredentialMigration.serverUrlKey: 'https://server',
      CredentialMigration.userIdKey: 'user',
    });
    final prefs = await SharedPreferences.getInstance();
    final association = PrivateTransportProfileAssociation(prefs);
    await association.associate('https://server', 'invite:one');
    final store = MemoryCredentialStore();
    await store.writeToken(CredentialMigration.tokenKey, 'token');
    final clients = <_RootClient>[];
    await tester.pumpWidget(RodPlayerApp(
      preferences: prefs,
      credentialStore: store,
      clientFactory: (url, identity) {
        final client = _RootClient(baseUrl: url, identity: identity);
        clients.add(client);
        return client;
      },
    ));
    await tester.pumpAndSettle();
    expect(clients.first.usesPrivateTransport, isTrue);

    Future<void> switchProfile() async {
      await tester.tap(find.byTooltip('Profile'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
          find.widgetWithText(OutlinedButton, 'Switch profile'), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Switch profile'));
      await tester.pumpAndSettle();
    }

    await switchProfile();
    expect(association.lookupFor('https://server').profileId, 'invite:one');
    await tester.enterText(
        find.widgetWithText(TextField, 'Username'), 'second');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(association.lookupFor('https://server').profileId, 'invite:one');
    expect(clients.last.usesPrivateTransport, isTrue);

    await switchProfile();
    await tester.enterText(find.widgetWithText(TextField, 'Server URL'),
        'https://other.example.test');
    await tester.enterText(find.widgetWithText(TextField, 'Username'), 'third');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(prefs.getString(CredentialMigration.serverUrlKey),
        'https://other.example.test');
    expect(prefs.getString(PrivateTransportProfileAssociation.preferenceKey),
        isNull);
    expect(clients.last.usesPrivateTransport, isFalse);
  });

  testWidgets(
      'switch profile keeps server URL and full logout clears it despite server logout failure',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{
      CredentialMigration.serverUrlKey: 'https://server',
      CredentialMigration.userIdKey: 'user'
    });
    final prefs = await SharedPreferences.getInstance();
    final store = MemoryCredentialStore();
    await store.writeToken(CredentialMigration.tokenKey, 'token');
    final clients = <_RootClient>[];
    final privateNetwork = _RootPrivateNetworkRuntime();
    var privateFactoryCalls = 0;
    await tester.pumpWidget(RodPlayerApp(
      preferences: prefs,
      credentialStore: store,
      privateNetworkRuntimeFactory: () {
        privateFactoryCalls++;
        return privateNetwork;
      },
      clientFactory: (url, identity) {
        final client = _RootClient(
            baseUrl: url, identity: identity, failLogout: clients.isEmpty);
        clients.add(client);
        return client;
      },
    ));
    await tester.pumpAndSettle();
    expect(find.byType(RodPlayerAppShell), findsOneWidget);

    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.widgetWithText(OutlinedButton, 'Switch profile'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Switch profile'));
    await tester.pumpAndSettle();
    expect(clients.first.logoutCalls, 1);
    expect(clients.first.closed, isTrue);
    expect(await store.readToken(CredentialMigration.tokenKey), isNull);
    expect(prefs.getString(CredentialMigration.serverUrlKey), 'https://server');
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.widgetWithText(TextField, 'https://server'), findsOneWidget);

    clients.last.accessToken = 'token2';
    clients.last.userId = 'user2';
    await tester.enterText(find.widgetWithText(TextField, 'Username'), 'user2');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Log out'));
    await tester.pumpAndSettle();
    expect(prefs.getString(CredentialMigration.serverUrlKey), isNull);
    expect(await store.readToken(CredentialMigration.tokenKey), isNull);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(privateNetwork.resetCalls, 0);
    expect(privateFactoryCalls, 0);
  });
}

PrivateTransportProfile _profile(String id) => PrivateTransportProfile(
      id: id,
      displayName: id,
      origin: PrivateTransportProfileOrigin.custom,
      controlUrl: Uri.parse('https://control.example.test'),
      serviceIpv4: '100.64.0.1',
      servicePort: 3000,
    );

class _RootClient extends JellyfinApiClient {
  _RootClient(
      {required super.baseUrl,
      required super.identity,
      this.failLogout = false})
      : super(
            client:
                http_testing.MockClient((_) async => http.Response('{}', 200)));

  final bool failLogout;
  bool closed = false;
  int logoutCalls = 0;

  @override
  Future<void> reportSessionEnded() async {
    logoutCalls++;
    if (failLogout) throw StateError('offline');
  }

  @override
  Future<JellyfinUserProfile> getCurrentUser() async =>
      const JellyfinUserProfile(id: 'user', name: 'User');

  @override
  Future<void> authenticate(
      {required String username, required String password}) async {
    accessToken ??= 'token';
    userId ??= 'user';
  }

  @override
  void close() => closed = true;
}

class _RootPrivateNetworkRuntime implements PrivateNetworkRuntime {
  _RootPrivateNetworkRuntime({this.allowedProfileId, this.resumePending,
      this.resumeStarted});

  final String? allowedProfileId;
  final Future<PrivateNetworkStatus>? resumePending;
  final Completer<void>? resumeStarted;
  final events = StreamController<PrivateNetworkStatus>.broadcast(sync: true);
  PrivateNetworkIdentityClaim? lastClaim;
  int resumeCalls = 0;
  int bootstrapCalls = 0;
  int resetCalls = 0;

  @override
  Future<PrivateNetworkStatus> bootstrap(
    PrivateNetworkBootstrap bootstrap,
  ) async {
    bootstrapCalls++;
    throw UnsupportedError('startup must not bootstrap');
  }

  @override
  Future<bool> confirmHostAvailable() async => true;

  @override
  Future<void> reset() async => resetCalls++;

  @override
  Future<PrivateNetworkStatus> resume(PrivateNetworkIdentityClaim claim) async {
    lastClaim = claim;
    resumeCalls++;
    resumeStarted?.complete();
    if (allowedProfileId != null && allowedProfileId != claim.profileId) {
      throw const PrivateNetworkException(
          PrivateNetworkFailure.operationFailed);
    }
    if (resumePending != null) return resumePending!;
    return const PrivateNetworkStatus(
      state: PrivateNetworkState.unavailable,
      path: PrivateNetworkPath.none,
      hasPersistedIdentity: true,
      unavailableReason: PrivateNetworkUnavailableReason.hostUnavailable,
    );
  }

  @override
  Future<PrivateNetworkStatus> status() async => const PrivateNetworkStatus(
        state: PrivateNetworkState.stopped,
        path: PrivateNetworkPath.none,
        hasPersistedIdentity: true,
        unavailableReason: PrivateNetworkUnavailableReason.none,
      );

  @override
  Stream<PrivateNetworkStatus> get statuses => events.stream;

  @override
  Future<void> stop() async {}
}
