import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/api/models/playback_info_request.dart';
import 'package:rodplayer/core/network/private_network_runtime.dart';
import 'package:rodplayer/core/network/private_service_endpoint_resolver.dart';
import 'package:rodplayer/core/network/private_transport_profile_association.dart';
import 'package:rodplayer/core/security/credential_migration.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

const canonical = 'https://media.example.test/jellyfin';

PrivateNetworkStatus ready(int port) => PrivateNetworkStatus(
      state: PrivateNetworkState.ready,
      path: PrivateNetworkPath.direct,
      hasPersistedIdentity: true,
      unavailableReason: PrivateNetworkUnavailableReason.none,
      gatewayBaseUrl: Uri.parse('http://127.0.0.1:$port'),
    );

const unavailable = PrivateNetworkStatus(
  state: PrivateNetworkState.unavailable,
  path: PrivateNetworkPath.none,
  hasPersistedIdentity: true,
  unavailableReason: PrivateNetworkUnavailableReason.directPathUnavailable,
);

void main() {
  test('association is explicit, profile-specific and stores no gateway',
      () async {
    SharedPreferences.setMockInitialValues(
        {CredentialMigration.serverUrlKey: canonical});
    final prefs = await SharedPreferences.getInstance();
    final association = PrivateTransportProfileAssociation(prefs);
    expect(association.lookupFor(canonical).kind,
        PrivateTransportAssociationKind.none);
    await association.associate(canonical, 'invite:family-a');
    expect(association.lookupFor(canonical).profileId, 'invite:family-a');
    expect(association.lookupFor('https://other.example.test').kind,
        PrivateTransportAssociationKind.none);
    expect(prefs.getString(PrivateTransportProfileAssociation.preferenceKey),
        isNot(contains('127.0.0.1')));
    await association.associate(canonical, 'custom:self-hosted-b');
    expect(association.lookupFor(canonical).profileId, 'custom:self-hosted-b');
    await prefs.setString(
        CredentialMigration.serverUrlKey, 'https://other.example.test');
    expect(association.lookupFor(canonical).kind,
        PrivateTransportAssociationKind.none);
    await association.clear();
    expect(prefs.getString(PrivateTransportProfileAssociation.preferenceKey),
        isNull);
  });

  test('present malformed association is invalid, never ordinary', () async {
    SharedPreferences.setMockInitialValues(
        {CredentialMigration.serverUrlKey: canonical});
    final prefs = await SharedPreferences.getInstance();
    final association = PrivateTransportProfileAssociation(prefs);
    for (final encoded in <String>[
      '{broken',
      '{}',
      jsonEncode({'serverUrl': canonical, 'profileId': ''}),
      jsonEncode({'serverUrl': canonical, 'profileId': '   '}),
      jsonEncode(
          {'serverUrl': 'https://wrong.example', 'profileId': 'invite:one'}),
    ]) {
      await prefs.setString(
          PrivateTransportProfileAssociation.preferenceKey, encoded);
      expect(association.lookupFor(canonical).kind,
          PrivateTransportAssociationKind.invalid);
    }
    await prefs.setInt(PrivateTransportProfileAssociation.preferenceKey, 7);
    expect(association.lookupFor(canonical).kind,
        PrivateTransportAssociationKind.invalid);
  });

  test('ordinary client never consults private status or changes canonical URL',
      () async {
    final urls = <Uri>[];
    final client = JellyfinApiClient(
      baseUrl: canonical,
      identity: testIdentity,
      client: MockClient((request) async {
        urls.add(request.url);
        return http.Response('{}', 200);
      }),
    )..userId = 'user';
    expect(client.usesPrivateTransport, isFalse);
    await client.getItem('movie');
    expect(urls.single.origin, 'https://media.example.test');
    expect(
        client
            .buildDirectPlayUri(itemId: 'movie', mediaSourceId: 'source')
            .host,
        'media.example.test');
    client.close();
  });

  test('private REST, report, image and playback URIs use current gateway',
      () async {
    final status = ValueNotifier<PrivateNetworkStatus?>(ready(41001));
    final requests = <http.Request>[];
    final client = JellyfinApiClient(
      baseUrl: canonical,
      identity: testIdentity,
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
            request.url.path.endsWith('/Items/movie')
                ? jsonEncode({'Id': 'movie', 'Type': 'Movie'})
                : '{}',
            200);
      }),
    )
      ..userId = 'user'
      ..accessToken = 'token';
    client.usePrivateTransport(status);
    expect(client.baseUrl, canonical);
    await client.getItem('movie');
    await client.getPlaybackInfo(const PlaybackInfoRequest(
        itemId: 'movie', deviceProfile: <String, dynamic>{}));
    await client.reportPlaybackProgress({'ItemId': 'movie'});
    await client
        .readServiceImage(Uri.parse('$canonical/Items/movie/Images/Primary'));
    expect(requests.map((r) => r.url.port), everyElement(41001));
    expect(requests.first.url.path, '/jellyfin/Users/user/Items/movie');
    expect(requests.first.headers['host'], 'media.example.test');
    expect(requests[1].method, 'POST');
    expect(requests[1].url.path, '/jellyfin/Items/movie/PlaybackInfo');
    expect(requests[2].body, contains('movie'));
    expect(requests[3].headers['authorization'], contains('token'));
    expect(
        client
            .buildDirectPlayUri(itemId: 'movie', mediaSourceId: 'source')
            .port,
        41001);
    expect(
        client.resolvePlaybackUri('$canonical/Videos/movie/master.m3u8').port,
        41001);
    status.value = ready(41002);
    expect(client.resolvePlaybackUri('$canonical/Videos/movie/stream').port,
        41002);
    await client.getItem('movie');
    expect(requests.last.url.port, 41002);
    client.close();
    status.dispose();
  });

  test('unready private status fails closed before any HTTP send', () async {
    final status = ValueNotifier<PrivateNetworkStatus?>(unavailable);
    var sends = 0;
    final client = JellyfinApiClient(
      baseUrl: canonical,
      identity: testIdentity,
      client: MockClient((_) async {
        sends++;
        return http.Response('{}', 200);
      }),
    )..userId = 'user';
    client.usePrivateTransport(status);
    await expectLater(
        client.getItem('movie'), throwsA(isA<PrivateNetworkException>()));
    expect(() => client.buildDirectPlayUri(itemId: 'movie', mediaSourceId: 's'),
        throwsA(isA<PrivateNetworkException>()));
    expect(sends, 0);
    client.close();
    status.dispose();
  });

  test('playback auth appends without rewriting raw query or duplicate keys',
      () {
    final status = ValueNotifier<PrivateNetworkStatus?>(ready(50001));
    final client = JellyfinApiClient(
        baseUrl: canonical,
        identity: testIdentity,
        client: MockClient((_) async => http.Response('{}', 200)))
      ..accessToken = 'token value';
    client.usePrivateTransport(status);
    final source = '$canonical/Videos/x/master.m3u8?a=a%2Bb&a=c%2Fd&empty=&z=1';
    final routed = client.resolvePlaybackUri(source);
    expect(routed.host, '127.0.0.1');
    expect(routed.query, 'a=a%2Bb&a=c%2Fd&empty=&z=1&api_key=token%20value');
    final existing =
        client.resolvePlaybackUri('$source&api_key=already%2Bhere');
    expect(existing.query, 'a=a%2Bb&a=c%2Fd&empty=&z=1&api_key=already%2Bhere');
    client.close();
    status.dispose();
  });

  test('resolver preserves encoded path/query and rejects foreign origin', () {
    final status = ValueNotifier<PrivateNetworkStatus?>(ready(44001));
    final resolver = PrivateServiceEndpointResolver(
        canonicalBaseUrl: canonical, status: status);
    final original = Uri.parse('$canonical/Videos/a%2Fb/stream?x=a%2Bb&n=1');
    final routed = resolver.resolve(original);
    expect(routed.pathSegments.last, 'stream');
    expect(routed.toString(),
        'http://127.0.0.1:44001/jellyfin/Videos/a%2Fb/stream?x=a%2Bb&n=1');
    expect(
        resolver
            .resolveWebSocket(
                Uri.parse('wss://media.example.test/jellyfin/socket'))
            .scheme,
        'ws');
    expect(
        () => resolver.resolve(Uri.parse('https://foreign.example.test/movie')),
        throwsA(isA<PrivateNetworkException>()));
    status.dispose();
  });

  test(
      'HTTP and WebSocket URLs use the live port without embedding credentials',
      () {
    final status = ValueNotifier<PrivateNetworkStatus?>(ready(50001));
    final resolver = PrivateServiceEndpointResolver(
        canonicalBaseUrl: 'http://private.example', status: status);
    expect(
      resolver
          .resolve(Uri.parse('http://private.example/Users/Me?x=1'))
          .toString(),
      'http://127.0.0.1:50001/Users/Me?x=1',
    );
    final socket = Uri.parse('ws://private.example/socket?token=sensitive');
    expect(resolver.resolveWebSocket(socket).toString(),
        'ws://127.0.0.1:50001/socket?token=sensitive');
    status.value = ready(50002);
    expect(resolver.resolveWebSocket(socket).port, 50002);
    expect(
        resolver.resolve(Uri.parse('http://private.example/subtitle.vtt')).port,
        50002);
    expect(resolver.resolve(Uri.parse('http://private.example/Users/Me')).query,
        isEmpty);
    status.value = unavailable;
    expect(() => resolver.resolveWebSocket(socket),
        throwsA(isA<PrivateNetworkException>()));
    status.dispose();
  });

  test('same-service absolute and relative redirects stay routed', () async {
    final status = ValueNotifier<PrivateNetworkStatus?>(ready(50001));
    final urls = <Uri>[];
    final hosts = <String?>[];
    final transport = PrivateServiceHttpClient(
      MockClient((request) async {
        urls.add(request.url);
        hosts.add(request.headers['host']);
        if (request.url.path == '/jellyfin/absolute') {
          return http.Response('', 302, headers: {
            'location': '$canonical/final?part=1',
          });
        }
        if (request.url.path == '/jellyfin/relative') {
          return http.Response('', 302, headers: {'location': 'final?part=2'});
        }
        return http.Response('ok', 200);
      }),
      PrivateServiceEndpointResolver(
          canonicalBaseUrl: canonical, status: status),
    );
    expect((await transport.get(Uri.parse('$canonical/absolute'))).body, 'ok');
    expect((await transport.get(Uri.parse('$canonical/relative'))).body, 'ok');
    expect(urls.map((url) => url.port), everyElement(50001));
    expect(urls[1].toString(), 'http://127.0.0.1:50001/jellyfin/final?part=1');
    expect(urls[3].toString(), 'http://127.0.0.1:50001/jellyfin/final?part=2');
    expect(hosts, everyElement('media.example.test'));
    transport.close();
    status.dispose();
  });

  test('explicit port and IPv6 canonical authority become HTTP Host', () async {
    final status = ValueNotifier<PrivateNetworkStatus?>(ready(50001));
    final captured = <http.Request>[];
    const ipv6 = 'https://[2001:db8::1]:8443/jellyfin';
    final transport = PrivateServiceHttpClient(
      MockClient((request) async {
        captured.add(request);
        return http.Response('ok', 200);
      }),
      PrivateServiceEndpointResolver(canonicalBaseUrl: ipv6, status: status),
    );
    await transport.get(Uri.parse('$ipv6/Items'));
    expect(captured.single.url.host, '127.0.0.1');
    expect(captured.single.headers['host'], '[2001:db8::1]:8443');
    await expectLater(
        transport.get(
            Uri.parse('https://name:secret@[2001:db8::1]:8443/jellyfin/Items')),
        throwsA(isA<PrivateNetworkException>()));
    expect(captured, hasLength(1));
    transport.close();
    status.dispose();
  });

  test(
      'streamed Range/body and headers survive routing; external redirect is blocked',
      () async {
    final status = ValueNotifier<PrivateNetworkStatus?>(ready(44001));
    final seen = <http.Request>[];
    final transport = PrivateServiceHttpClient(
      MockClient((request) async {
        seen.add(request);
        if (request.url.path.endsWith('/redirect')) {
          return http.Response('', 307,
              headers: {'location': 'https://outside.example.test/secret'});
        }
        return http.Response('ok', 200);
      }),
      PrivateServiceEndpointResolver(
          canonicalBaseUrl: canonical, status: status),
    );
    final request =
        http.Request('POST', Uri.parse('$canonical/Videos/movie/segment'))
          ..headers['Range'] = 'bytes=10-20'
          ..headers['Authorization'] = 'token'
          ..body = 'body';
    final response = await transport.send(request);
    expect(response.statusCode, 200);
    expect(seen.single.url.port, 44001);
    expect(seen.single.headers['range'], 'bytes=10-20');
    expect(seen.single.headers['authorization'], 'token');
    expect(seen.single.body, 'body');
    await expectLater(transport.get(Uri.parse('$canonical/redirect')),
        throwsA(isA<PrivateNetworkException>()));
    expect(seen.length, 2);
    transport.close();
    status.dispose();
  });

  test(
      'rejected external redirect cancels its response without an external send',
      () async {
    final status = ValueNotifier<PrivateNetworkStatus?>(ready(50001));
    var sends = 0;
    var cancelled = false;
    final body = StreamController<List<int>>(onCancel: () {
      cancelled = true;
    });
    final transport = PrivateServiceHttpClient(
      MockClient.streaming((request, _) async {
        sends++;
        return http.StreamedResponse(body.stream, 302, headers: {
          'location': 'https://outside.example.test/secret',
        });
      }),
      PrivateServiceEndpointResolver(
          canonicalBaseUrl: canonical, status: status),
    );
    await expectLater(transport.get(Uri.parse('$canonical/redirect')),
        throwsA(isA<PrivateNetworkException>()));
    expect(sends, 1);
    expect(cancelled, isTrue);
    await body.close();
    transport.close();
    status.dispose();
  });
}
