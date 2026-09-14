import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/playback/logical_playback_session.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';

void main() {
  test('logical session remains stable while server session changes', () {
    PlaybackPlan plan(String id, PlayMethod method) => PlaybackPlan(itemId: 'item', mediaSourceId: id, playSessionId: 'play-$id', playMethod: method, playbackUri: Uri.parse('https://media/$id'), engineId: 'media_kit', source: MediaSourceInfo.fromJson(<String, dynamic>{'Id': id, 'MediaStreams': <dynamic>[]}));
    final session = LogicalPlaybackSession(id: 'logical', itemId: 'item', activePlan: plan('A', PlayMethod.directPlay));
    session.activatePlan(plan('B', PlayMethod.transcode));
    expect(session.id, 'logical');
    expect(session.activeServerSession.mediaSourceId, 'B');
    expect(session.activeServerSession.playMethod, PlayMethod.transcode);
  });
}
