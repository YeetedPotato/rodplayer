import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/network/family_enrollment.dart';
import 'package:rodplayer/core/network/private_transport_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('strict v1 invitation document contains no setup credential', () {
    const valid = '{"version":1,"profileId":"owner:one",'
        '"displayName":"Family","enrollmentEndpoint":"https://owner.example/v1/enroll"}';
    final invitation = PrivateTransportInvitation.parse(valid);
    expect(invitation.profileId, 'owner:one');
    expect(invitation.enrollmentEndpoint.toString(),
        'https://owner.example/v1/enroll');
    for (final invalid in [
      '{}',
      '{"version":2,"profileId":"owner:one","displayName":"Family",'
          '"enrollmentEndpoint":"https://owner.example/v1/enroll"}',
      '{"version":1.0,"profileId":"owner:one","displayName":"Family",'
          '"enrollmentEndpoint":"https://owner.example/v1/enroll"}',
      '{"version":1,"profileId":"owner:one","displayName":"Family",'
          '"enrollmentEndpoint":"http://owner.example/v1/enroll"}',
      '{"version":1,"profileId":"owner:one","displayName":"Family",'
          '"enrollmentEndpoint":"https://owner.example/v1/enroll",'
          '"setupCode":"secret"}',
      '{"version":1,"displayName":"Family",'
          '"enrollmentEndpoint":"https://owner.example/v1/enroll"}',
    ]) {
      expect(() => PrivateTransportInvitation.parse(invalid),
          throwsFormatException);
    }
  });

  PrivateTransportProfile profile(String id,
          {String host = '100.64.0.1',
          String control = 'https://control.example.test'}) =>
      PrivateTransportProfile(
        id: id,
        displayName: 'Private service $id',
        origin: PrivateTransportProfileOrigin.custom,
        controlUrl: Uri.parse(control),
        serviceIpv4: host,
        servicePort: 3000,
      );

  test('empty by default; CRUD supports distinct opaque identities', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = PrivateTransportProfileStore(prefs);
    expect(store.all(), isEmpty);
    await store.put(profile('owner:one'));
    await store.put(profile('owner:two', host: '100.64.0.2'));
    expect(store.all().map((item) => item.id), ['owner:one', 'owner:two']);
    expect(store.find('owner:two')?.serviceIpv4, '100.64.0.2');
    await store.put(profile('owner:one', host: '100.64.0.3'));
    expect(store.find('owner:one')?.serviceIpv4, '100.64.0.3');
    await store.remove('owner:two');
    expect(store.find('owner:two'), isNull);
    expect(() => store.all().clear(), throwsUnsupportedError);
  });

  test('profile stores stable configuration, never gateway or credentials',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final store = PrivateTransportProfileStore(prefs);
    await store.put(profile('owner:one'));
    final persisted =
        prefs.getString(PrivateTransportProfileStore.preferenceKey)!;
    expect(persisted, isNot(contains('gateway')));
    expect(persisted, isNot(contains('authKey')));
    expect(persisted, isNot(contains('setupCode')));
    expect(persisted, isNot(contains('127.0.0.1')));
  });

  test('invalid configuration and malformed stored profiles fail closed',
      () async {
    expect(
        () => profile('owner:one', host: 'not-an-ip'), throwsFormatException);
    expect(
        () => PrivateTransportProfile(
              id: 'bad',
              displayName: 'bad',
              origin: PrivateTransportProfileOrigin.custom,
              controlUrl: Uri.parse('http://control.example.test'),
              serviceIpv4: '100.64.0.1',
              servicePort: 3000,
            ),
        throwsFormatException);
    final prefs = await SharedPreferences.getInstance();
    final store = PrivateTransportProfileStore(prefs);
    await store.put(profile('owner:one'));
    final decoded =
        jsonDecode(prefs.getString(PrivateTransportProfileStore.preferenceKey)!)
            as Map<String, dynamic>;
    (decoded['profiles'] as List).first['gatewayBaseUrl'] =
        'http://127.0.0.1:1234';
    await prefs.setString(
        PrivateTransportProfileStore.preferenceKey, jsonEncode(decoded));
    expect(() => store.find('owner:one'), throwsFormatException);
    expect(() => store.put(profile('owner:two')), throwsFormatException);
  });

  test('legacy claim allowed only for a unique matching configuration',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final store = PrivateTransportProfileStore(prefs);
    final first = profile('owner:one');
    await store.put(first);
    expect(store.uniquelyMatches(first), isTrue);
    await store.put(profile('owner:two'));
    expect(store.uniquelyMatches(first), isFalse);
  });

  test('control identity ignores root slash, case, and explicit HTTPS 443',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final store = PrivateTransportProfileStore(prefs);
    final first = profile('owner:one');
    await store.put(first);
    for (final equivalent in [
      'https://control.example.test/',
      'https://control.example.test:443',
      'HTTPS://CONTROL.EXAMPLE.TEST:443/',
    ]) {
      final candidate = profile('owner:two', control: equivalent);
      expect(candidate.controlUrl.toString(), 'https://control.example.test');
      expect(store.uniquelyMatches(candidate), isTrue);
      await store.put(candidate);
      expect(store.find(candidate.id)?.toJson()['controlUrl'],
          'https://control.example.test');
      expect(prefs.getString(PrivateTransportProfileStore.preferenceKey),
          isNot(contains('https://control.example.test:443')));
      expect(store.uniquelyMatches(first), isFalse);
      expect(store.uniquelyMatches(candidate), isFalse);
      await store.remove(candidate.id);
    }
    expect(first.toJson()['controlUrl'], 'https://control.example.test');
    final nondefault =
        profile('owner:three', control: 'https://control.example.test:8443/');
    expect(
        nondefault.controlUrl.toString(), 'https://control.example.test:8443');
    await store.put(nondefault);
    expect(store.uniquelyMatches(first), isTrue);
    expect(store.uniquelyMatches(nondefault), isTrue);
    final persisted =
        prefs.getString(PrivateTransportProfileStore.preferenceKey)!;
    expect(persisted, contains('https://control.example.test:8443'));
    expect(persisted, isNot(contains('https://control.example.test:443')));
  });

  test('invitation name must be trimmed, nonempty, and at most 120 chars', () {
    for (final name in ['', '  ', ' Family', 'Family ', 'x' * 121]) {
      expect(
          () => PrivateTransportInvitation(
                profileId: 'owner:one',
                displayName: name,
                enrollmentEndpoint:
                    Uri.parse('https://invite.example.test/v1/enroll'),
              ),
          throwsFormatException);
    }
    expect(
        PrivateTransportInvitation(
          profileId: 'owner:one',
          displayName: 'x' * 120,
          enrollmentEndpoint:
              Uri.parse('https://invite.example.test/v1/enroll'),
        ).displayName,
        hasLength(120));
  });

  test('owner invite creates explicit managed profile; key stays transient',
      () {
    final invite = PrivateTransportInvitation(
      profileId: 'owner:one',
      displayName: 'Family',
      enrollmentEndpoint: Uri.parse('https://invite.example.test/v1/enroll'),
    );
    final enrollment = FamilyEnrollmentResult(
      version: 1,
      controlUrl: Uri.parse('https://control.example.test'),
      authKey: 'fake-one-use-key',
      authKeyLifetime: const Duration(minutes: 5),
      homeIpv4: '100.64.0.1',
      homePort: 3000,
    );
    final managed = invite.profileFrom(enrollment);
    expect(managed.origin, PrivateTransportProfileOrigin.managedInvite);
    expect(managed.enrollmentEndpoint, invite.enrollmentEndpoint);
    expect(managed.toJson().toString(), isNot(contains('fake-one-use-key')));
    final bootstrap = invite.bootstrapFrom(enrollment);
    expect(bootstrap.profileId, managed.id);
    expect(bootstrap.authKey, 'fake-one-use-key');
    expect(bootstrap.toString(), isNot(contains('fake-one-use-key')));
  });
}
