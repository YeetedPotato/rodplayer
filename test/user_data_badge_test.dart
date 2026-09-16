import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/widgets/focusable_media_card.dart';
import 'package:rodplayer/ui/widgets/user_data_badge.dart';

void main() {
  Widget app(Widget child) => MaterialApp(theme: rodPlayerThemeData(), home: Scaffold(body: Center(child: child)));

  testWidgets('user data badge renders favorite watched both and empty states', (tester) async {
    await tester.pumpWidget(app(UserDataBadge(userData: const JellyfinUserData())));
    expect(find.byIcon(Icons.favorite), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsNothing);

    await tester.pumpWidget(app(UserDataBadge(userData: const JellyfinUserData(isFavorite: true))));
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.bySemanticsLabel('Favorite'), findsOneWidget);

    await tester.pumpWidget(app(UserDataBadge(userData: const JellyfinUserData(played: true))));
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.bySemanticsLabel('Watched'), findsOneWidget);

    await tester.pumpWidget(app(UserDataBadge(userData: const JellyfinUserData(isFavorite: true, played: true))));
    expect(find.bySemanticsLabel('Favorite, Watched'), findsOneWidget);
  });

  testWidgets('badge fits compact media card', (tester) async {
    await tester.pumpWidget(app(const SizedBox(
      width: 140,
      height: 220,
      child: FocusableMediaCard(title: 'Title', badge: UserDataBadge(userData: JellyfinUserData(isFavorite: true, played: true))),
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
