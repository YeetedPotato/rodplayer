import 'dart:convert';

import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/downloads/download_models.dart';

enum DiagnosticPlatform { windows, macos, ios, android, linux, web, unknown }

enum DiagnosticPlaybackMethod { directPlay, directStream, transcode, unknown }

enum DiagnosticEventState {
  connected,
  reconnecting,
  unsupported,
  disabled,
  unknown
}

enum DiagnosticErrorCategory {
  network,
  authentication,
  server,
  playback,
  storage,
  protocol,
  unknown
}

enum DiagnosticLatencyBucket {
  under100ms,
  under500ms,
  under2s,
  over2s,
  unknown
}

enum AvailabilityReason {
  ready,
  serverCapability,
  platformCapability,
  playbackBackend,
  userPreference,
  activeRuntime,
  unknown
}

final class FeatureAvailability {
  const FeatureAvailability({required this.support, required this.reason});
  final CapabilitySupport support;
  final AvailabilityReason reason;
}

/// User-shareable diagnostics built only from allowlisted typed facts. There
/// are intentionally no URL, identifier, token, exception-text, or free-form
/// headers fields.
final class SanitizedDiagnostics {
  SanitizedDiagnostics({
    required this.appVersion,
    required this.platform,
    required this.playbackMethod,
    required this.hasPlaySession,
    required this.eventState,
    required this.errorCategory,
    required this.latency,
    required this.activeServerGeneration,
    required Map<String, CapabilitySupport> capabilities,
    required Map<DownloadJobState, int> downloadCounts,
    this.serverDialectVersion,
    this.httpStatus,
    this.codecClass,
  })  : capabilities =
            Map<String, CapabilitySupport>.unmodifiable(capabilities),
        downloadCounts =
            Map<DownloadJobState, int>.unmodifiable(downloadCounts) {
    if (!_validAppVersion(appVersion) || activeServerGeneration < 0)
      throw ArgumentError('Invalid diagnostics metadata');
    if (capabilities.length > 128 ||
        capabilities.keys.any((key) => !_safeCapabilityKeyValue(key))) {
      throw const FormatException('Invalid diagnostics capability inventory');
    }
    if (downloadCounts.values.any((count) => count < 0)) {
      throw ArgumentError('Invalid diagnostics download counts');
    }
    if (httpStatus != null && (httpStatus! < 100 || httpStatus! > 599))
      throw ArgumentError.value(httpStatus, 'httpStatus');
    if (serverDialectVersion != null &&
        !_safeServerDialectVersion(serverDialectVersion!)) {
      throw const FormatException('Invalid diagnostics server dialect');
    }
    if (codecClass != null && !_safeCodecClass(codecClass!)) {
      throw const FormatException('Invalid diagnostics codec class');
    }
  }

  final String appVersion;
  final DiagnosticPlatform platform;
  final DiagnosticPlaybackMethod playbackMethod;
  final bool hasPlaySession;
  final DiagnosticEventState eventState;
  final DiagnosticErrorCategory errorCategory;
  final DiagnosticLatencyBucket latency;
  final int activeServerGeneration;
  final Map<String, CapabilitySupport> capabilities;
  final Map<DownloadJobState, int> downloadCounts;
  final String? serverDialectVersion;
  final int? httpStatus;
  final String? codecClass;

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': 1,
        'appVersion': appVersion,
        'platform': platform.name,
        'playbackMethod': playbackMethod.name,
        'hasPlaySession': hasPlaySession,
        'eventState': eventState.name,
        'errorCategory': errorCategory.name,
        'latency': latency.name,
        'activeServerGeneration': activeServerGeneration,
        'capabilities': <String, String>{
          for (final entry in capabilities.entries)
            _safeCapabilityKey(entry.key): entry.value.name
        },
        'downloadCounts': <String, int>{
          for (final entry in downloadCounts.entries)
            entry.key.name: entry.value.clamp(0, 0x7fffffff)
        },
        if (serverDialectVersion != null)
          'serverDialectVersion': serverDialectVersion,
        if (httpStatus != null) 'httpStatus': httpStatus,
        if (codecClass != null) 'codecClass': codecClass,
      };

  String encode() => jsonEncode(toJson());

  static String _safeCapabilityKey(String value) {
    if (!_safeCapabilityKeyValue(value))
      throw FormatException('Invalid capability key');
    return value;
  }

  static bool _safeCapabilityKeyValue(String value) =>
      RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,39}$').hasMatch(value) &&
      !_containsSensitiveLabel(value);

  static bool _validAppVersion(String value) =>
      RegExp(
        r'^[0-9]{1,3}(?:\.[0-9]{1,3}){0,3}(?:\+[A-Za-z0-9.-]{1,24})?$',
      ).hasMatch(value) &&
      !_containsSensitiveLabel(value);

  static bool _safeServerDialectVersion(String value) => RegExp(
        r'^(?:jellyfin|emby-compatible)(?:/[0-9]{1,3}(?:\.[0-9]{1,3}){1,3})?$',
        caseSensitive: false,
      ).hasMatch(value);

  static bool _safeCodecClass(String value) => const <String>{
        'h264',
        'hevc',
        'av1',
        'vp9',
        'mpeg2video',
        'aac',
        'ac3',
        'eac3',
        'dts',
        'truehd',
        'unknown',
      }.contains(value.toLowerCase());

  static bool _containsSensitiveLabel(String value) => RegExp(
        r'(?:token|password|authorization|api_?key|headscale|gateway|https?://|\b\d{1,3}(?:\.\d{1,3}){3}\b)',
        caseSensitive: false,
      ).hasMatch(value);
}
