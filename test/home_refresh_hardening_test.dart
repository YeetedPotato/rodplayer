import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/screens/home_screen.dart';

import 'test_support.dart';

void main() {
  Widget app(Widget child) => MaterialApp(theme: rodPlayerThemeData(), home: Scaffold(body: child));

  testWidgets('overlapping Continue Watching refresh keeps newer result', (tester) async {
    final client = _ControlledHomeClient();
    await tester.pumpWidget(app(HomeScreen(client: client)));
    await tester.pump();
    await tester.pumpWidget(app(HomeScreen(client: client, latestUserDataChange: const JellyfinUserDataChange(itemId: 'resume', played: true), userDataRevision: 1)));
    await tester.pump();

    client.resumeRequests[1].complete(<ResumableItem>[_resume('new', 'New Resume')]);
    client.nextUpRequests[0].complete(<NextUpItem>[]);
    client.nextUpRequests[1].complete(<NextUpItem>[]);
    await tester.pump();
    client.resumeRequests[0].complete(<ResumableItem>[_resume('old', 'Old Resume')]);
    await tester.pumpAndSettle();

    expect(find.text('New Resume'), findsWidgets);
    expect(find.text('Old Resume'), findsNothing);
  });

  testWidgets('stale Continue Watching failure does not replace newer success', (tester) async {
    final client = _ControlledHomeClient();
    await tester.pumpWidget(app(HomeScreen(client: client)));
    await tester.pump();
    await tester.pumpWidget(app(HomeScreen(client: client, latestUserDataChange: const JellyfinUserDataChange(itemId: 'resume', playbackProgressMayHaveChanged: true), userDataRevision: 1)));
    await tester.pump();

    client.resumeRequests[1].complete(<ResumableItem>[_resume('new', 'Fresh Resume')]);
    client.nextUpRequests[0].complete(<NextUpItem>[]);
    client.nextUpRequests[1].complete(<NextUpItem>[]);
    await tester.pump();
    client.resumeRequests[0].completeError(StateError('stale'));
    await tester.pumpAndSettle();

    expect(find.text('Fresh Resume'), findsWidgets);
    expect(find.text('Continue Watching unavailable'), findsNothing);
  });

  testWidgets('Next Up stale request protection and refresh scope are independent', (tester) async {
    final client = _ControlledHomeClient();
    await tester.pumpWidget(app(HomeScreen(client: client)));
    await tester.pump();
    expect((client.resumeRequests.length, client.nextUpRequests.length, client.movieCalls, client.showCalls), (1, 1, 1, 1));

    await tester.pumpWidget(app(HomeScreen(client: client, latestUserDataChange: const JellyfinUserDataChange(itemId: 'episode', played: true), userDataRevision: 1)));
    await tester.pump();
    expect((client.resumeRequests.length, client.nextUpRequests.length, client.movieCalls, client.showCalls), (2, 2, 1, 1));

    client.resumeRequests[1].complete(<ResumableItem>[_resume('resume', 'Resume')]);
    client.nextUpRequests[1].complete(<NextUpItem>[_nextUp('fresh', 'Fresh Next')]);
    await tester.pump();
    client.resumeRequests[0].complete(<ResumableItem>[]);
    client.nextUpRequests[0].complete(<NextUpItem>[_nextUp('old', 'Old Next')]);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Fresh Next'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Fresh Next'), findsWidgets);
    expect(find.text('Old Next'), findsNothing);

    await tester.pumpWidget(app(HomeScreen(client: client, latestUserDataChange: const JellyfinUserDataChange(itemId: 'movie', isFavorite: true), userDataRevision: 2)));
    await tester.pump();
    expect((client.resumeRequests.length, client.nextUpRequests.length, client.movieCalls, client.showCalls), (2, 2, 1, 1));
  });
}

class _ControlledHomeClient extends JellyfinApiClient {
  _ControlledHomeClient() : super(baseUrl: 'https://server', identity: testIdentity, client: http_testing.MockClient((_) async => http.Response('{}', 200)));

  final resumeRequests = <Completer<List<ResumableItem>>>[];
  final nextUpRequests = <Completer<List<NextUpItem>>>[];
  int movieCalls = 0;
  int showCalls = 0;

  @override
  Future<List<ResumableItem>> getResumeItems({int limit = 12}) {
    final completer = Completer<List<ResumableItem>>();
    resumeRequests.add(completer);
    return completer.future;
  }

  @override
  Future<List<NextUpItem>> getNextUp({int limit = 12}) {
    final completer = Completer<List<NextUpItem>>();
    nextUpRequests.add(completer);
    return completer.future;
  }

  @override
  Future<List<JellyfinLibraryItem>> getLatestMovies({int limit = 20}) async {
    movieCalls++;
    return <JellyfinLibraryItem>[_item('movie', 'Movie')];
  }

  @override
  Future<List<JellyfinLibraryItem>> getLatestTvShows({int limit = 20}) async {
    showCalls++;
    return <JellyfinLibraryItem>[_item('series', 'Series', type: 'Series')];
  }
}

ResumableItem _resume(String id, String name) => ResumableItem.fromJson(<String, dynamic>{'Id': id, 'Name': name, 'Type': 'Movie'});
NextUpItem _nextUp(String id, String name) => NextUpItem.fromJson(<String, dynamic>{'Id': id, 'Name': name, 'Type': 'Episode'});
JellyfinLibraryItem _item(String id, String name, {String type = 'Movie'}) => JellyfinLibraryItem.fromJson(<String, dynamic>{'Id': id, 'Name': name, 'Type': type});
