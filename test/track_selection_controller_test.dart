import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/playback/logical_playback_session.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/player/track_controller.dart';

void main() {
  test('local track switch updates logical session with server stream index', () async {
    final session = LogicalPlaybackSession(id: 'logical', itemId: 'item', activePlan: _plan(audio: 1, subtitle: 2));
    final delegate = _FakeTrackSelectionController();
    final controller = LogicalSessionTrackSelectionController(delegate: delegate, session: session);
    final audio = RodPlayerTrack(engineTrackId: 'engine-audio-4', serverStreamIndex: 4, label: 'English');
    final subtitle = RodPlayerTrack(engineTrackId: 'engine-sub-8', serverStreamIndex: 8, label: 'English CC');
    await controller.selectAudio(audio);
    await controller.selectSubtitle(subtitle);
    expect(session.selectedAudio, 4);
    expect(session.selectedSubtitle, 8);
    expect(audio.engineTrackId, isNot('${audio.serverStreamIndex}'));
  });

  test('unsupported local switch can indicate server renegotiation', () async {
    final session = LogicalPlaybackSession(id: 'logical', itemId: 'item', activePlan: _plan(audio: 1, subtitle: null));
    final delegate = _FakeTrackSelectionController(mode: TrackSwitchMode.serverRenegotiation);
    final controller = LogicalSessionTrackSelectionController(delegate: delegate, session: session);
    final result = await controller.selectAudio(const RodPlayerTrack(engineTrackId: 'remote-only', serverStreamIndex: 9, label: 'Commentary'));
    expect(result.mode, TrackSwitchMode.serverRenegotiation);
    expect(session.selectedAudio, 1);
  });

  test('nonnumeric engine IDs map to Jellyfin server stream indexes explicitly', () {
    final mappings = TrackServerIndexMappings.fromPlan(
      plan: _planWithStreams(),
      audioEngineTrackIds: <String>['audio/main', 'audio/commentary'],
      subtitleEngineTrackIds: <String>['subtitle/cc'],
    );
    expect(mappings.audioIndexFor('audio/main'), 4);
    expect(mappings.audioIndexFor('audio/commentary'), 9);
    expect(mappings.subtitleIndexFor('subtitle/cc'), 12);
  });

  test('unmapped engine IDs do not fabricate server stream indexes', () {
    final mappings = TrackServerIndexMappings.fromPlan(
      plan: _planWithStreams(),
      audioEngineTrackIds: <String>['audio/main'],
      subtitleEngineTrackIds: const <String>[],
    );
    expect(mappings.audioIndexFor('unmapped-7'), isNull);
    expect(mappings.subtitleIndexFor('12'), isNull);
  });
}

PlaybackPlan _plan({int? audio, int? subtitle}) => PlaybackPlan(
      itemId: 'item',
      mediaSourceId: 'source',
      playSessionId: 'play',
      playMethod: PlayMethod.directPlay,
      playbackUri: Uri.parse('https://media/Videos/item/stream'),
      engineId: 'test',
      selectedAudioStreamIndex: audio,
      selectedSubtitleStreamIndex: subtitle,
      source: MediaSourceInfo.fromJson(<String, dynamic>{'Id': 'source', 'MediaStreams': <dynamic>[]}),
    );

PlaybackPlan _planWithStreams() => PlaybackPlan(
      itemId: 'item',
      mediaSourceId: 'source',
      playSessionId: 'play',
      playMethod: PlayMethod.directPlay,
      playbackUri: Uri.parse('https://media/Videos/item/stream'),
      engineId: 'test',
      source: MediaSourceInfo.fromJson(<String, dynamic>{
        'Id': 'source',
        'MediaStreams': <Map<String, dynamic>>[
          <String, dynamic>{'Index': 0, 'Type': 'Video', 'Codec': 'h264'},
          <String, dynamic>{'Index': 4, 'Type': 'Audio', 'Codec': 'aac'},
          <String, dynamic>{'Index': 9, 'Type': 'Audio', 'Codec': 'ac3'},
          <String, dynamic>{'Index': 12, 'Type': 'Subtitle', 'Codec': 'subrip'},
        ],
      }),
    );

class _FakeTrackSelectionController implements TrackSelectionController {
  _FakeTrackSelectionController({this.mode = TrackSwitchMode.local});
  final TrackSwitchMode mode;

  @override
  List<RodPlayerTrack> get audioTracks => const <RodPlayerTrack>[];
  @override
  List<RodPlayerTrack> get subtitleTracks => const <RodPlayerTrack>[];
  @override
  RodPlayerTrack? get selectedAudio => null;
  @override
  RodPlayerTrack? get selectedSubtitle => null;

  @override
  Future<TrackSwitchResult> selectAudio(RodPlayerTrack track) async => TrackSwitchResult(mode: mode, serverStreamIndex: track.serverStreamIndex);

  @override
  Future<TrackSwitchResult> selectSubtitle(RodPlayerTrack? track) async => TrackSwitchResult(mode: mode, serverStreamIndex: track?.serverStreamIndex);
}
