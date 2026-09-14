import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/playback/playback_decision.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';

void main() {
  const backend = PlaybackBackendCapabilities(id: 'media_kit', name: 'media_kit', containers: <String>['mkv'], videoCodecs: <String>['h264'], audioCodecs: <String>['aac'], subtitleCodecs: <String>['srt']);
  final engine = PlaybackDecisionEngine(backend);

  test('uses only Jellyfin play methods', () {
    expect(PlayMethod.values.map((m) => m.jellyfinName), <String>['DirectPlay', 'DirectStream', 'Transcode']);
  });

  test('accepts server-provided transcode URL', () {
    final decision = engine.decide(<String, dynamic>{'TranscodingUrl': 'https://media/transcode'});
    expect(decision.method, PlayMethod.transcode);
    expect(decision.url.toString(), 'https://media/transcode');
  });
}
