import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/theme/remux_theme.dart';
import 'package:rodplayer/ui/widgets/media_bar.dart';

void main() {
  Widget harness() => MaterialApp(theme: remuxThemeData(), home: const Scaffold(body: MediaBar()));

  testWidgets('mute toggles and restores saved volume', (tester) async {
    await tester.pumpWidget(harness());
    expect(find.byTooltip('Mute'), findsOneWidget);
    await tester.tap(find.byTooltip('Mute'));
    await tester.pump();
    expect(find.byTooltip('Unmute'), findsOneWidget);
    await tester.tap(find.byTooltip('Unmute'));
    await tester.pump();
    expect(find.byTooltip('Mute'), findsOneWidget);
  });

  testWidgets('slideshow pause toggles to play', (tester) async {
    await tester.pumpWidget(harness());
    await tester.tap(find.byTooltip('Pause slideshow'));
    await tester.pump();
    expect(find.byTooltip('Play slideshow'), findsOneWidget);
  });

  testWidgets('settings opens a glass dialog', (tester) async {
    await tester.pumpWidget(harness());
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Playback settings'), findsOneWidget);
    expect(find.text('media.example.com'), findsOneWidget);
  });
}
