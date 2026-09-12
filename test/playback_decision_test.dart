import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/playback/platform_capabilities.dart';
import 'package:rodplayer/core/playback/playback_decision.dart';

void main() {
  const capabilities = DeviceCapabilities(
    profile: PlatformProfile.fireTv4kMax,
    videoCodecs: ['h264', 'hevc'],
    audioCodecs: ['aac', 'eac3'],
    containers: ['mp4', 'mkv'],
  );
  final engine = PlaybackDecisionEngine(capabilities);

  test('selects direct play for supported source', () {
    final decision = engine.decide({'Container': 'mkv', 'VideoCodec': 'h264', 'AudioCodec': 'aac', 'DirectStreamUrl': 'https://media/video'});
    expect(decision.method, PlayMethod.directPlay);
    expect(decision.url.toString(), 'https://media/video');
  });

  test('selects direct stream when direct play is unavailable', () {
    final decision = engine.decide({'Container': 'mkv', 'VideoCodec': 'h264', 'AudioCodec': 'dts', 'TranscodingUrl': 'https://media/transcode'});
    expect(decision.method, PlayMethod.directStream);
    expect(decision.reason, contains('server supplied'));
  });

  test('explains transcode requirements', () {
    final decision = engine.decide({'Container': 'avi', 'VideoCodec': 'vp9', 'AudioCodec': 'dts'});
    expect(decision.method, PlayMethod.transcode);
    expect(decision.reason, contains('unsupported'));
  });
}
