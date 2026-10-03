import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/player/media_kit_advanced_playback_controls.dart';
import 'package:rodplayer/core/player/playback_command_controller.dart';
import 'package:rodplayer/core/player/playback_engine.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/core/player/track_controller.dart';
import 'package:rodplayer/core/player_ui_settings.dart';
import 'package:rodplayer/ui/player/playback_settings_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/test_playback_engine.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('playback settings persist and update their active player',
      (tester) async {
    final preferences = await SharedPreferences.getInstance();
    var current = PlayerUiSettings.defaults;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlaybackSettingsSheet(
          settings: current,
          onChanged: (settings) => current = settings,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Playback speed'), findsNothing,
        reason: 'unsupported or unknown backend controls stay hidden');
    expect(find.text('Single-click always toggles playback.'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('15 seconds').last);
    await tester.pumpAndSettle();

    expect(current.seekIntervalSeconds, 15);
    expect(preferences.getInt(PlayerUiSettings.seekKey), 15);
    expect(find.text('Playback settings'), findsOneWidget);
  });

  testWidgets('supported backend exposes only real playback-speed control',
      (tester) async {
    final backend = _FakeRateBackend();
    final controls = MediaKitAdvancedPlaybackControls.forTesting(backend);
    addTearDown(controls.dispose);
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
      PlaybackRuntimeViewBinding(advanced: controls),
    );
    addTearDown(binding.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlaybackSettingsSheet(
          settings: PlayerUiSettings.defaults,
          activeBinding: binding,
          onChanged: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Playback speed'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<double>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.5x').last);
    await tester.pumpAndSettle();
    expect(backend.rate, 1.5);
  });

  testWidgets('production speed selection uses the active command target',
      (tester) async {
    final displayedBackend = _FakeRateBackend();
    final displayedControls =
        MediaKitAdvancedPlaybackControls.forTesting(displayedBackend);
    addTearDown(displayedControls.dispose);
    final commandBackend = _FakeRateBackend();
    final commandControls =
        MediaKitAdvancedPlaybackControls.forTesting(commandBackend);
    addTearDown(commandControls.dispose);
    final engine = TestPlaybackEngine();
    addTearDown(engine.dispose);
    final commandTarget = _PlaybackSettingsCommandTarget(
      engine: engine,
      advanced: commandControls,
    );
    final commands = PlaybackCommandController(currentTarget: () => commandTarget);
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
      PlaybackRuntimeViewBinding(advanced: displayedControls),
    );
    addTearDown(binding.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlaybackSettingsSheet(
          settings: PlayerUiSettings.defaults,
          activeBinding: binding,
          commandController: commands,
          onChanged: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<double>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.5x').last);
    await tester.pumpAndSettle();

    expect(commandBackend.rate, 1.5);
    expect(displayedBackend.rate, isNull,
        reason: 'the UI binding is read-only; mutation goes through commands');
  });

  testWidgets('active source appears as truthful Version and Quality summary',
      (tester) async {
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
      PlaybackRuntimeViewBinding(
        plan: PlaybackPlan(
          itemId: 'movie',
          mediaSourceId: 'source-1',
          playSessionId: 'session-1',
          playMethod: PlayMethod.directPlay,
          playbackUri: Uri.parse('https://media.example.com/video'),
          engineId: 'test',
          source: MediaSourceInfo.fromJson(<String, dynamic>{
            'Id': 'source-1',
            'Name': 'Blu-ray',
            'Bitrate': 9800000,
            'MediaStreams': <Object>[
              <String, Object>{
                'Type': 'Video',
                'Width': 1920,
                'Height': 1080,
                'Codec': 'hevc',
                'VideoRangeType': 'HDR10',
              },
              <String, Object>{'Type': 'Audio', 'Channels': 6},
            ],
          }),
        ),
      ),
    );
    addTearDown(binding.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlaybackSettingsSheet(
          settings: PlayerUiSettings.defaults,
          activeBinding: binding,
          onChanged: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Version & Quality'), findsOneWidget);
    expect(find.textContaining('1080p · Blu-ray'), findsOneWidget);
    expect(find.textContaining('exit playback and choose Play Version'),
        findsNothing);
    expect(find.text('Change'), findsOneWidget);
  });

  testWidgets('Version and Quality presents sources and forwards selection',
      (tester) async {
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
      PlaybackRuntimeViewBinding(
        plan: PlaybackPlan(
          itemId: 'movie',
          mediaSourceId: 'source-1',
          playSessionId: 'session-1',
          playMethod: PlayMethod.directPlay,
          playbackUri: Uri.parse('https://media.example.com/video'),
          engineId: 'test',
          source: MediaSourceInfo.fromJson(<String, dynamic>{
            'Id': 'source-1',
            'Name': 'Blu-ray',
            'MediaStreams': <Object>[],
          }),
        ),
      ),
    );
    addTearDown(binding.dispose);
    final sourceB = MediaSourceInfo.fromJson(<String, dynamic>{
      'Id': 'source-2',
      'Name': 'Web',
      'Bitrate': 24000000,
      'MediaStreams': <Object>[
        <String, Object>{
          'Type': 'Video',
          'Width': 3840,
          'Height': 2160,
          'Codec': 'hevc',
        },
      ],
    });
    MediaSourceInfo? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlaybackSettingsSheet(
          settings: PlayerUiSettings.defaults,
          activeBinding: binding,
          onChanged: (_) {},
          loadMediaSources: () async => <MediaSourceInfo>[
            binding.value.plan!.source,
            sourceB,
          ],
          onSelectMediaSource: (source) async => selected = source,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    expect(find.text('4K · Web'), findsOneWidget);
    expect(find.text('HEVC · 24.0 Mbps'), findsOneWidget);
    await tester.tap(find.text('4K · Web'));
    await tester.pumpAndSettle();
    expect(selected?.id, 'source-2');
  });
}

class _FakeRateBackend implements MediaKitAdvancedPlaybackBackend {
  double? rate;

  @override
  Duration get position => Duration.zero;

  @override
  Future<void> setRate(double value) async => rate = value;

  @override
  Future<void> setProperty(String name, String value) async {}

  @override
  Future<void> command(List<String> arguments) async {}
}

class _PlaybackSettingsCommandTarget implements PlaybackCommandTarget {
  _PlaybackSettingsCommandTarget({
    required this.engine,
    required this.advanced,
  });

  @override
  final PlaybackEngine engine;
  @override
  final MediaKitAdvancedPlaybackControls advanced;
  @override
  TrackSelectionController? get tracks => null;
  @override
  final PlaybackCommandTargetId id = const PlaybackCommandTargetId(
    logicalSessionId: 'playback-settings-test',
    runtimeGeneration: 1,
  );
}
