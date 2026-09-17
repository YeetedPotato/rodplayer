import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/playback/playback_diagnostics.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/ui/widgets/compatibility_panel.dart';

void main() {
  test('CompatibilityPanel has no fake 4K/HDR/Atmos defaults', () {
    final source = File('lib/ui/widgets/compatibility_panel.dart').readAsStringSync();
    expect(source, isNot(contains('4K UHD')));
    expect(source, isNot(contains('HDR10+')));
    expect(source, isNot(contains('Atmos / 7.1')));
  });

  testWidgets('Stats for Nerds renders only explicit server metadata', (tester) async {
    await _pump(tester, CapabilitySupport.unknown);
    expect(find.text('HEVC'), findsOneWidget);
    expect(find.text('3840x2160'), findsOneWidget);
    expect(find.text('23.976'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('Atmos'), findsOneWidget);
    expect(find.text('HDR10'), findsOneWidget);
    expect(find.text('Unknown'), findsWidgets);
    expect(find.text('4K UHD'), findsNothing);
    expect(find.text('HDR10+'), findsNothing);
    expect(find.text('7.1'), findsNothing);
    expect(find.text('hardware decoding'), findsNothing);
  });

  testWidgets('diagnostics telemetry is truthful and compact content remains safe', (tester) async {
    final oldSize = tester.view.physicalSize;
    final oldRatio = tester.view.devicePixelRatio;
    addTearDown(() {
      tester.view.physicalSize = oldSize;
      tester.view.devicePixelRatio = oldRatio;
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 760);
    await _pump(tester, CapabilitySupport.supported, longValues: true);
    expect(tester.takeException(), isNull);
    expect(find.text('Supported'), findsOneWidget);
    await _pump(tester, CapabilitySupport.unknown, longValues: true);
    expect(find.text('Unknown'), findsWidgets);
    await _pump(tester, CapabilitySupport.unsupported);
    expect(find.text('Not reported'), findsOneWidget);
  });
}

Future<void> _pump(WidgetTester tester, CapabilitySupport support, {bool longValues = false}) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompatibilityPanel(
            snapshot: PlaybackDiagnosticsSnapshot.fromPlan(plan: _plan(longValues: longValues), selectedAudioStreamIndex: 1),
            runtimeDiagnostics: support,
          ),
        ),
      ),
    );

PlaybackPlan _plan({bool longValues = false}) => PlaybackPlan(
      itemId: 'item',
      mediaSourceId: 'source',
      playSessionId: 'session',
      playMethod: PlayMethod.transcode,
      playbackUri: Uri.parse('https://not-shown.example/stream'),
      engineId: 'backend',
      videoOperation: VideoOperation.unknown,
      audioOperation: AudioOperation.unknown,
      subtitleOperation: SubtitleOperation.unknown,
      hdrHandling: HdrHandling.unknown,
      source: MediaSourceInfo.fromJson(<String, dynamic>{
        'Id': 'source',
        'Container': longValues ? 'a-very-long-container-name-that-must-wrap-safely' : 'mkv',
        'MediaStreams': <Map<String, dynamic>>[
          <String, dynamic>{
            'Index': 0,
            'Type': 'Video',
            'Codec': 'HEVC',
            'Width': 3840,
            'Height': 2160,
            'AverageFrameRate': 23.976,
            'BitDepth': 10,
            'VideoRange': 'HDR',
            'VideoRangeType': 'HDR10',
          },
          <String, dynamic>{'Index': 1, 'Type': 'Audio', 'Codec': 'EAC3', 'AudioSpatialFormat': 'Atmos'},
        ],
      }),
    );
