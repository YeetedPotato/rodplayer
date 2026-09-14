import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/player/player_controller.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/widgets/media_bar.dart';

void main() {
  late MediaKitPlaybackEngine engine;
  Widget harness({MediaKitPlaybackEngine? suppliedEngine, double initialVolume = 0.8}) => MaterialApp(theme: rodPlayerThemeData(), home: Scaffold(body: MediaBar(engine: suppliedEngine, initialVolume: initialVolume)));
  setUp(() { engine = MediaKitPlaybackEngine(); });
  tearDown(() async { await engine.dispose(); });
  testWidgets('updates play and pause controls from engine playing stream', (tester) async { await tester.pumpWidget(harness(suppliedEngine: engine)); expect(find.byTooltip('Play'), findsOneWidget); await engine.player.play(); await tester.pump(); expect(find.byTooltip('Pause'), findsOneWidget); await engine.player.pause(); await tester.pump(); expect(find.byTooltip('Play'), findsOneWidget); });
  testWidgets('updates the seek bar from the engine position stream', (tester) async { await tester.pumpWidget(harness(suppliedEngine: engine)); final slider = tester.widget<Slider>(find.byType(Slider).first); expect(slider.value, 0); expect(slider.onChanged, isNull); await engine.player.seek(const Duration(seconds: 12)); await tester.pump(); final updatedSlider = tester.widget<Slider>(find.byType(Slider).first); expect(updatedSlider.value, 0); });
  testWidgets('volume and mute controls stay synchronized with volume commands', (tester) async { await tester.pumpWidget(harness(suppliedEngine: engine, initialVolume: 0.6)); await tester.pump(); expect(engine.player.state.volume, closeTo(60, 0.01)); expect(find.byTooltip('Mute'), findsOneWidget); await tester.tap(find.byTooltip('Mute')); await tester.pump(); expect(engine.player.state.volume, closeTo(0, 0.01)); expect(find.byTooltip('Unmute'), findsOneWidget); await tester.tap(find.byTooltip('Unmute')); await tester.pump(); expect(engine.player.state.volume, closeTo(60, 0.01)); expect(find.byTooltip('Mute'), findsOneWidget); });
  testWidgets('supports an injected engine without taking ownership', (tester) async { await tester.pumpWidget(harness(suppliedEngine: engine)); await tester.pump(); await engine.player.play(); await tester.pump(); expect(find.byTooltip('Pause'), findsOneWidget); await tester.pumpWidget(const SizedBox()); await tester.pump(); expect(() => engine.player.state.playing, returnsNormally); });
  testWidgets('creates and disposes its own engine when engine is omitted', (tester) async { await tester.pumpWidget(harness()); expect(find.bySemanticsLabel('Media controls'), findsOneWidget); await tester.pumpWidget(const SizedBox()); await tester.pump(); expect(find.bySemanticsLabel('Media controls'), findsNothing); });
  testWidgets('initial volume is clamped before it is sent to the engine', (tester) async { await tester.pumpWidget(harness(suppliedEngine: engine, initialVolume: 2)); await tester.pump(); expect(engine.player.state.volume, closeTo(100, 0.01)); });
  testWidgets('settings reflects the current volume', (tester) async { await tester.pumpWidget(harness(suppliedEngine: engine, initialVolume: 0.4)); await tester.tap(find.byTooltip('Settings')); await tester.pumpAndSettle(); expect(find.text('Volume 40%'), findsOneWidget); });
}
