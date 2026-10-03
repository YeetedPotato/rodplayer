import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/core/player/track_controller.dart';
import 'package:rodplayer/core/player/playback_command_controller.dart';
import 'package:rodplayer/core/player/playback_engine.dart';
import 'package:rodplayer/core/playback/advanced_playback.dart';
import 'package:rodplayer/ui/player/track_display_label.dart';
import 'package:rodplayer/ui/player/track_selector_sheet.dart';
import 'fakes/test_playback_engine.dart';

void main() {
  Future<void> openSheet(
      WidgetTester tester, ValueListenable<PlaybackRuntimeViewBinding> binding,
      {PlaybackCommandController? commands}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => TrackSelectorSheet.show(context,
                controls: binding, commandController: commands),
            child: const Text('Tracks'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Tracks'));
    await tester.pumpAndSettle();
  }

  for (final mode in TrackSwitchMode.values) {
    testWidgets('production audio command and sheet handle $mode truthfully',
        (tester) async {
      final tracks = _AudioTracks()..mode = mode;
      final target = _SheetTarget(tracks, 1);
      addTearDown(target.engine.dispose);
      final binding = ValueNotifier(PlaybackRuntimeViewBinding(tracks: tracks));
      addTearDown(binding.dispose);
      final commands = PlaybackCommandController(currentTarget: () => target);
      await openSheet(tester, binding, commands: commands);
      await tester.tap(find.text('Spanish'));
      await tester.pumpAndSettle();
      expect(
          tracks.selectedAudio,
          mode == TrackSwitchMode.local
              ? tracks.audioTracks.last
              : tracks.audioTracks.first);
      final selected = find.ancestor(
          of: find.text(mode == TrackSwitchMode.local ? 'Spanish' : 'English'),
          matching: find.byWidgetPredicate((widget) =>
              widget is Semantics && widget.properties.selected == true));
      expect(selected, findsOneWidget);
      if (mode != TrackSwitchMode.local)
        expect(
            find.text(
                'This audio track requires a source change that is not available here.'),
            findsOneWidget);
      final result = await commands.dispatchCurrent(
          command: SelectAudioCommand(tracks.audioTracks.last),
          origin: PlaybackCommandOrigin.localUi);
      expect(
          result.status,
          switch (mode) {
            TrackSwitchMode.local => PlaybackCommandStatus.executed,
            TrackSwitchMode.serverRenegotiation =>
              PlaybackCommandStatus.needsServerRenegotiation,
            TrackSwitchMode.externalAttach =>
              PlaybackCommandStatus.externalAttachRequired,
          });
    });
  }

  testWidgets('failed and stale audio actions preserve the active selection',
      (tester) async {
    final old = _AudioTracks()..fail = true;
    var target = _SheetTarget(old, 1);
    addTearDown(target.engine.dispose);
    final binding = ValueNotifier(PlaybackRuntimeViewBinding(tracks: old));
    addTearDown(binding.dispose);
    final commands = PlaybackCommandController(currentTarget: () => target);
    await openSheet(tester, binding, commands: commands);
    await tester.tap(find.text('Spanish'));
    await tester.pumpAndSettle();
    expect(old.selectedAudio, old.audioTracks.first);
    expect(find.text('Unable to change audio track'), findsOneWidget);
    old
      ..fail = false
      ..gate = Completer<void>();
    final pending = commands.dispatchCurrent(
        command: SelectAudioCommand(old.audioTracks.last),
        origin: PlaybackCommandOrigin.localUi);
    await tester.pump();
    final next = _AudioTracks();
    target = _SheetTarget(next, 2);
    addTearDown(target.engine.dispose);
    binding.value = PlaybackRuntimeViewBinding(tracks: next);
    old.gate!.complete();
    expect((await pending).status, PlaybackCommandStatus.staleSession);
    await tester.pumpAndSettle();
    expect(next.selectedAudio, next.audioTracks.first);
  });

  testWidgets('audio choices use generic metadata and update selected state',
      (tester) async {
    final tracks = _AudioTracks();
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
        PlaybackRuntimeViewBinding(tracks: tracks));
    addTearDown(binding.dispose);
    await openSheet(tester, binding);

    expect(find.text('English'), findsOneWidget);
    expect(find.text('AAC'), findsOneWidget);
    expect(find.text('Spanish'), findsOneWidget);
    expect(tracks.selectedAudio, tracks.audioTracks.first);
    await tester.tap(find.text('Spanish'));
    await tester.pump();
    expect(tracks.calls, <String>['b']);
    expect(tracks.selectedAudio, tracks.audioTracks.last);
    final selected = find.ancestor(
      of: find.text('Spanish'),
      matching: find.byWidgetPredicate((widget) =>
          widget is Semantics && widget.properties.selected == true),
    );
    expect(selected, findsOneWidget);
  });

  testWidgets('empty audio controller does not invent options', (tester) async {
    final tracks = _AudioTracks(audio: const <RodPlayerTrack>[]);
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
        PlaybackRuntimeViewBinding(tracks: tracks));
    addTearDown(binding.dispose);
    await openSheet(tester, binding);
    expect(find.text('No track choices available'), findsOneWidget);
    expect(find.text('English'), findsNothing);
    expect(tracks.calls, isEmpty);
  });

  testWidgets('real unmapped streams receive numbered fallback labels',
      (tester) async {
    final tracks = _AudioTracks(audio: const <RodPlayerTrack>[
      RodPlayerTrack(engineTrackId: 'a1', label: 'Unknown track'),
      RodPlayerTrack(engineTrackId: 'a2', label: 'Unknown track'),
    ]);
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
        PlaybackRuntimeViewBinding(tracks: tracks));
    addTearDown(binding.dispose);
    await openSheet(tester, binding);
    expect(find.text('Audio track 1'), findsOneWidget);
    expect(find.text('Audio track 2'), findsOneWidget);
    expect(find.text('Audio track'), findsNothing);
  });

  testWidgets('single audio is hidden when subtitle choices are available',
      (tester) async {
    final tracks = _AudioAndSubtitleTracks();
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
        PlaybackRuntimeViewBinding(tracks: tracks));
    addTearDown(binding.dispose);
    await openSheet(tester, binding);

    expect(find.text('AUDIO'), findsNothing);
    expect(find.text('Subtitles'), findsOneWidget,
        reason: 'subtitle-only choices use the compact Subtitles heading');
    expect(find.text('Audio track 4'), findsNothing);
    expect(find.text('SRT · External · Forced'), findsOneWidget);
  });

  testWidgets('single audio track with no subtitles has no choice section',
      (tester) async {
    final tracks = _AudioTracks(audio: const <RodPlayerTrack>[
      RodPlayerTrack(engineTrackId: 'only', label: 'English', title: 'English'),
    ]);
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
        PlaybackRuntimeViewBinding(tracks: tracks));
    addTearDown(binding.dispose);
    await openSheet(tester, binding);
    expect(find.text('AUDIO'), findsNothing);
    expect(find.text('No track choices available'), findsOneWidget);
  });

  test('display title labels do not repeat language, codec, or flags', () {
    final track = RodPlayerTrack(
      engineTrackId: 's3',
      label: 'English CC',
      displayTitle: 'English CC',
      language: 'eng',
      codec: 'ass',
      isExternal: true,
    );
    expect(subtitleTrackDisplayLabel(track), 'English CC · ASS · External');
  });

  test('subtitle labels prefer truthful stream title and avoid guessing', () {
    const titled = RodPlayerTrack(
      engineTrackId: 'sdh',
      label: 'English',
      title: 'English (SDH)',
      language: 'eng',
      codec: 'subrip',
      isExternal: false,
      isDefault: true,
    );
    expect(subtitleTrackPrimaryLabel(titled), 'English (SDH)');
    expect(subtitleTrackSecondaryLabel(titled), 'SRT · Embedded · Default');

    const languageOnly =
        RodPlayerTrack(engineTrackId: 'spa', label: 'spa', language: 'spa');
    expect(subtitleTrackPrimaryLabel(languageOnly), 'Spanish');

    const codeTitle = RodPlayerTrack(
        engineTrackId: 'eng-sdh',
        label: 'eng',
        title: 'eng - SDH',
        language: 'eng');
    expect(subtitleTrackPrimaryLabel(codeTitle), 'English - SDH');

    const unknown = RodPlayerTrack(engineTrackId: 'unknown', label: 'Unknown');
    expect(subtitleTrackPrimaryLabel(unknown), 'Unknown');
  });
}

class _AudioTracks extends TrackSelectionController {
  TrackSwitchMode mode = TrackSwitchMode.local;
  bool fail = false;
  Completer<void>? gate;
  _AudioTracks({List<RodPlayerTrack>? audio})
      : audio = audio ??
            const <RodPlayerTrack>[
              RodPlayerTrack(
                  engineTrackId: 'a',
                  label: 'English',
                  language: 'eng',
                  title: 'English',
                  codec: 'aac'),
              RodPlayerTrack(
                  engineTrackId: 'b',
                  label: 'Spanish',
                  language: 'spa',
                  title: 'Spanish',
                  codec: 'ac3',
                  isDefault: true),
            ];

  final List<RodPlayerTrack> audio;
  final List<String> calls = <String>[];
  RodPlayerTrack? _selected;

  @override
  TrackSelectionCapabilities get capabilities =>
      const TrackSelectionCapabilities(
          audioSelection: CapabilitySupport.supported);
  @override
  List<RodPlayerTrack> get audioTracks => audio;
  @override
  List<RodPlayerTrack> get subtitleTracks => const <RodPlayerTrack>[];
  @override
  RodPlayerTrack? get selectedAudio =>
      _selected ?? (audio.isEmpty ? null : audio.first);
  @override
  RodPlayerTrack? get selectedSubtitle => null;
  @override
  Future<TrackSwitchResult> selectAudio(RodPlayerTrack track) async {
    calls.add(track.engineTrackId);
    await gate?.future;
    if (fail) throw StateError('audio failed');
    if (mode == TrackSwitchMode.local) _selected = track;
    return TrackSwitchResult(mode: mode);
  }

  @override
  Future<TrackSwitchResult> selectSubtitle(RodPlayerTrack? track) async =>
      const TrackSwitchResult(mode: TrackSwitchMode.local);
}

final class _SheetTarget implements PlaybackCommandTarget {
  _SheetTarget(this.tracks, int generation)
      : id = PlaybackCommandTargetId(
            logicalSessionId: 'sheet', runtimeGeneration: generation);
  @override
  final PlaybackCommandTargetId id;
  @override
  final TrackSelectionController tracks;
  @override
  final PlaybackEngine engine = TestPlaybackEngine();
  @override
  AdvancedPlaybackControls? get advanced => null;
}

class _AudioAndSubtitleTracks extends _AudioTracks {
  @override
  List<RodPlayerTrack> get audioTracks => const <RodPlayerTrack>[
        RodPlayerTrack(
          engineTrackId: 'a4',
          label: 'Unknown track',
          serverStreamIndex: 3,
        ),
      ];

  @override
  List<RodPlayerTrack> get subtitleTracks => const <RodPlayerTrack>[
        RodPlayerTrack(
          engineTrackId: 's2',
          label: 'Unknown track',
          serverStreamIndex: 1,
          codec: 'srt',
          isForced: true,
          isExternal: true,
        ),
      ];

  @override
  TrackSelectionCapabilities get capabilities =>
      const TrackSelectionCapabilities(
        audioSelection: CapabilitySupport.supported,
        subtitleSelection: CapabilitySupport.supported,
      );
}
