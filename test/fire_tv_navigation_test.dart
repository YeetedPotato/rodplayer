import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/api/remux_client.dart';
import 'package:rodplayer/core/theme/remux_theme.dart';
import 'package:rodplayer/ui/screens/browse_screen.dart';
import 'package:rodplayer/ui/widgets/focusable_media_card.dart';

void main() {
  Widget testApp(Widget child) {
    return MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const <ThemeExtension<RemuxTheme>>[RemuxTheme()],
      ),
      home: child,
    );
  }

  testWidgets('browse screen exposes a PopScope and ordered focus traversal',
      (tester) async {
    final client = RemuxClient(baseUrl: 'http://127.0.0.1:1');
    addTearDown(client.close);

    await tester.pumpWidget(testApp(BrowseScreen(client: client)));
    await tester.pump();

    expect(find.byType(PopScope), findsOneWidget);
    expect(find.byType(FocusTraversalGroup), findsOneWidget);
    expect(find.byType(FocusableMediaCard), findsWidgets);
  });

  testWidgets('DPAD traversal moves focus between ElegantFin media cards',
      (tester) async {
    final firstFocus = FocusNode(debugLabel: 'first');
    final secondFocus = FocusNode(debugLabel: 'second');
    addTearDown(firstFocus.dispose);
    addTearDown(secondFocus.dispose);

    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Row(
              children: [
                SizedBox(
                  width: 200,
                  child: FocusableMediaCard(
                    key: const ValueKey<String>('first-card'),
                    title: 'First',
                    focusNode: firstFocus,
                    autofocus: true,
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: FocusableMediaCard(
                    key: const ValueKey<String>('second-card'),
                    title: 'Second',
                    focusNode: secondFocus,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(firstFocus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(secondFocus.hasFocus, isTrue);
  });

  testWidgets('focused cards use the ElegantFin Brand Gold token', (tester) async {
    final focusNode = FocusNode(debugLabel: 'gold-card');
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: FocusableMediaCard(
            title: 'Focused card',
            focusNode: focusNode,
            autofocus: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final theme = Theme.of(tester.element(find.byType(FocusableMediaCard)))
        .extension<RemuxTheme>()!;
    expect(theme.goldBright, const Color(0xFFEBCF52));
    expect(theme.goldBright.withValues(alpha: 0.32).a, closeTo(0.32, 0.01));
  });
}
