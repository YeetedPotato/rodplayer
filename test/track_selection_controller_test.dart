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

  test('unmapped local switches do not invent Jellyfin stream indexes', () async {
    final session = LogicalPlaybackSession(id: 'logical', itemId: 'item', activePlan: _plan(audio: 1, subtitle: 2));
    final controller = LogicalSessionTrackSelectionController(delegate: _FakeTrackSelectionController(), session: session);

    await controller.selectAudio(const RodPlayerTrack(engineTrackId: 'local-unmapped', label: 'Local'));
    await controller.selectSubtitle(null);

    expect(session.selectedAudio, isNull);
    expect(session.selectedSubtitle, isNull);
  });

  test('nonnumeric engine IDs map to Jellyfin server stream indexes explicitly', () {
    final mappings = TrackServerIndexMappings.fromPlan(
      plan: _planWithStreams(),
      audioTracks: const <EngineTrackMetadata>[
        EngineTrackMetadata(id: 'audio/main', language: 'eng', title: 'Main'),
        EngineTrackMetadata(id: 'audio/commentary', language: 'eng', title: 'Commentary'),
      ],
      subtitleTracks: const <EngineTrackMetadata>[EngineTrackMetadata(id: 'subtitle/cc', language: 'eng', title: 'English CC')],
    );
    expect(mappings.audioIndexFor('audio/main'), 4);
    expect(mappings.audioIndexFor('audio/commentary'), 9);
    expect(mappings.subtitleIndexFor('subtitle/cc'), 12);
  });

  test('ambiguous engine metadata does not fabricate server stream indexes', () {
    final mappings = TrackServerIndexMappings.fromPlan(
      plan: _planWithStreams(),
      audioTracks: const <EngineTrackMetadata>[EngineTrackMetadata(id: 'audio/main', language: 'eng')],
      subtitleTracks: const <EngineTrackMetadata>[],
    );
    expect(mappings.audioIndexFor('audio/main'), isNull);
    expect(mappings.subtitleIndexFor('12'), isNull);
  });

  test('typed server stream metadata preserves audio and subtitle properties', () {
    final source = _planWithStreams().source;
    final audio = source.audioStreams.firstWhere((stream) => stream.index == 4);
    final subtitle = source.subtitleStreams.single;

    expect(audio.language, 'eng');
    expect(audio.title, 'Main');
    expect(audio.codec, 'aac');
    expect(audio.isDefault, isTrue);
    expect(audio.channels, 6);
    expect(subtitle.isForced, isTrue);
    expect(subtitle.isExternal, isTrue);
    expect(subtitle.isTextSubtitleStream, isTrue);
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
          <String, dynamic>{'Index': 4, 'Type': 'Audio', 'Codec': 'aac', 'Language': 'eng', 'Title': 'Main', 'IsDefault': true, 'Channels': 6},
          <String, dynamic>{'Index': 9, 'Type': 'Audio', 'Codec': 'ac3', 'Language': 'eng', 'Title': 'Commentary'},
          <String, dynamic>{'Index': 12, 'Type': 'Subtitle', 'Codec': 'subrip', 'Language': 'eng', 'Title': 'English CC', 'IsForced': true, 'IsExternal': true, 'IsTextSubtitleStream': true},
        ],
      }),
    );

class _FakeTrackSelectionController implements TrackSelectionController {
  _FakeTrackSelectionController({this.mode = TrackSwitchMode.local});
  final TrackSwitchMode mode;

  @override
  TrackSelectionCapabilities get capabilities => const TrackSelectionCapabilities.unavailable();

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
