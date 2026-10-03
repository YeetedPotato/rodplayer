import 'dart:collection';

import 'package:rodplayer/core/player/playback_command_controller.dart';

enum RemoteDeviceStatus { pairing, paired, revoked, expired }

final class RemoteDeviceId {
  RemoteDeviceId(String value) : value = _required(value, 'remote device ID');
  final String value;

  @override
  bool operator ==(Object other) =>
      other is RemoteDeviceId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class PairedRemoteDevice {
  const PairedRemoteDevice(
      {required this.id,
      required this.label,
      required this.status,
      required this.pairedAt,
      this.expiresAt,
      this.revokedAt});
  final RemoteDeviceId id;
  final String label;
  final RemoteDeviceStatus status;
  final DateTime pairedAt;
  final DateTime? expiresAt;
  final DateTime? revokedAt;

  PairedRemoteDevice approve({required DateTime at}) {
    if (status != RemoteDeviceStatus.pairing) {
      throw StateError('Only a pending pairing can be approved');
    }
    if (expiresAt != null && !at.isBefore(expiresAt!)) {
      throw StateError('Expired pairing cannot be approved');
    }
    return PairedRemoteDevice(
        id: id,
        label: label,
        status: RemoteDeviceStatus.paired,
        pairedAt: at,
        expiresAt: expiresAt);
  }

  PairedRemoteDevice expire() {
    if (status != RemoteDeviceStatus.pairing &&
        status != RemoteDeviceStatus.paired) {
      throw StateError('Only an active device can expire');
    }
    return PairedRemoteDevice(
        id: id,
        label: label,
        status: RemoteDeviceStatus.expired,
        pairedAt: pairedAt,
        expiresAt: expiresAt);
  }

  PairedRemoteDevice revoke(DateTime at) => PairedRemoteDevice(
      id: id,
      label: label,
      status: RemoteDeviceStatus.revoked,
      pairedAt: pairedAt,
      expiresAt: expiresAt,
      revokedAt: at);
  bool isAuthorizedAt(DateTime now) =>
      status == RemoteDeviceStatus.paired &&
      (expiresAt == null || now.isBefore(expiresAt!));
}

sealed class CompanionMessage {
  const CompanionMessage(
      {required this.protocolVersion, required this.messageId});
  final int protocolVersion;
  final String messageId;
  String get type;
  Map<String, Object?> toJson();
}

final class CompanionHello extends CompanionMessage {
  const CompanionHello(
      {required super.protocolVersion,
      required super.messageId,
      required this.capabilities});
  final Set<String> capabilities;
  @override
  String get type => 'hello';
  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'version': protocolVersion,
        'id': messageId,
        'type': type,
        'capabilities': capabilities.toList()..sort()
      };
}

final class CompanionPlaybackState extends CompanionMessage {
  const CompanionPlaybackState(
      {required super.protocolVersion,
      required super.messageId,
      required this.playing,
      required this.positionMs,
      this.contentId});
  final bool playing;
  final int positionMs;
  final String? contentId;
  @override
  String get type => 'playbackState';
  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'version': protocolVersion,
        'id': messageId,
        'type': type,
        'playing': playing,
        'positionMs': positionMs,
        if (contentId != null) 'contentId': contentId
      };
}

enum CompanionCommandKind { play, pause, toggle, seekRelative }

final class CompanionCommandMessage extends CompanionMessage {
  const CompanionCommandMessage(
      {required super.protocolVersion,
      required super.messageId,
      required this.kind,
      this.seekMs});
  final CompanionCommandKind kind;
  final int? seekMs;

  PlaybackCommand? get command => switch (kind) {
        CompanionCommandKind.play => const PlayCommand(),
        CompanionCommandKind.pause => const PauseCommand(),
        CompanionCommandKind.toggle => const TogglePlayPauseCommand(),
        CompanionCommandKind.seekRelative => seekMs == null
            ? null
            : SeekRelativeCommand(Duration(milliseconds: seekMs!)),
      };

  @override
  String get type => 'command';
  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'version': protocolVersion,
        'id': messageId,
        'type': type,
        'command': kind.name,
        if (seekMs != null) 'seekMs': seekMs
      };
}

final class CompanionAcknowledgment extends CompanionMessage {
  const CompanionAcknowledgment(
      {required super.protocolVersion,
      required super.messageId,
      required this.status});
  final CompanionAcknowledgmentStatus status;
  @override
  String get type => 'ack';
  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'version': protocolVersion,
        'id': messageId,
        'type': type,
        'status': status.name
      };
}

enum CompanionAcknowledgmentStatus {
  executed,
  unsupported,
  staleSession,
  unauthorized,
  rateLimited,
  invalid,
  failed,
}

final class CompanionPing extends CompanionMessage {
  const CompanionPing(
      {required super.protocolVersion,
      required super.messageId,
      required this.monotonicMs});
  final int monotonicMs;
  @override
  String get type => 'ping';
  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'version': protocolVersion,
        'id': messageId,
        'type': type,
        'monotonicMs': monotonicMs
      };
}

/// Explicit allowlist decoder. Unknown versions/fields are rejected; media
/// URLs, server tokens, credentials, and arbitrary method names are not part
/// of the protocol model.
CompanionMessage decodeCompanionMessage(Map<String, Object?> json,
    {int supportedVersion = 1}) {
  final version = json['version'];
  final messageId = json['id'];
  final type = json['type'];
  if (version is! int ||
      version != supportedVersion ||
      messageId is! String ||
      !_validMessageId(messageId) ||
      type is! String) {
    throw const FormatException('Invalid or unsupported companion message');
  }
  return switch (type) {
    'hello'
        when _onlyKeys(json, const {'version', 'id', 'type', 'capabilities'}) &&
            json['capabilities'] is List &&
            _validCapabilities(json['capabilities'] as List) =>
      CompanionHello(
          protocolVersion: version,
          messageId: messageId,
          capabilities: Set<String>.from(json['capabilities'] as List)),
    'playbackState'
        when _onlyKeys(json, const {
              'version',
              'id',
              'type',
              'playing',
              'positionMs',
              'contentId'
            }) &&
            json['playing'] is bool &&
            json['positionMs'] is int &&
            (json['positionMs']! as int) >= 0 &&
            _validContentId(json['contentId']) =>
      CompanionPlaybackState(
          protocolVersion: version,
          messageId: messageId,
          playing: json['playing']! as bool,
          positionMs: json['positionMs']! as int,
          contentId: json['contentId'] is String
              ? json['contentId']! as String
              : null),
    'command'
        when _onlyKeys(
            json, const {'version', 'id', 'type', 'command', 'seekMs'}) =>
      _decodeCommand(version, messageId, json),
    'ack'
        when _onlyKeys(json, const {'version', 'id', 'type', 'status'}) &&
            json['status'] is String &&
            _decodeAck(json['status']! as String) != null =>
      CompanionAcknowledgment(
          protocolVersion: version,
          messageId: messageId,
          status: _decodeAck(json['status']! as String)!),
    'ping'
        when _onlyKeys(json, const {'version', 'id', 'type', 'monotonicMs'}) &&
            json['monotonicMs'] is int &&
            (json['monotonicMs']! as int) >= 0 =>
      CompanionPing(
          protocolVersion: version,
          messageId: messageId,
          monotonicMs: json['monotonicMs']! as int),
    _ => throw const FormatException('Unsupported companion message type'),
  };
}

CompanionCommandMessage _decodeCommand(
    int version, String id, Map<String, Object?> json) {
  final kindName = json['command'];
  CompanionCommandKind? kind;
  for (final candidate in CompanionCommandKind.values) {
    if (candidate.name == kindName) kind = candidate;
  }
  final seekMs = json['seekMs'];
  if (kind == null ||
      (kind == CompanionCommandKind.seekRelative && seekMs is! int) ||
      (seekMs != null && seekMs is! int) ||
      (seekMs is int &&
          seekMs.abs() > const Duration(minutes: 30).inMilliseconds)) {
    throw const FormatException('Invalid companion command');
  }
  return CompanionCommandMessage(
      protocolVersion: version,
      messageId: id,
      kind: kind,
      seekMs: seekMs as int?);
}

bool _onlyKeys(Map<String, Object?> json, Set<String> allowed) =>
    json.keys.every(allowed.contains);

bool _validMessageId(String value) =>
    value.length <= 128 && RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value);

bool _validCapabilities(List values) =>
    values.length <= 32 &&
    values.every((value) =>
        value is String &&
        value.length <= 64 &&
        RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value)) &&
    values.toSet().length == values.length;

bool _validContentId(Object? value) =>
    value == null ||
    (value is String &&
        value.length <= 256 &&
        !value.contains('://') &&
        !value.contains(RegExp(r'\s')));

CompanionAcknowledgmentStatus? _decodeAck(String value) {
  for (final status in CompanionAcknowledgmentStatus.values) {
    if (status.name == value) return status;
  }
  return null;
}

/// Bounded replay window using monotonic time supplied by the caller.
final class RemoteReplayWindow {
  RemoteReplayWindow(
      {this.capacity = 512, this.maxAge = const Duration(minutes: 5)}) {
    if (capacity < 1 ||
        capacity > 10000 ||
        maxAge.isNegative ||
        maxAge == Duration.zero ||
        maxAge > const Duration(days: 1)) {
      throw ArgumentError('Invalid replay-window bounds');
    }
  }
  final int capacity;
  final Duration maxAge;
  final LinkedHashMap<(String, String), Duration> _seen =
      LinkedHashMap<(String, String), Duration>();
  Duration? _lastNow;

  int get length => _seen.length;

  bool accept(String id, Duration now, {String sessionId = 'default'}) {
    if (now.isNegative ||
        id.trim().isEmpty ||
        id.length > 128 ||
        sessionId.trim().isEmpty ||
        sessionId.length > 384) {
      return false;
    }
    final previousNow = _lastNow;
    if (previousNow != null && now < previousNow) return false;
    _lastNow = now;
    _seen.removeWhere((_, at) => now >= at && now - at >= maxAge);
    final key = (sessionId, id);
    if (_seen.containsKey(key)) return false;
    _seen[key] = now;
    while (_seen.length > capacity) {
      _seen.remove(_seen.keys.first);
    }
    return true;
  }

  void clearSession(String sessionId) =>
      _seen.removeWhere((key, _) => key.$1 == sessionId);
}

/// Fixed-window per-peer control limiter. The cache is bounded by active peers
/// and callers should remove entries on disconnect/revoke.
final class RemoteControlRateLimiter {
  RemoteControlRateLimiter(
      {required this.limit,
      this.window = const Duration(seconds: 1),
      this.maxPeers = 128}) {
    if (limit < 1 ||
        limit > 10000 ||
        maxPeers < 1 ||
        maxPeers > 1024 ||
        window.isNegative ||
        window == Duration.zero)
      throw ArgumentError('Rate limiter bounds must be positive');
  }
  final int limit;
  final Duration window;
  final int maxPeers;
  final Map<String, List<Duration>> _windows = {};
  Duration? _lastNow;

  bool allow(String peerId, Duration now) {
    if (now.isNegative || peerId.isEmpty || peerId.length > 128) return false;
    final previousNow = _lastNow;
    if (previousNow != null && now < previousNow) return false;
    _lastNow = now;
    var timestamps = _windows[peerId];
    if (timestamps == null) {
      if (_windows.length >= maxPeers) _windows.remove(_windows.keys.first);
      timestamps = <Duration>[];
      _windows[peerId] = timestamps;
    }
    timestamps.removeWhere((at) => now - at >= window);
    if (timestamps.length >= limit) return false;
    timestamps.add(now);
    return true;
  }

  void removePeer(String peerId) => _windows.remove(peerId);
}

abstract interface class CompanionPeerTransport {
  Stream<Object?> get messages;
  Future<void> send(CompanionMessage message);
  Future<void> close();
}

abstract interface class CompanionDiscovery {
  Stream<Object> discover();
  Future<void> close();
}

String _required(String value, String label) {
  if (value.trim().isEmpty ||
      value.trim() != value ||
      value.length > 128 ||
      !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value))
    throw FormatException('Invalid $label');
  return value;
}
