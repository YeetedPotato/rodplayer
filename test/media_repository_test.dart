import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/playback/media_repository.dart';
import 'package:rodplayer/core/playback/platform_capabilities.dart';
import 'package:rodplayer/core/playback/playback_decision.dart';

void main() {
  final repository = MediaRepository(
    capabilities: const DeviceCapabilities(
      profile: PlatformProfile.fireTv4kMax,
      videoCodecs: ['h264', 'hevc'],
      audioCodecs: ['aac', 'eac3'],
      containers: ['mp4', 'mkv'],
    ),
  );

  test('selects direct play from a compatible media source', () {
    final decision = repository.selectStream({
      'MediaSources': [
        {
          'Container': 'mkv',
          'VideoCodec': 'hevc',
          'AudioCodec': 'eac3',
          'DirectStreamUrl': 'https://media.example/direct.mkv',
        },
      ],
    });

    expect(decision.method, PlayMethod.directPlay);
    expect(decision.url, Uri.parse('https://media.example/direct.mkv'));
    expect(decision.reason, 'Direct play: mkv, hevc, eac3');
  });

  test('prefers a later direct stream/remux source over an earlier fallback', () {
    final decision = repository.selectStream({
      'MediaSources': [
        {
          'Container': 'avi',
          'VideoCodec': 'vp9',
          'AudioCodec': 'dts',
        },
        {
          'Container': 'mkv',
          'VideoCodec': 'hevc',
          'AudioCodec': 'dts',
          'TranscodingUrl': 'https://media.example/remux.mkv',
        },
      ],
    });

    expect(decision.method, PlayMethod.directStream);
    expect(decision.url, Uri.parse('https://media.example/remux.mkv'));
    expect(decision.reason, contains('server supplied a playable URL'));
  });

  test('falls back to transcode with codec and container reasons', () {
    final decision = repository.selectStream({
      'MediaSources': [
        {
          'Container': 'avi',
          'VideoCodec': 'vp9',
          'AudioCodec': 'dts',
        },
      ],
    });

    expect(decision.method, PlayMethod.transcode);
    expect(decision.url, isNull);
    expect(decision.reason, contains('Container avi unsupported'));
    expect(decision.reason, contains('vp9 -> H.264/HEVC'));
    expect(decision.reason, contains('dts -> AAC'));
  });

  test('handles missing and empty MediaSources', () {
    final missing = repository.selectStream({});
    final empty = repository.selectStream({'MediaSources': []});

    expect(missing.method, PlayMethod.transcode);
    expect(missing.reason, isEmpty);
    expect(missing.url, isNull);
    expect(empty.method, PlayMethod.transcode);
    expect(empty.reason, 'Jellyfin returned no playable media sources');
    expect(empty.url, isNull);
  });
}
