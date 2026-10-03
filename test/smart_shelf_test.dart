import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/widgets/smart_shelf.dart';

void main() {
  testWidgets('hovered desktop shelf arrows page the horizontal rail',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: rodPlayerThemeData(),
      home: Scaffold(
        body: SmartShelf(
          title: 'Movies',
          itemCount: 12,
          aspectRatio: 2 / 3,
          itemBuilder: (context, index, focusNode, {required autofocus}) =>
              Focus(
            focusNode: focusNode,
            child: SizedBox(
              width: 176,
              child: Center(child: Text('Movie $index')),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(find.byType(ListView).first);
    expect(list.controller!.offset, 0);
    expect(find.byTooltip('Scroll right'), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(const Offset(500, 240));
    await tester.pump();
    expect(find.byTooltip('Scroll right'), findsOneWidget);

    await tester.tap(find.byTooltip('Scroll right'));
    await tester.pumpAndSettle();
    expect(list.controller!.offset, greaterThan(0));
    expect(find.byTooltip('Scroll left'), findsOneWidget);

    final movedOffset = list.controller!.offset;
    await tester.tap(find.byTooltip('Scroll left'));
    await tester.pumpAndSettle();
    expect(list.controller!.offset, lessThan(movedOffset));
  });
}
