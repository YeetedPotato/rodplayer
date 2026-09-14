import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/models/media_intelligence.dart';

void main() {
  test('preserves all streams and separates audio concepts', () {
    final media = MediaIntelligence.fromJson(<String, dynamic>{
      'MediaStreams': <Map<String, dynamic>>[
        <String, dynamic>{'Index': 0, 'Type': 'Video', 'Codec': 'hevc'},
        <String, dynamic>{'Index': 1, 'Type': 'Audio', 'Codec': 'truehd', 'AudioSpatialFormat': 'Dolby Atmos', 'Channels': 8},
        <String, dynamic>{'Index': 2, 'Type': 'Audio', 'Codec': 'dts', 'Profile': 'DTS-HD MA', 'AudioSpatialFormat': 'DTS:X'},
        <String, dynamic>{'Index': 3, 'Type': 'Subtitle', 'Codec': 'ass'},
      ],
    });
    expect(media.audioStreams, hasLength(2));
    expect(media.subtitleStreams.single.index, 3);
    expect(media.audioStreams.first.codecFamily, AudioCodecFamily.trueHd);
    expect(media.audioStreams.first.spatialFormat, SpatialFormat.atmos);
    expect(media.audioStreams[1].codecFamily, AudioCodecFamily.dts);
    expect(media.audioStreams[1].detailedFormat, AudioDetailedFormat.dtsHdMa);
    expect(media.audioStreams[1].spatialFormat, SpatialFormat.dtsX);
  });
}
