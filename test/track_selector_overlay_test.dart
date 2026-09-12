import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/player/player_controller.dart';
import 'package:rodplayer/core/theme/remux_theme.dart';
import 'package:rodplayer/ui/player/track_selector_overlay.dart';

void main() {
  testWidgets('track selector renders TV-friendly sections and close control', (tester) async {
    final engine = RemuxEngine();
    addTearDown(engine.dispose);
    await tester.pumpWidget(MaterialApp(theme: remuxThemeData(), home: Scaffold(body: TrackSelectorOverlay(engine: engine))));
    expect(find.text('Tracks'), findsOneWidget);
    expect(find.text('AUDIO'), findsOneWidget);
    expect(find.text('SUBTITLES'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
  });
}
