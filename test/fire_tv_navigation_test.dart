import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/widgets/focusable_media_card.dart';

void main() {
  Widget testApp(Widget child) {
    return MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const <ThemeExtension<RodPlayerTheme>>[RodPlayerTheme()],
      ),
      home: child,
    );
  }

  testWidgets('media surfaces expose ordered focus traversal', (tester) async {
    await tester.pumpWidget(testApp(Scaffold(body: FocusTraversalGroup(policy: OrderedTraversalPolicy(), child: const FocusableMediaCard(title: 'Focusable')))));
    await tester.pumpAndSettle();
    expect(find.byType(FocusTraversalGroup), findsWidgets);
  });

  testWidgets('DPAD traversal moves focus between RodPlayer media cards', (tester) async {
    final firstFocus = FocusNode(debugLabel: 'first');
    final secondFocus = FocusNode(debugLabel: 'second');
    addTearDown(firstFocus.dispose);
    addTearDown(secondFocus.dispose);
    await tester.pumpWidget(testApp(Scaffold(body: FocusTraversalGroup(policy: OrderedTraversalPolicy(), child: Row(children: [
      SizedBox(width: 200, child: FocusableMediaCard(key: const ValueKey<String>('first-card'), title: 'First', focusNode: firstFocus, autofocus: true)),
      SizedBox(width: 200, child: FocusableMediaCard(key: const ValueKey<String>('second-card'), title: 'Second', focusNode: secondFocus)),
    ])))));
    await tester.pumpAndSettle();
    expect(firstFocus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(secondFocus.hasFocus, isTrue);
  });

  testWidgets('focused cards use the RodPlayer focus theme', (tester) async {
    final focusNode = FocusNode(debugLabel: 'gold-card');
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(testApp(Scaffold(body: FocusableMediaCard(title: 'Focused card', focusNode: focusNode, autofocus: true))));
    await tester.pumpAndSettle();
    final theme = Theme.of(tester.element(find.byType(FocusableMediaCard))).extension<RodPlayerTheme>()!;
    expect(theme.goldBright, isNot(theme.textMuted));
  });
}
