import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rodplayer/core/network/family_enrollment.dart';
import 'package:rodplayer/core/network/managed_private_transport_setup.dart';
import 'package:rodplayer/core/network/private_network_runtime.dart';
import 'package:rodplayer/core/network/private_transport_profile.dart';
import 'package:rodplayer/core/network/private_transport_profile_association.dart';
import 'package:rodplayer/core/security/credential_migration.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _server = 'https://media.example.test:3000';
const _invitation = '{"version":1,"profileId":"owner:family",'
    '"displayName":"Family","enrollmentEndpoint":"https://owner.example/v1/enroll"}';
const _code = 'setup-code-sentinel';
final _key = 'hskey-auth-${'a' * 12}-${'b' * 64}';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'enrolls only at owner endpoint, boots, stops, then persists stable keys',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final runtime = _SetupRuntime();
    Uri? endpoint;
    String? submittedCode;
    final setup = ManagedPrivateTransportSetup(
      preferences: prefs,
      runtimeFactory: () {
        expect(
            prefs.containsKey(PrivateTransportProfileAssociation.preferenceKey),
            isFalse);
        return runtime;
      },
      enrollmentClientFactory: (uri) {
        endpoint = uri;
        return FamilyEnrollmentClient(
            endpoint: uri,
            client: MockClient((request) async {
              submittedCode =
                  (jsonDecode(request.body) as Map)['code'] as String;
              expect(request.url, uri);
              return http.Response(
                  jsonEncode({
                    'version': 1,
                    'control_url': 'https://control.owner.example',
                    'auth_key': _key,
                    'auth_key_expires_in_seconds': 600,
                    'home': {'ipv4': '100.64.0.8', 'port': 4444},
                  }),
                  200);
            }));
      },
    );
    await setup.configure(
        canonicalServerUrl: _server,
        invitationText: _invitation,
        setupCode: _code);
    expect(endpoint.toString(), 'https://owner.example/v1/enroll');
    expect(submittedCode, _code);
    expect(runtime.bootstrapValue?.authKey, _key);
    expect(runtime.bootstrapValue?.profileId, 'owner:family');
    expect(runtime.stopCalls, 1);
    expect(runtime.resetCalls, 0);
    expect(prefs.getString(CredentialMigration.serverUrlKey), _server);
    final profile = PrivateTransportProfileStore(prefs).find('owner:family')!;
    expect(profile.controlUrl.toString(), 'https://control.owner.example');
    expect(profile.serviceIpv4, '100.64.0.8');
    expect(profile.servicePort, 4444);
    expect(
        PrivateTransportProfileAssociation(prefs).lookupFor(_server).profileId,
        profile.id);
    expect(prefs.getKeys().map((key) => prefs.get(key)).join('|'),
        isNot(anyOf(contains(_code), contains(_key), contains('127.0.0.1'))));
  });

  test('failed temporary stop prevents stable persistence', () async {
    final prefs = await SharedPreferences.getInstance();
    final runtime = _SetupRuntime(failStop: true);
    await expectLater(
      _setup(prefs, runtime).configure(
          canonicalServerUrl: _server,
          invitationText: _invitation,
          setupCode: _code),
      throwsA(isA<StateError>()),
    );
    expect(runtime.stopCalls, 1);
    expect(runtime.resetCalls, 0);
    expect(prefs.getKeys(), isEmpty);
  });

  test('bootstrap failure leaves server ordinary and never resets identity',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final runtime = _SetupRuntime(failBootstrap: true);
    await expectLater(
      _setup(prefs, runtime).configure(
          canonicalServerUrl: _server,
          invitationText: _invitation,
          setupCode: _code),
      throwsA(isA<StateError>()),
    );
    expect(runtime.stopCalls, 0);
    expect(runtime.resetCalls, 0);
    expect(prefs.getKeys(), isEmpty);
    expect(PrivateTransportProfileAssociation(prefs).lookupFor(_server).kind,
        PrivateTransportAssociationKind.none);
  });

  test('pre-existing identity is not stopped after rejected bootstrap',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final runtime = _SetupRuntime(failBootstrap: true, priorIdentity: true);
    await expectLater(
      _setup(prefs, runtime).configure(
          canonicalServerUrl: _server,
          invitationText: _invitation,
          setupCode: _code),
      throwsA(isA<StateError>()),
    );
    expect(runtime.stopCalls, 0);
    expect(runtime.resetCalls, 0);
    expect(prefs.getKeys(), isEmpty);
  });

  test('native bootstrap failure is propagated without Dart cleanup', () async {
    final prefs = await SharedPreferences.getInstance();
    final runtime = _SetupRuntime(failBootstrap: true);
    await expectLater(
      _setup(prefs, runtime).configure(
          canonicalServerUrl: _server,
          invitationText: _invitation,
          setupCode: _code),
      throwsA(isA<StateError>().having((error) => error.message, 'message',
          'incompatible retained identity')),
    );
    expect(runtime.stopCalls, 0);
    expect(runtime.resetCalls, 0);
  });

  test('non-proxyable bootstrap does not persist or reset', () async {
    final prefs = await SharedPreferences.getInstance();
    final runtime = _SetupRuntime(ready: false);
    await expectLater(
      _setup(prefs, runtime).configure(
          canonicalServerUrl: _server,
          invitationText: _invitation,
          setupCode: _code),
      throwsA(isA<StateError>()),
    );
    expect(runtime.stopCalls, 1);
    expect(runtime.resetCalls, 0);
    expect(prefs.getKeys(), isEmpty);
  });

  test('starting bootstrap waits for monitored gateway before persisting',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final runtime = _SetupRuntime(ready: false, starting: true);
    final configure = _setup(prefs, runtime).configure(
        canonicalServerUrl: _server,
        invitationText: _invitation,
        setupCode: _code);
    await runtime.bootstrapStarted.future;
    expect(prefs.getKeys(), isEmpty);
    expect(runtime.stopCalls, 0);
    runtime.emit(PrivateNetworkStatus.fromPayload({
      'state': 'ready',
      'path': 'direct',
      'hasPersistedIdentity': true,
      'reason': 'none',
      'gatewayUrl': 'http://127.0.0.1:45678',
    }));
    await configure;
    expect(runtime.stopCalls, 1);
    expect(
        PrivateTransportProfileAssociation(prefs).lookupFor(_server).profileId,
        'owner:family');
  });

  test('early ready superseded by unavailable cannot authorize setup',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final runtime =
        _SetupRuntime(ready: false, starting: true, bootstrapEvents: [
      PrivateNetworkStatus.fromPayload({
        'state': 'ready',
        'path': 'direct',
        'hasPersistedIdentity': true,
        'reason': 'none',
        'gatewayUrl': 'http://127.0.0.1:45678',
      }),
      const PrivateNetworkStatus(
        state: PrivateNetworkState.unavailable,
        path: PrivateNetworkPath.none,
        hasPersistedIdentity: true,
        unavailableReason:
            PrivateNetworkUnavailableReason.directPathUnavailable,
      ),
    ]);
    final configure = _setup(prefs, runtime).configure(
        canonicalServerUrl: _server,
        invitationText: _invitation,
        setupCode: _code);
    await runtime.bootstrapStarted.future;
    await Future<void>.value();
    expect(prefs.containsKey(PrivateTransportProfileAssociation.preferenceKey),
        isFalse);
    expect(runtime.stopCalls, 0);
    runtime.emit(PrivateNetworkStatus.fromPayload({
      'state': 'ready',
      'path': 'direct',
      'hasPersistedIdentity': true,
      'reason': 'none',
      'gatewayUrl': 'http://127.0.0.1:45679',
    }));
    await configure;
    expect(runtime.stopCalls, 1);
  });

  test('newer unavailable event overrides a ready bootstrap result', () async {
    final prefs = await SharedPreferences.getInstance();
    final runtime = _SetupRuntime(bootstrapEvents: [
      const PrivateNetworkStatus(
        state: PrivateNetworkState.unavailable,
        path: PrivateNetworkPath.none,
        hasPersistedIdentity: true,
        unavailableReason:
            PrivateNetworkUnavailableReason.directPathUnavailable,
      ),
    ]);
    await expectLater(
      _setup(prefs, runtime).configure(
          canonicalServerUrl: _server,
          invitationText: _invitation,
          setupCode: _code),
      throwsA(isA<StateError>()),
    );
    expect(prefs.getKeys(), isEmpty);
    expect(runtime.stopCalls, 1);
    expect(runtime.resetCalls, 0);
  });

  test('post-bootstrap status can supersede an older cached event', () async {
    final prefs = await SharedPreferences.getInstance();
    final runtime = _SetupRuntime(
      bootstrapEvents: [
        const PrivateNetworkStatus(
          state: PrivateNetworkState.stopped,
          path: PrivateNetworkPath.none,
          hasPersistedIdentity: false,
          unavailableReason: PrivateNetworkUnavailableReason.none,
        ),
      ],
      statusAfterBootstrap: _readyStatus(),
    );
    await _setup(prefs, runtime).configure(
        canonicalServerUrl: _server,
        invitationText: _invitation,
        setupCode: _code);
    expect(PrivateTransportProfileAssociation(prefs).lookupFor(_server).kind,
        PrivateTransportAssociationKind.associated);
    expect(runtime.stopCalls, 1);
  });

  test('event arriving during status read supersedes its stale result',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final statusRead = Completer<PrivateNetworkStatus>();
    final runtime = _SetupRuntime(postBootstrapStatus: statusRead);
    final configure = _setup(prefs, runtime).configure(
        canonicalServerUrl: _server,
        invitationText: _invitation,
        setupCode: _code);
    await runtime.postBootstrapStatusStarted.future;
    runtime.emit(const PrivateNetworkStatus(
      state: PrivateNetworkState.unavailable,
      path: PrivateNetworkPath.none,
      hasPersistedIdentity: true,
      unavailableReason: PrivateNetworkUnavailableReason.directPathUnavailable,
    ));
    statusRead.complete(_readyStatus());
    await expectLater(configure, throwsA(isA<StateError>()));
    expect(prefs.getKeys(), isEmpty);
    expect(runtime.stopCalls, 1);
    expect(runtime.resetCalls, 0);
  });

  test('persistence failure restores prior values, never resets native state',
      () async {
    SharedPreferences.setMockInitialValues({
      CredentialMigration.serverUrlKey: 'https://old.example',
      PrivateTransportProfileStore.preferenceKey: '{malformed',
      PrivateTransportProfileAssociation.preferenceKey: 'old-association',
    });
    final prefs = await SharedPreferences.getInstance();
    final before = {for (final key in prefs.getKeys()) key: prefs.get(key)};
    final runtime = _SetupRuntime();
    await expectLater(
      _setup(prefs, runtime).configure(
          canonicalServerUrl: _server,
          invitationText: _invitation,
          setupCode: _code),
      throwsA(isA<FormatException>()),
    );
    expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, before);
    expect(runtime.stopCalls, 1);
    expect(runtime.resetCalls, 0);
  });

  for (final stage in [_FailAfter.profile, _FailAfter.association]) {
    test('late $stage write failure restores all raw preference values',
        () async {
      SharedPreferences.setMockInitialValues({
        CredentialMigration.serverUrlKey: 'https://old.example',
        PrivateTransportProfileStore.preferenceKey:
            '{"version":1,"profiles":[]}',
        PrivateTransportProfileAssociation.preferenceKey: 'old-association',
      });
      final prefs = await SharedPreferences.getInstance();
      final before = {for (final key in prefs.getKeys()) key: prefs.get(key)};
      final runtime = _SetupRuntime();
      var enrollments = 0;
      await expectLater(
        _setup(prefs, runtime,
                persistence: _FailingPersistence(stage),
                onEnroll: () => enrollments++)
            .configure(
                canonicalServerUrl: _server,
                invitationText: _invitation,
                setupCode: _code),
        throwsA(isA<StateError>()),
      );
      expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, before);
      expect(prefs.getKeys().map((key) => prefs.get(key)).join('|'),
          isNot(anyOf(contains(_code), contains(_key), contains('127.0.0.1'))));
      expect(enrollments, 1);
      expect(runtime.bootstrapCalls, 1);
      expect(runtime.stopCalls, 1);
      expect(runtime.resetCalls, 0);
    });
  }

  test('marker write failure changes no stable state', () async {
    final prefs = await SharedPreferences.getInstance();
    final runtime = _SetupRuntime();
    await expectLater(
      _setup(prefs, runtime,
              persistence: const _FaultPersistence(failMarkerWrite: true))
          .configure(
              canonicalServerUrl: _server,
              invitationText: _invitation,
              setupCode: _code),
      throwsA(isA<StateError>()),
    );
    expect(prefs.getKeys(), isEmpty);
    expect(runtime.stopCalls, 1);
    expect(runtime.resetCalls, 0);
  });

  test('failed canonical restore retains marker across preference reload',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final runtime = _SetupRuntime();
    var enrollments = 0;
    await expectLater(
      _setup(prefs, runtime,
              persistence: const _FaultPersistence(
                  failAfterProfile: true, failServerRestore: true),
              onEnroll: () => enrollments++)
          .configure(
              canonicalServerUrl: _server,
              invitationText: _invitation,
              setupCode: _code),
      throwsA(isA<StateError>()),
    );
    await prefs.reload();
    expect(
        prefs.containsKey(PrivateTransportProfileAssociation.pendingSetupKey),
        isTrue);
    expect(PrivateTransportProfileAssociation(prefs).lookupFor(_server).kind,
        PrivateTransportAssociationKind.invalid);
    expect(enrollments, 1);
    expect(runtime.bootstrapCalls, 1);
    expect(runtime.resetCalls, 0);
  });

  test('thrown association restore retains marker and blocks routing',
      () async {
    SharedPreferences.setMockInitialValues({
      CredentialMigration.serverUrlKey: 'https://old.example',
      PrivateTransportProfileStore.preferenceKey: '{"version":1,"profiles":[]}',
      PrivateTransportProfileAssociation.preferenceKey: 'old-association',
    });
    final prefs = await SharedPreferences.getInstance();
    final runtime = _SetupRuntime();
    var enrollments = 0;
    await expectLater(
      _setup(prefs, runtime,
              persistence: const _FaultPersistence(
                  failAfterAssociation: true, throwAssociationRestore: true),
              onEnroll: () => enrollments++)
          .configure(
              canonicalServerUrl: _server,
              invitationText: _invitation,
              setupCode: _code),
      throwsA(isA<StateError>()),
    );
    await prefs.reload();
    expect(PrivateTransportProfileAssociation(prefs).lookupFor(_server).kind,
        PrivateTransportAssociationKind.invalid);
    expect(enrollments, 1);
    expect(runtime.bootstrapCalls, 1);
    expect(runtime.resetCalls, 0);
  });

  test('failed late write restores previously absent raw values', () async {
    final prefs = await SharedPreferences.getInstance();
    await expectLater(
      _setup(prefs, _SetupRuntime(),
              persistence: const _FaultPersistence(failAfterProfile: true))
          .configure(
              canonicalServerUrl: _server,
              invitationText: _invitation,
              setupCode: _code),
      throwsA(isA<StateError>()),
    );
    expect(prefs.getKeys(), isEmpty);
  });

  test('failed marker clear leaves completed writes fail-closed', () async {
    final prefs = await SharedPreferences.getInstance();
    await expectLater(
      _setup(prefs, _SetupRuntime(),
              persistence: const _FaultPersistence(failMarkerClear: true))
          .configure(
              canonicalServerUrl: _server,
              invitationText: _invitation,
              setupCode: _code),
      throwsA(isA<StateError>()),
    );
    await prefs.reload();
    expect(prefs.getString(CredentialMigration.serverUrlKey), _server);
    expect(PrivateTransportProfileAssociation(prefs).lookupFor(_server).kind,
        PrivateTransportAssociationKind.invalid);
    expect(prefs.getString(PrivateTransportProfileAssociation.pendingSetupKey),
        isNot(anyOf(contains(_code), contains(_key), contains('127.0.0.1'))));
  });

  test('ambiguous marker removal keeps verified routing private', () async {
    final prefs = await SharedPreferences.getInstance();
    final runtime = _SetupRuntime();
    await expectLater(
      _setup(prefs, runtime, persistence: _AmbiguousClearPersistence())
          .configure(
              canonicalServerUrl: _server,
              invitationText: _invitation,
              setupCode: _code),
      throwsA(isA<StateError>()),
    );
    await prefs.reload();
    expect(
        prefs.containsKey(PrivateTransportProfileAssociation.pendingSetupKey),
        isFalse);
    expect(PrivateTransportProfileAssociation(prefs).lookupFor(_server).kind,
        PrivateTransportAssociationKind.associated);
    expect(PrivateTransportProfileStore(prefs).find('owner:family'), isNotNull);
    expect(runtime.resetCalls, 0);
  });

  for (final failsBootstrap in [true, false]) {
    test(
        'failed cancellation poisons later setup: bootstrap fails=$failsBootstrap',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final gate = ManagedPrivateTransportTeardownGate();
      var subscriptions = 0;
      final events = StreamController<PrivateNetworkStatus>(
        sync: true,
        onListen: () => subscriptions++,
        onCancel: () => throw StateError('sensitive-cancellation-detail'),
      );
      addTearDown(events.close);
      final runtime = _SetupRuntime(
          failBootstrap: failsBootstrap, statusStream: events.stream);
      var enrollments = 0;
      final first = _setup(prefs, runtime,
          teardownGate: gate, onEnroll: () => enrollments++);
      await expectLater(
        first.configure(
            canonicalServerUrl: _server,
            invitationText: _invitation,
            setupCode: _code),
        throwsA(isA<StateError>()),
      );
      expect(prefs.getKeys(), isEmpty);
      final second = _setup(prefs, runtime,
          teardownGate: gate, onEnroll: () => enrollments++);
      await expectLater(
        second.configure(
            canonicalServerUrl: _server,
            invitationText: _invitation,
            setupCode: _code),
        throwsA(isA<StateError>().having((error) => error.message, 'message',
            isNot(contains('sensitive-cancellation-detail')))),
      );
      expect(enrollments, 1);
      expect(runtime.bootstrapCalls, 1);
      expect(subscriptions, 1);
      expect(runtime.stopCalls, failsBootstrap ? 0 : 1);
      expect(runtime.resetCalls, 0);
    });
  }

  test('confirmed cancellation does not poison a later setup', () async {
    final prefs = await SharedPreferences.getInstance();
    final gate = ManagedPrivateTransportTeardownGate();
    var enrollments = 0;
    for (var i = 0; i < 2; i++) {
      await _setup(prefs, _SetupRuntime(),
              teardownGate: gate, onEnroll: () => enrollments++)
          .configure(
              canonicalServerUrl: _server,
              invitationText: _invitation,
              setupCode: _code);
    }
    expect(enrollments, 2);
  });

  test('pending setup blocks only its target server and survives reload',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        PrivateTransportProfileAssociation.pendingSetupKey,
        PrivateTransportProfileAssociation.pendingSetupRecord(
            _server, 'owner:family'));
    await prefs.reload();
    final associations = PrivateTransportProfileAssociation(prefs);
    expect(associations.lookupFor(_server).kind,
        PrivateTransportAssociationKind.invalid);
    expect(associations.lookupFor('https://public.example').kind,
        PrivateTransportAssociationKind.none);
  });

  for (final corrupt in <String>[
    '{broken',
    jsonEncode({'version': 1, 'serverUrl': '', 'profileId': 'owner:family'}),
    jsonEncode({
      'version': 1,
      'serverUrl': 'ftp://server',
      'profileId': 'owner:family'
    }),
    jsonEncode({
      'version': 1,
      'serverUrl': 'https://user@server',
      'profileId': 'owner:family'
    }),
    jsonEncode({
      'version': 1,
      'serverUrl': 'https://server?q=1',
      'profileId': 'owner:family'
    }),
    jsonEncode({
      'version': 1,
      'serverUrl': 'https://server#f',
      'profileId': 'owner:family'
    }),
    jsonEncode(
        {'version': 2, 'serverUrl': _server, 'profileId': 'owner:family'}),
    jsonEncode(
        {'version': 1.0, 'serverUrl': _server, 'profileId': 'owner:family'}),
    jsonEncode({'version': 1, 'profileId': 'owner:family'}),
    jsonEncode({
      'version': 1,
      'serverUrl': _server,
      'profileId': 'owner:family',
      'extra': true
    }),
    jsonEncode({'version': 1, 'serverUrl': _server, 'profileId': ' '}),
  ]) {
    test('corrupt present marker blocks direct routing: $corrupt', () async {
      SharedPreferences.setMockInitialValues({
        CredentialMigration.serverUrlKey: _server,
        PrivateTransportProfileAssociation.pendingSetupKey: corrupt,
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(PrivateTransportProfileAssociation(prefs).lookupFor(_server).kind,
          PrivateTransportAssociationKind.invalid);
    });
  }
}

ManagedPrivateTransportSetup _setup(
        SharedPreferences prefs, _SetupRuntime runtime,
        {ManagedPrivateTransportPersistence persistence =
            const ManagedPrivateTransportPersistence(),
        ManagedPrivateTransportTeardownGate? teardownGate,
        void Function()? onEnroll}) =>
    ManagedPrivateTransportSetup(
      preferences: prefs,
      runtimeFactory: () => runtime,
      persistence: persistence,
      teardownGate: teardownGate ?? ManagedPrivateTransportTeardownGate(),
      enrollmentClientFactory: (endpoint) => FamilyEnrollmentClient(
        endpoint: endpoint,
        client: MockClient((_) async {
          onEnroll?.call();
          return http.Response(
              jsonEncode({
                'version': 1,
                'control_url': 'https://control.owner.example',
                'auth_key': _key,
                'auth_key_expires_in_seconds': 600,
                'home': {'ipv4': '100.64.0.8', 'port': 4444},
              }),
              200);
        }),
      ),
    );

enum _FailAfter { profile, association }

class _FailingPersistence extends ManagedPrivateTransportPersistence {
  const _FailingPersistence(this.stage);

  final _FailAfter stage;

  @override
  Future<void> saveProfile(
      SharedPreferences preferences, PrivateTransportProfile profile) async {
    await super.saveProfile(preferences, profile);
    if (stage == _FailAfter.profile) throw StateError('profile write failed');
  }

  @override
  Future<void> associate(
      SharedPreferences preferences, String serverUrl, String profileId) async {
    await super.associate(preferences, serverUrl, profileId);
    if (stage == _FailAfter.association) {
      throw StateError('association write failed');
    }
  }
}

class _FaultPersistence extends ManagedPrivateTransportPersistence {
  const _FaultPersistence({
    this.failMarkerWrite = false,
    this.failAfterProfile = false,
    this.failAfterAssociation = false,
    this.failServerRestore = false,
    this.throwAssociationRestore = false,
    this.failMarkerClear = false,
  });

  final bool failMarkerWrite;
  final bool failAfterProfile;
  final bool failAfterAssociation;
  final bool failServerRestore;
  final bool throwAssociationRestore;
  final bool failMarkerClear;

  @override
  Future<bool> setString(
      SharedPreferences preferences, String key, String value) async {
    if (failMarkerWrite &&
        key == PrivateTransportProfileAssociation.pendingSetupKey) {
      return false;
    }
    if (failServerRestore &&
        key == CredentialMigration.serverUrlKey &&
        value == 'https://old.example') {
      return false;
    }
    if (throwAssociationRestore &&
        key == PrivateTransportProfileAssociation.preferenceKey &&
        value == 'old-association') {
      throw StateError('restore failed');
    }
    return super.setString(preferences, key, value);
  }

  @override
  Future<bool> remove(SharedPreferences preferences, String key) async {
    if (failServerRestore && key == CredentialMigration.serverUrlKey) {
      return false;
    }
    if (failMarkerClear &&
        key == PrivateTransportProfileAssociation.pendingSetupKey) {
      return false;
    }
    return super.remove(preferences, key);
  }

  @override
  Future<void> saveProfile(
      SharedPreferences preferences, PrivateTransportProfile profile) async {
    await super.saveProfile(preferences, profile);
    if (failAfterProfile) throw StateError('profile write failed');
  }

  @override
  Future<void> associate(
      SharedPreferences preferences, String serverUrl, String profileId) async {
    await super.associate(preferences, serverUrl, profileId);
    if (failAfterAssociation) throw StateError('association write failed');
  }
}

class _AmbiguousClearPersistence extends ManagedPrivateTransportPersistence {
  var markerWrites = 0;

  @override
  Future<bool> setString(
      SharedPreferences preferences, String key, String value) async {
    if (key == PrivateTransportProfileAssociation.pendingSetupKey &&
        ++markerWrites > 1) {
      return false;
    }
    return super.setString(preferences, key, value);
  }

  @override
  Future<bool> remove(SharedPreferences preferences, String key) async {
    if (key == PrivateTransportProfileAssociation.pendingSetupKey) {
      await super.remove(preferences, key);
      return false;
    }
    return super.remove(preferences, key);
  }
}

PrivateNetworkStatus _readyStatus() => PrivateNetworkStatus.fromPayload({
      'state': 'ready',
      'path': 'direct',
      'hasPersistedIdentity': true,
      'reason': 'none',
      'gatewayUrl': 'http://127.0.0.1:45678',
    });

class _SetupRuntime implements PrivateNetworkRuntime {
  _SetupRuntime(
      {this.failBootstrap = false,
      this.ready = true,
      this.starting = false,
      this.bootstrapEvents = const [],
      this.priorIdentity = false,
      this.statusAfterBootstrap,
      this.postBootstrapStatus,
      this.failStop = false,
      this.statusStream});

  final bool failBootstrap;
  final bool ready;
  final bool starting;
  final List<PrivateNetworkStatus> bootstrapEvents;
  final bool priorIdentity;
  final PrivateNetworkStatus? statusAfterBootstrap;
  final Completer<PrivateNetworkStatus>? postBootstrapStatus;
  final bool failStop;
  final Stream<PrivateNetworkStatus>? statusStream;
  final bootstrapStarted = Completer<void>();
  final postBootstrapStatusStarted = Completer<void>();
  final events = StreamController<PrivateNetworkStatus>.broadcast(sync: true);
  PrivateNetworkBootstrap? bootstrapValue;
  PrivateNetworkStatus? currentStatus;
  int bootstrapCalls = 0;
  int statusCalls = 0;
  int stopCalls = 0;
  int resetCalls = 0;

  @override
  Future<PrivateNetworkStatus> bootstrap(PrivateNetworkBootstrap value) async {
    bootstrapCalls++;
    bootstrapValue = value;
    bootstrapStarted.complete();
    if (failBootstrap) throw StateError('incompatible retained identity');
    for (final status in bootstrapEvents) {
      emit(status);
    }
    final result = PrivateNetworkStatus(
      state: ready
          ? PrivateNetworkState.ready
          : starting
              ? PrivateNetworkState.starting
              : PrivateNetworkState.unavailable,
      path: ready ? PrivateNetworkPath.direct : PrivateNetworkPath.none,
      hasPersistedIdentity: true,
      unavailableReason: ready || starting
          ? PrivateNetworkUnavailableReason.none
          : PrivateNetworkUnavailableReason.hostUnavailable,
      gatewayBaseUrl: ready ? Uri.parse('http://127.0.0.1:45678') : null,
    );
    currentStatus = statusAfterBootstrap ?? currentStatus ?? result;
    return result;
  }

  void emit(PrivateNetworkStatus status) {
    currentStatus = status;
    events.add(status);
  }

  @override
  Future<bool> confirmHostAvailable() async => true;

  @override
  Future<PrivateNetworkStatus> resume(
          PrivateNetworkIdentityClaim claim) async =>
      throw UnimplementedError();

  @override
  Future<PrivateNetworkStatus> status() async {
    if (++statusCalls == 1 && postBootstrapStatus != null) {
      postBootstrapStatusStarted.complete();
      return postBootstrapStatus!.future;
    }
    return currentStatus ??
        PrivateNetworkStatus(
          state: PrivateNetworkState.stopped,
          path: PrivateNetworkPath.none,
          hasPersistedIdentity: priorIdentity,
          unavailableReason: PrivateNetworkUnavailableReason.none,
        );
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    if (failStop) throw StateError('stop failed');
  }

  @override
  Future<void> reset() async => resetCalls++;

  @override
  Stream<PrivateNetworkStatus> get statuses => statusStream ?? events.stream;
}
