import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/widgets/media_bar.dart';

import 'fakes/test_playback_engine.dart';

void main() {
  late TestPlaybackEngine engine;

  Widget harness({bool visible = true}) => MaterialApp(
        theme: rodPlayerThemeData(),
        home: Scaffold(
          body: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: visible ? MediaBar(engine: engine) : const SizedBox.shrink(),
          ),
        ),
      );

  setUp(() {
    engine = TestPlaybackEngine();
    engine.duration = const Duration(seconds: 30);
  });

  tearDown(() async {
    if (!engine.disposed) await engine.dispose();
  });

  testWidgets('traverses volume, seek, play, and settings controls', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    final volume = find.byTooltip('Mute');
    final seek = find.byType(Slider);
    final play = find.byTooltip('Play');
    final settings = find.byTooltip('Settings');
    expect(volume, findsOneWidget);
    expect(seek, findsOneWidget);
    expect(play, findsOneWidget);
    expect(settings, findsOneWidget);
    Focus.of(tester.element(volume)).requestFocus();
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(volume)).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(seek)).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(play)).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(Focus.of(tester.element(settings)).hasFocus, isTrue);
  });

  testWidgets('DPAD arrows preserve seek focus and select toggles playback', (tester) async {
    await engine.play();
    await tester.pumpWidget(harness());
    await tester.pump();
    final slider = find.byType(Slider);
    final play = find.byTooltip('Pause');
    Focus.of(tester.element(slider)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(Focus.of(tester.element(slider)).hasFocus, isTrue);
    expect(Focus.of(tester.element(slider)).nextFocus(), isTrue);
    await tester.pump();
    expect(Focus.of(tester.element(play)).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(engine.playing.value, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(engine.playing.value, isTrue);
  });

  testWidgets('focused HUD controls use the RodPlayer focus theme', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();
    final settings = find.byTooltip('Settings');
    Focus.of(tester.element(settings)).requestFocus();
    await tester.pump();
    final theme = Theme.of(tester.element(settings)).extension<RodPlayerTheme>()!;
    expect(theme.goldBright, isNot(theme.textMuted));
    expect(Focus.of(tester.element(settings)).hasFocus, isTrue);
  });

  testWidgets('HUD controls gain focus when playback HUD becomes visible', (tester) async {
    await tester.pumpWidget(harness(visible: false));
    await tester.pump();
    expect(find.byTooltip('Settings'), findsNothing);
    await tester.pumpWidget(harness());
    await tester.pump();
    final volume = find.byTooltip('Mute');
    expect(Focus.of(tester.element(volume)).hasFocus, isTrue);
    expect(find.bySemanticsLabel('Media controls'), findsOneWidget);
  });
}
