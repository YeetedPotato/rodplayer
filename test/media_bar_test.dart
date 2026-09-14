import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/widgets/media_bar.dart';

import 'fakes/test_playback_engine.dart';

void main() {
  late TestPlaybackEngine engine;

  Widget harness({double initialVolume = 0.8}) => MaterialApp(
        theme: rodPlayerThemeData(),
        home: Scaffold(body: MediaBar(engine: engine, initialVolume: initialVolume)),
      );

  setUp(() {
    engine = TestPlaybackEngine();
  });

  tearDown(() async {
    if (!engine.disposed) await engine.dispose();
  });

  testWidgets('updates play and pause controls from engine state', (tester) async {
    await tester.pumpWidget(harness());
    expect(find.byTooltip('Play'), findsOneWidget);
    await engine.play();
    await tester.pump();
    expect(find.byTooltip('Pause'), findsOneWidget);
    await engine.pause();
    await tester.pump();
    expect(find.byTooltip('Play'), findsOneWidget);
  });

  testWidgets('updates the seek bar from engine position and duration', (tester) async {
    engine.duration = const Duration(seconds: 30);
    await tester.pumpWidget(harness());
    engine.position = const Duration(seconds: 12);
    await tester.pump();
    final slider = tester.widget<Slider>(find.byType(Slider).first);
    expect(slider.value, 12000);
    expect(slider.onChanged, isNotNull);
  });

  testWidgets('volume and mute controls stay synchronized with engine volume commands', (tester) async {
    await tester.pumpWidget(harness(initialVolume: 0.6));
    await tester.pump();
    expect(engine.volume.value, closeTo(60, 0.01));
    expect(find.byTooltip('Mute'), findsOneWidget);
    await tester.tap(find.byTooltip('Mute'));
    await tester.pump();
    expect(engine.volume.value, closeTo(0, 0.01));
    expect(find.byTooltip('Unmute'), findsOneWidget);
    await tester.tap(find.byTooltip('Unmute'));
    await tester.pump();
    expect(engine.volume.value, closeTo(60, 0.01));
    expect(find.byTooltip('Mute'), findsOneWidget);
  });

  testWidgets('does not own or dispose the injected engine', (tester) async {
    await tester.pumpWidget(harness());
    await engine.play();
    await tester.pump();
    expect(find.byTooltip('Pause'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(engine.disposed, isFalse);
  });

  testWidgets('initial volume is clamped before it is sent to the engine', (tester) async {
    await tester.pumpWidget(harness(initialVolume: 2));
    await tester.pump();
    expect(engine.volume.value, closeTo(100, 0.01));
  });

  testWidgets('settings reflects the current volume', (tester) async {
    await tester.pumpWidget(harness(initialVolume: 0.4));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Volume 40%'), findsOneWidget);
  });
}
