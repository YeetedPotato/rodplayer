import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/widgets/focusable_media_card.dart';

void main() {
  Widget app(Widget child) => MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, extensions: const <ThemeExtension<RodPlayerTheme>>[RodPlayerTheme()]),
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('constrained landscape metadata hides subtitle without overflow', (tester) async {
    await tester.pumpWidget(app(const SizedBox(
      width: 280,
      height: 170,
      child: FocusableMediaCard(title: 'Landscape title', subtitle: 'Hidden subtitle', aspectRatio: 16 / 9),
    )));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Landscape title'), findsOneWidget);
    expect(find.text('Hidden subtitle'), findsNothing);
  });

  testWidgets('landscape metadata shows subtitle when height is sufficient', (tester) async {
    await tester.pumpWidget(app(const SizedBox(
      width: 280,
      height: 360,
      child: FocusableMediaCard(title: 'Landscape title', subtitle: 'Visible subtitle', aspectRatio: 16 / 9),
    )));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Landscape title'), findsOneWidget);
    expect(find.text('Visible subtitle'), findsOneWidget);
  });
}
