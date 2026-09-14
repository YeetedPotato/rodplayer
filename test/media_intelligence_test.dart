import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/models/media_intelligence.dart';

void main() {
  group('MediaIntelligence.fromJson', () {
    test('parses MediaStreams and selects the first stream of each type', () {
      final media = MediaIntelligence.fromJson({
        'MediaStreams': [
          {'Type': 'Video', 'Codec': 'hevc'},
          {'Type': 'Video', 'Codec': 'avc'},
          {'Type': 'Audio', 'Codec': 'flac'},
          {'Type': 'Subtitle', 'Codec': 'subrip'},
        ],
        'Width': 3840,
        'Height': 2160,
        'Bitrate': 12000000,
        'RunTimeTicks': 72000000000,
      });

      expect(media.video?.codec, 'hevc');
      expect(media.audio?.codec, 'flac');
      expect(media.subtitle?.codec, 'subrip');
      expect(media.width, 3840);
      expect(media.height, 2160);
      expect(media.bitrate, 12000000);
      expect(media.durationTicks, 72000000000);
    });

    test('uses Streams as a fallback and handles missing or null streams', () {
      final fallback = MediaIntelligence.fromJson({
        'MediaStreams': null,
        'Streams': [
          {'Type': 'Audio', 'Codec': 'aac'},
        ],
      });
      final empty = MediaIntelligence.fromJson({
        'MediaStreams': null,
        'Streams': null,
      });

      expect(fallback.audio?.codec, 'aac');
      expect(fallback.video, isNull);
      expect(fallback.subtitle, isNull);
      expect(empty.video, isNull);
      expect(empty.audio, isNull);
      expect(empty.subtitle, isNull);
      expect(empty.width, isNull);
    });
  });

  group('codec normalization', () {
    test('normalizes HEVC, H.265, AVC, H.264, and AV1 variants', () {
      for (final codec in ['hevc', 'h265', 'H.265']) {
        expect(_stream(codec: codec).displayCodec, 'HEVC');
      }
      for (final codec in ['avc', 'h264', 'H.264']) {
        expect(_stream(codec: codec).displayCodec, 'H.264');
      }
      for (final codec in ['av1', 'AV1']) {
        expect(_stream(codec: codec).displayCodec, 'AV1');
      }
    });

    test('falls back to display title, raw codec, or Unknown', () {
      expect(_stream(displayTitle: 'Custom HEVC').displayCodec, 'Custom HEVC');
      expect(_stream(codec: 'MPEG-4').displayCodec, 'MPEG-4');
      expect(_stream(codec: 'vp9').displayCodec, 'vp9');
      expect(_stream().displayCodec, 'Unknown');
    });
  });

  group('HDR detection', () {
    test('detects Dolby Vision and includes its profile', () {
      expect(_stream(profile: 'Dolby Vision 8.1').displayHdr, 'Dolby Vision Dolby Vision 8.1');
      expect(_stream(videoRange: 'Dolby Vision').displayHdr, 'Dolby Vision');
    });

    test('detects HDR10+, HDR10, and HLG', () {
      expect(_stream(videoRangeType: 'HDR10+').displayHdr, 'HDR10+');
      expect(_stream(videoRange: 'HDR10').displayHdr, 'HDR10');
      expect(_stream(videoRangeType: 'HLG').displayHdr, 'HLG');
    });

    test('falls back to SDR when no HDR flags are present', () {
      expect(_stream().displayHdr, 'SDR');
    });
  });

  group('audio formatting', () {
    test('formats named codecs and spatial formats', () {
      expect(_stream(codec: 'TrueHD').displayAudio, 'TrueHD');
      expect(_stream(audioSpatialFormat: 'Dolby Atmos').displayAudio, 'Atmos');
      expect(_stream(codec: 'DTS:X').displayAudio, 'DTS:X');
      expect(_stream(codec: 'DTS-HD MA').displayAudio, 'DTS-HD MA');
      expect(_stream(codec: 'FLAC').displayAudio, 'FLAC');
    });

    test('formats channel counts and preserves explicit channel layouts', () {
      expect(_stream(codec: 'aac', channels: 8).displayAudio, 'aac 7.1');
      expect(_stream(codec: 'aac', channels: 6).displayAudio, 'aac 5.1');
      expect(_stream(codec: 'aac', channels: 2, channelLayout: 'L R').displayAudio, 'aac L R');
    });
  });

  group('resolution and summary', () {
    test('formats resolution and identifies 4K', () {
      final media4k = MediaIntelligence.fromJson({
        'Width': 3840,
        'Height': 2160,
        'MediaStreams': [],
      });
      final media1080p = MediaIntelligence.fromJson({
        'Width': 1920,
        'Height': 1080,
        'MediaStreams': [],
      });

      expect(media4k.resolution, '3840x2160');
      expect(media4k.is4K, isTrue);
      expect(media1080p.resolution, '1920x1080');
      expect(media1080p.is4K, isFalse);
      expect(MediaIntelligence.fromJson({}).resolution, 'Unknown');
    });

    test('composes summary from available media details', () {
      final media = MediaIntelligence.fromJson({
        'Width': 3840,
        'Height': 2160,
        'MediaStreams': [
          {'Type': 'Video', 'Codec': 'hevc', 'VideoRange': 'HDR10'},
          {'Type': 'Audio', 'Codec': 'FLAC', 'Channels': 2},
        ],
      });

      expect(media.summary, '3840x2160 • HEVC • HDR10 • FLAC 2 ch');
    });
  });
}

StreamIntelligence _stream({
  String? codec,
  String? profile,
  String? videoRange,
  String? videoRangeType,
  String? displayTitle,
  int? channels,
  String? channelLayout,
  String? audioSpatialFormat,
}) {
  return StreamIntelligence(
    type: 'Video',
    codec: codec,
    profile: profile,
    videoRange: videoRange,
    videoRangeType: videoRangeType,
    displayTitle: displayTitle,
    channels: channels,
    channelLayout: channelLayout,
    audioSpatialFormat: audioSpatialFormat,
  );
}
