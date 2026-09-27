import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/theme/appearance_mode.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/widgets/focusable_media_card.dart';
import 'package:rodplayer/ui/widgets/smart_shelf.dart';

void main() {
  Widget app(Widget child, {AppearanceMode? appearance, double textScale = 1}) => MaterialApp(
        theme: appearance == null
            ? ThemeData(brightness: Brightness.dark, extensions: const <ThemeExtension<RodPlayerTheme>>[RodPlayerTheme()])
            : rodPlayerThemeData(mode: appearance),
        home: Builder(builder: (context) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(body: Center(child: child)),
          );
        }),
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

  testWidgets('missing image URL uses placeholder without network image', (tester) async {
    await tester.pumpWidget(app(const SizedBox(width: 160, height: 240, child: FocusableMediaCard(title: 'No Art'))));
    await tester.pumpAndSettle();

    expect(find.text('No Art'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
  testWidgets('pointer hover scales the card without changing its layout', (tester) async {
    var taps = 0;
    await tester.pumpWidget(app(SizedBox(
      width: 160,
      height: 240,
      child: FocusableMediaCard(title: 'Hover card', onTap: () => taps++),
    )));
    await tester.pumpAndSettle();

    final card = find.byType(FocusableMediaCard);
    final scale = find.descendant(of: card, matching: find.byType(AnimatedScale));
    final layoutSize = tester.getSize(card);
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: tester.getCenter(card));
    await pointer.moveTo(tester.getCenter(card));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.widget<AnimatedScale>(scale).scale, 1.03);
    expect(tester.getSize(card), layoutSize);
    expect(taps, 0);
    await tester.tap(card);
    expect(taps, 1);
    await pointer.removePointer();
  });

  testWidgets('focused card uses semantic accent in Light Dark and OLED', (tester) async {
    for (final mode in <AppearanceMode>[AppearanceMode.light, AppearanceMode.dark, AppearanceMode.oled]) {
      final focusNode = FocusNode(debugLabel: 'appearance card');
      await tester.pumpWidget(app(SizedBox(
        width: 160,
        height: 240,
        child: FocusableMediaCard(title: 'Focused card', focusNode: focusNode, autofocus: true, onTap: () {}),
      ), appearance: mode));
      focusNode.requestFocus();
      await tester.pumpAndSettle();

      final card = find.byType(FocusableMediaCard);
      final scale = find.descendant(of: card, matching: find.byType(AnimatedScale));
      final decoration = tester.widget<AnimatedContainer>(find.descendant(of: card, matching: find.byType(AnimatedContainer)).first).decoration as BoxDecoration;
      final theme = rodPlayerPalette(mode);
      expect(tester.widget<AnimatedScale>(scale).scale, 1.045, reason: mode.name);
      expect((decoration.border! as Border).top.color, theme.accentBright, reason: mode.name);
      expect(tester.takeException(), isNull, reason: mode.name);
      await tester.pumpWidget(const SizedBox.shrink());
      focusNode.dispose();
    }
  });

  testWidgets('card keyboard activation and pointer tap share the existing callback', (tester) async {
    final focusNode = FocusNode(debugLabel: 'activation card');
    addTearDown(focusNode.dispose);
    var activations = 0;
    await tester.pumpWidget(app(SizedBox(
      width: 160,
      height: 240,
      child: FocusableMediaCard(title: 'Activate card', focusNode: focusNode, autofocus: true, onTap: () => activations++),
    )));
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(activations, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(activations, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(activations, 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    expect(activations, 4);
    await tester.tap(find.byType(FocusableMediaCard));
    expect(activations, 5);
  });

  testWidgets('shelf traversal focuses and activates each card directly', (tester) async {
    final focusNodes = <int, FocusNode>{};
    final activations = <int>[];
    await tester.pumpWidget(app(SizedBox(
      width: 600,
      height: 480,
      child: SmartShelf(
        title: 'Movies',
        itemCount: 3,
        autofocusFirstItem: true,
        itemBuilder: (context, index, focusNode, {required autofocus}) {
          focusNodes[index] = focusNode;
          return FocusableMediaCard(
            title: 'Traversal movie $index',
            focusNode: focusNode,
            autofocus: autofocus,
            onTap: () => activations.add(index),
          );
        },
      ),
    )));
    await tester.pumpAndSettle();

    expect(focusNodes[0]!.hasPrimaryFocus, isTrue);
    expect(FocusManager.instance.primaryFocus, same(focusNodes[0]));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(activations, <int>[0]);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(focusNodes[1]!.hasPrimaryFocus, isTrue);
    expect(FocusManager.instance.primaryFocus, same(focusNodes[1]));
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(activations, <int>[0, 1]);
  });

  testWidgets('card progress is clamped and uses the semantic accent', (tester) async {
    await tester.pumpWidget(app(const SizedBox(
      width: 160,
      height: 240,
      child: FocusableMediaCard(title: 'Progress card', progress: 1.4),
    )));
    final progress = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(progress.value, 1);
    expect(progress.color, rodPlayerPalette(AppearanceMode.oled).accentBright);
  });

  testWidgets('poster metadata remains usable at larger text scale', (tester) async {
    await tester.pumpWidget(app(
      const SizedBox(
        width: 160,
        height: 260,
        child: FocusableMediaCard(title: 'A long title that should truncate safely', subtitle: '2026 · Unrated'),
      ),
      textScale: 1.8,
    ));
    await tester.pumpAndSettle();

    expect(find.text('A long title that should truncate safely'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shelf gutter keeps a focused scaled card inside its viewport', (tester) async {
    late FocusNode focusNode;
    await tester.pumpWidget(app(SizedBox(
      width: 390,
      height: 480,
      child: SmartShelf(
        title: 'Movies',
        itemCount: 5,
        aspectRatio: 2 / 3,
        itemBuilder: (context, index, shelfFocusNode, {required autofocus}) {
          if (index == 0) focusNode = shelfFocusNode;
          return FocusableMediaCard(
            title: 'Movie $index',
            focusNode: shelfFocusNode,
            autofocus: autofocus,
            onTap: () {},
          );
        },
      ),
    )));
    await tester.pumpAndSettle();

    focusNode.requestFocus();
    await tester.pumpAndSettle();
    final viewport = tester.getRect(find.byType(ListView));
    final card = tester.getRect(find.byWidgetPredicate((widget) => widget is FocusableMediaCard && widget.title == 'Movie 0'));
    expect(card.left - viewport.left, greaterThanOrEqualTo(12));
    expect(card.top, greaterThanOrEqualTo(viewport.top - 1));
    expect(card.bottom, lessThanOrEqualTo(viewport.bottom + 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid shelf focus changes keep the newest item as reveal target', (tester) async {
    final focusNodes = <int, FocusNode>{};
    await tester.pumpWidget(app(SizedBox(
      width: 390,
      height: 480,
      child: SmartShelf(
        title: 'Movies',
        itemCount: 8,
        itemBuilder: (context, index, focusNode, {required autofocus}) {
          focusNodes[index] = focusNode;
          return FocusableMediaCard(
            title: 'Movie $index',
            focusNode: focusNode,
            autofocus: autofocus,
            onTap: () {},
          );
        },
      ),
    )));
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent - 250);
    await tester.pumpAndSettle();

    final viewportBeforeFocus = tester.getRect(find.byType(ListView));
    final lastCardBeforeFocus = tester.getRect(find.byWidgetPredicate(
      (widget) => widget is FocusableMediaCard && widget.title == 'Movie 7',
    ));
    expect(lastCardBeforeFocus.right, greaterThan(viewportBeforeFocus.right));

    focusNodes[7]!.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(focusNodes[7]!.hasFocus, isTrue);
    expect(scrollable.position.isScrollingNotifier.value, isTrue);
    await tester.pump(const Duration(milliseconds: 48));
    focusNodes[6]!.requestFocus();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 48));
    focusNodes[5]!.requestFocus();
    await tester.pumpAndSettle();

    final viewport = tester.getRect(find.byType(ListView));
    final currentCard = tester.getRect(find.byWidgetPredicate(
      (widget) => widget is FocusableMediaCard && widget.title == 'Movie 5',
    ));
    expect(focusNodes[5]!.hasPrimaryFocus, isTrue);
    expect(currentCard.left - viewport.left, greaterThanOrEqualTo(12));
    expect(currentCard.right, lessThan(viewport.right));
    expect(tester.takeException(), isNull);
  });
  testWidgets('last focused poster and landscape cards reserve trailing paint room', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(760, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final (aspectRatio, itemWidth) in <(double, double)>[(2 / 3, 176), (16 / 9, 280)]) {
      late FocusNode focusNode;
      const itemCount = 4;
      await tester.pumpWidget(app(SizedBox(
        width: 760,
        height: 480,
        child: SmartShelf(
          title: 'Movies',
          itemCount: itemCount,
          aspectRatio: aspectRatio,
          itemWidth: itemWidth,
          itemBuilder: (context, index, shelfFocusNode, {required autofocus}) {
            if (index == itemCount - 1) focusNode = shelfFocusNode;
            return FocusableMediaCard(
              title: 'Movie $index',
              aspectRatio: aspectRatio,
              focusNode: shelfFocusNode,
              autofocus: autofocus,
              onTap: () {},
            );
          },
        ),
      )));
      await tester.pumpAndSettle();

      focusNode.requestFocus();
      await tester.pumpAndSettle();

      final viewport = tester.getRect(find.byType(ListView));
      final card = tester.getRect(find.byWidgetPredicate(
        (widget) => widget is FocusableMediaCard && widget.title == 'Movie ${itemCount - 1}',
      ));
      final trailingGap = viewport.right - card.right;
      expect(trailingGap, inInclusiveRange(12, 24), reason: 'aspect ratio: $aspectRatio');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

}
