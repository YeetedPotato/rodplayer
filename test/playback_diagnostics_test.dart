import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/playback/playback_diagnostics.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';

void main() {
  test('snapshot copies safe plan facts and exact selected streams', () {
    final snapshot = PlaybackDiagnosticsSnapshot.fromPlan(
      plan: _plan(),
      runtimeId: 'runtime',
      selectedAudioStreamIndex: 4,
      selectedSubtitleStreamIndex: 8,
    );

    expect(snapshot.backendId, 'backend');
    expect(snapshot.runtimeId, 'runtime');
    expect(snapshot.playMethod, PlayMethod.directPlay);
    expect(snapshot.deliveryMode, PlaybackDeliveryMode.directStream);
    expect(snapshot.videoOperation, VideoOperation.copy);
    expect(snapshot.audioOperation, AudioOperation.transcode);
    expect(snapshot.subtitleOperation, SubtitleOperation.native);
    expect(snapshot.hdrHandling, HdrHandling.unknown);
    expect(snapshot.transcodeReasons, <String>['reason']);
    expect(snapshot.container, 'mkv');
    expect(snapshot.protocol, 'File');
    expect(snapshot.sourceBitrate, 1000000);
    expect(snapshot.videoStream?.codec, 'hevc');
    expect(snapshot.audioStream?.codec, 'aac');
    expect(snapshot.subtitleStream?.codec, 'subrip');
  });

  test('snapshot neither guesses selected streams nor exposes multiple video streams', () {
    final plan = _plan(videoStreams: 2);
    expect(PlaybackDiagnosticsSnapshot.fromPlan(plan: plan).videoStream, isNull);
    expect(PlaybackDiagnosticsSnapshot.fromPlan(plan: plan, selectedAudioStreamIndex: 5).audioStream, isNull);
    expect(PlaybackDiagnosticsSnapshot.fromPlan(plan: plan, selectedSubtitleStreamIndex: 7).subtitleStream, isNull);
  });

  test('snapshot retains neither plan nor URL-bearing server objects', () {
    final snapshot = PlaybackDiagnosticsSnapshot.fromPlan(
      plan: _plan(deliveryUrl: 'https://secret.example/subtitle?api_key=SUPER_SECRET_TOKEN'),
    );
    expect(snapshot.videoStream?.runtimeType.toString(), 'PlaybackDiagnosticsStream');
    expect(() => snapshot.transcodeReasons.add('mutate'), throwsUnsupportedError);
    expect(snapshot.toString(), isNot(contains('SUPER_SECRET_TOKEN')));
  });
}

PlaybackPlan _plan({int videoStreams = 1, String? deliveryUrl}) => PlaybackPlan(
      itemId: 'item',
      mediaSourceId: 'source',
      playSessionId: 'session',
      playMethod: PlayMethod.directPlay,
      playbackUri: Uri.parse('https://secret.example/stream?api_key=SUPER_SECRET_TOKEN'),
      engineId: 'backend',
      deliveryMode: PlaybackDeliveryMode.directStream,
      videoOperation: VideoOperation.copy,
      audioOperation: AudioOperation.transcode,
      subtitleOperation: SubtitleOperation.native,
      hdrHandling: HdrHandling.unknown,
      transcodeReasons: const <String>['reason'],
      source: MediaSourceInfo.fromJson(<String, dynamic>{
        'Id': 'source',
        'Container': 'mkv',
        'Protocol': 'File',
        'Bitrate': 1000000,
        'MediaStreams': <Map<String, dynamic>>[
          for (var index = 0; index < videoStreams; index++)
            <String, dynamic>{'Index': index, 'Type': 'Video', 'Codec': 'hevc'},
          <String, dynamic>{'Index': 4, 'Type': 'Audio', 'Codec': 'aac'},
          <String, dynamic>{'Index': 8, 'Type': 'Subtitle', 'Codec': 'subrip', 'DeliveryUrl': deliveryUrl},
        ],
      }),
    );
