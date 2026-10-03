import 'package:flutter/foundation.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/device/installation_identity.dart';
import 'package:rodplayer/core/models/server_identity.dart';
import 'package:rodplayer/core/network/private_network_runtime.dart';
import 'package:rodplayer/core/network/private_service_endpoint_resolver.dart';
import 'package:rodplayer/core/network/service_transport.dart';

const testIdentity = InstallationIdentity(
  deviceId: 'device-stable',
  clientName: 'Nautilus',
  deviceName: 'Test device',
  appVersion: '9.8.7',
);

final testServerId = ServerId('test-server');

void bindTestPrivateTransport(
  JellyfinApiClient client,
  ValueListenable<PrivateNetworkStatus?> status, {
  Future<void> Function()? waitUntilReady,
}) {
  final transport = client.serviceTransport;
  if (transport is! HttpServiceTransport) {
    throw StateError('Test client does not use HTTP service transport');
  }
  transport.bindPrivateResolver(
    PrivateServiceEndpointResolver(
      canonicalBaseUrl: client.baseUrl,
      status: status,
    ),
    waitUntilReady: waitUntilReady,
  );
}
