import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/network/private_network_runtime.dart';
import 'package:rodplayer/ui/widgets/routed_jellyfin_image.dart';

import 'test_support.dart';

void main() {
  testWidgets(
      'private image waits for usable gateway and follows port rotation',
      (tester) async {
    final status = ValueNotifier<PrivateNetworkStatus?>(null);
    final requests = <Uri>[];
    final client = JellyfinApiClient(
      baseUrl: 'https://server.example/jellyfin',
      identity: testIdentity,
      client: MockClient((request) async {
        requests.add(request.url);
        return MockClient.pngResponse();
      }),
    );
    client.usePrivateTransport(status);
    await tester.pumpWidget(MaterialApp(
        home: RoutedJellyfinImage(
      client: client,
      url: 'https://server.example/jellyfin/Items/one/Images/Primary',
      fallback: const Text('Unavailable'),
    )));
    expect(find.text('Unavailable'), findsOneWidget);
    expect(requests, isEmpty);
    status.value = _ready(40101);
    await tester.pumpAndSettle();
    expect(requests.single.port, 40101);
    status.value = _ready(40102);
    await tester.pumpAndSettle();
    expect(requests.last.port, 40102);
    expect(requests.length, 2);
    client.close();
    status.dispose();
  });

  testWidgets('same gateway retries after unavailable without periodic refetch',
      (tester) async {
    final status = ValueNotifier<PrivateNetworkStatus?>(_ready(50001));
    var sends = 0;
    final client = JellyfinApiClient(
      baseUrl: 'https://server.example/jellyfin',
      identity: testIdentity,
      client: MockClient((_) async {
        sends++;
        return sends == 1
            ? http.Response('unavailable', 503)
            : MockClient.pngResponse();
      }),
    );
    client.usePrivateTransport(status);
    await tester.pumpWidget(MaterialApp(
        home: RoutedJellyfinImage(
      client: client,
      url: 'https://server.example/jellyfin/Items/one/Images/Primary',
      fallback: const Text('Unavailable'),
    )));
    await tester.pumpAndSettle();
    expect(sends, 1);
    expect(find.text('Unavailable'), findsOneWidget);
    status.value = unavailable;
    await tester.pump();
    expect(sends, 1);
    status.value = _ready(50001);
    await tester.pumpAndSettle();
    expect(sends, 2);
    status.value = _ready(50001);
    await tester.pumpAndSettle();
    expect(sends, 2);
    client.close();
    status.dispose();
  });
}

const unavailable = PrivateNetworkStatus(
  state: PrivateNetworkState.unavailable,
  path: PrivateNetworkPath.none,
  hasPersistedIdentity: true,
  unavailableReason: PrivateNetworkUnavailableReason.directPathUnavailable,
);

PrivateNetworkStatus _ready(int port) => PrivateNetworkStatus(
      state: PrivateNetworkState.ready,
      path: PrivateNetworkPath.direct,
      hasPersistedIdentity: true,
      unavailableReason: PrivateNetworkUnavailableReason.none,
      gatewayBaseUrl: Uri.parse('http://127.0.0.1:$port'),
    );
