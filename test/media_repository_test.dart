import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/playback/media_repository.dart';

void main() {
  test('does not reject a valid server transcode candidate', () {
    final repository = MediaRepository();
    final decision = repository.selectStream(<String, dynamic>{
      'MediaSources': <Map<String, dynamic>>[
        <String, dynamic>{'Id': 'source', 'TranscodingUrl': 'https://media.example/transcode.m3u8'},
      ],
    });
    expect(decision.method, PlayMethod.transcode);
    expect(decision.url, Uri.parse('https://media.example/transcode.m3u8'));
  });
}
