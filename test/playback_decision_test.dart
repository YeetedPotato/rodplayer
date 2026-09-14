import 'package:flutter_test/flutter_test.dart';
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

  test('legacy helper does not treat filesystem Path as playback URL', () {
    final decision = engine.decide(<String, dynamic>{'SupportsDirectPlay': true, 'Path': '/media/Movie.mkv'});
    expect(decision.url, isNull);
  });
}
