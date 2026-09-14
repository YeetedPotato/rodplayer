import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';

void main() {
  test('PlaybackPlan represents all Jellyfin play methods', () {
    for (final method in PlayMethod.values) {
      final source = MediaSourceInfo.fromJson(<String, dynamic>{'Id': method.name, 'MediaStreams': <dynamic>[]});
      final plan = PlaybackPlan(itemId: 'item', mediaSourceId: source.id, playSessionId: 'play', playMethod: method, playbackUri: Uri.parse('https://media/$method'), engineId: 'media_kit', source: source);
      expect(plan.playMethod, method);
    }
  });
}
