import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/screens/browse_screen.dart';
import 'package:rodplayer/ui/screens/search_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

void main() {
  Widget app(Widget child) => MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, extensions: const <ThemeExtension<RodPlayerTheme>>[RodPlayerTheme()]),
        home: child,
      );

  testWidgets('Browse consumes typed Continue Watching and Next Up', (tester) async {
    final client = _FakeContentClient(
      resume: <ResumableItem>[ResumableItem.fromJson(<String, dynamic>{'Id': 'resume', 'Name': 'Resume Movie'})],
      nextUp: <NextUpItem>[NextUpItem.fromJson(<String, dynamic>{'Id': 'next', 'Name': 'Next Episode'})],
    );

    await tester.pumpWidget(app(BrowseScreen(client: client)));
    await tester.pumpAndSettle();

    expect(find.text('Resume Movie'), findsOneWidget);
    expect(find.text('Next Episode'), findsOneWidget);
  });

  testWidgets('Search consumes typed search hints', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final client = _FakeContentClient(
      searchResults: <JellyfinSearchHint>[JellyfinSearchHint.fromJson(<String, dynamic>{'ItemId': 'item', 'Name': 'Typed Result', 'Type': 'Movie'})],
    );

    await tester.pumpWidget(app(SearchScreen(client: client)));
    await tester.enterText(find.byType(TextField), 'typed');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Typed Result'), findsOneWidget);
    expect(find.text('Movie'), findsOneWidget);
    await tester.tap(find.text('Typed Result'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Play'), findsOneWidget);
  });

  testWidgets('missing image does not create invalid network URL', (tester) async {
    final client = _FakeContentClient(
      resume: <ResumableItem>[ResumableItem.fromJson(<String, dynamic>{'Id': 'resume', 'Name': 'No Art'})],
    );

    await tester.pumpWidget(app(BrowseScreen(client: client)));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsNothing);
    expect(find.text('No Art'), findsOneWidget);
  });
}

class _FakeContentClient extends JellyfinApiClient {
  _FakeContentClient({
    this.resume = const <ResumableItem>[],
    this.nextUp = const <NextUpItem>[],
    this.searchResults = const <JellyfinSearchHint>[],
  }) : super(baseUrl: 'https://server', identity: testIdentity, client: http.Client());

  final List<ResumableItem> resume;
  final List<NextUpItem> nextUp;
  final List<JellyfinSearchHint> searchResults;

  @override
  Future<List<ResumableItem>> getResumeItems({int limit = 12}) async => resume;

  @override
  Future<List<NextUpItem>> getNextUp({int limit = 12}) async => nextUp;

  @override
  Future<List<JellyfinSearchHint>> search({required String query, int limit = 20}) async => searchResults;

  @override
  Future<JellyfinLibraryItem> getItem(String itemId) async => JellyfinLibraryItem.fromJson(<String, dynamic>{'Id': itemId, 'Name': 'Typed Result', 'Type': 'Movie'});
}
