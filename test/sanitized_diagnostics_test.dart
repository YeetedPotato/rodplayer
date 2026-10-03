import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/diagnostics/sanitized_diagnostics.dart';
import 'package:rodplayer/core/downloads/download_models.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';

void main() {
  test(
      'export includes allowlisted facts and excludes private endpoints and credentials',
      () {
    final diagnostics = SanitizedDiagnostics(
      appVersion: '1.2.3',
      platform: DiagnosticPlatform.windows,
      playbackMethod: DiagnosticPlaybackMethod.directPlay,
      hasPlaySession: true,
      eventState: DiagnosticEventState.unsupported,
      errorCategory: DiagnosticErrorCategory.network,
      latency: DiagnosticLatencyBucket.under500ms,
      activeServerGeneration: 4,
      capabilities: const <String, CapabilitySupport>{
        'liveEvents': CapabilitySupport.unsupported
      },
      downloadCounts: const <DownloadJobState, int>{
        DownloadJobState.completed: 2
      },
      httpStatus: 200,
      codecClass: 'h264',
    );
    final json = diagnostics.encode();
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    expect(decoded['hasPlaySession'], isTrue);
    expect(decoded['capabilities']['liveEvents'], 'unsupported');
    expect(json.toLowerCase(), isNot(contains('token')));
    expect(json, isNot(contains('https://')));
    expect(json, isNot(contains('api_key')));
    expect(json, isNot(contains('10.0.0.')));
  });

  test('diagnostics rejects unbounded or URL-shaped labels', () {
    expect(
      () => SanitizedDiagnostics(
        appVersion: '1',
        platform: DiagnosticPlatform.unknown,
        playbackMethod: DiagnosticPlaybackMethod.unknown,
        hasPlaySession: false,
        eventState: DiagnosticEventState.unknown,
        errorCategory: DiagnosticErrorCategory.unknown,
        latency: DiagnosticLatencyBucket.unknown,
        activeServerGeneration: 0,
        capabilities: const <String, CapabilitySupport>{},
        downloadCounts: const <DownloadJobState, int>{},
        codecClass: 'https://secret.example/path?api_key=x',
      ).toJson(),
      throwsFormatException,
    );
    expect(
      () => _sample(appVersion: '1.2.3-token-secret').encode(),
      throwsArgumentError,
    );
    expect(
      () => _sample(serverDialectVersion: '100.64.0.6').encode(),
      throwsFormatException,
    );
    expect(
      () => _sample(codecClass: '192.168.1.4').encode(),
      throwsFormatException,
    );
    expect(
      () => _sample(capabilities: <String, CapabilitySupport>{
        for (var i = 0; i < 129; i++) 'capability$i': CapabilitySupport.unknown,
      }).encode(),
      throwsFormatException,
    );
  });

  test('synthetic sensitive labels are rejected across every string field', () {
    const hostileValues = <String>[
      'token marker',
      'password marker',
      'https://media.example.test/path?api_key=synthetic',
      'Authorization marker',
      '192.0.2.4',
      'fd00::4',
      'private gateway marker',
      'Headscale key marker',
    ];
    for (final value in hostileValues) {
      expect(() => _sample(appVersion: value).encode(), throwsArgumentError);
      expect(() => _sample(serverDialectVersion: value).encode(),
          throwsFormatException);
      expect(() => _sample(codecClass: value).encode(), throwsFormatException);
      expect(
        () => _sample(capabilities: <String, CapabilitySupport>{
          value: CapabilitySupport.unknown,
        }).encode(),
        throwsFormatException,
      );
    }
  });
}

SanitizedDiagnostics _sample({
  String appVersion = '1.2.3',
  String? serverDialectVersion,
  String? codecClass,
  Map<String, CapabilitySupport> capabilities =
      const <String, CapabilitySupport>{},
}) =>
    SanitizedDiagnostics(
      appVersion: appVersion,
      platform: DiagnosticPlatform.windows,
      playbackMethod: DiagnosticPlaybackMethod.directPlay,
      hasPlaySession: false,
      eventState: DiagnosticEventState.unknown,
      errorCategory: DiagnosticErrorCategory.unknown,
      latency: DiagnosticLatencyBucket.unknown,
      activeServerGeneration: 0,
      capabilities: capabilities,
      downloadCounts: const <DownloadJobState, int>{},
      serverDialectVersion: serverDialectVersion,
      codecClass: codecClass,
    );
