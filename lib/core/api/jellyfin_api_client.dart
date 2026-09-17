import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rodplayer/core/api/models/playback_info_request.dart';
import 'package:rodplayer/core/api/models/playback_info_response.dart';
import 'package:rodplayer/core/api/models/media_segment.dart';
import 'package:rodplayer/core/device/installation_identity.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/models/jellyfin_user_profile.dart';

class JellyfinAuthException implements Exception {
  JellyfinAuthException(this.message);
  final String message;
  @override
  String toString() => 'JellyfinAuthException: $message';
}

class ServerConnectionException implements Exception {
  ServerConnectionException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => 'ServerConnectionException: $message';
}

enum JellyfinLibraryKind {
  movies('Movie'),
  tvShows('Series');

  const JellyfinLibraryKind(this.includeItemType);
  final String includeItemType;
}

enum JellyfinLibrarySort {
  title('Title', 'SortName', 'Ascending'),
  recentlyAdded('Recently Added', 'DateCreated', 'Descending'),
  releaseDate('Release Date', 'PremiereDate', 'Descending'),
  communityRating('Community Rating', 'CommunityRating', 'Descending');

  const JellyfinLibrarySort(this.label, this.sortBy, this.sortOrder);
  final String label;
  final String sortBy;
  final String sortOrder;
}

enum JellyfinLibraryFilter {
  all('All', null),
  unplayed('Unplayed', 'IsUnplayed'),
  favorites('Favorites', 'IsFavorite');

  const JellyfinLibraryFilter(this.label, this.filter);
  final String label;
  final String? filter;
}

enum JellyfinSearchType {
  all('All', 'Movie,Series,Episode,Audio'),
  movies('Movies', 'Movie'),
  tvShows('TV Shows', 'Series'),
  episodes('Episodes', 'Episode'),
  music('Music', 'Audio');

  const JellyfinSearchType(this.label, this.includeItemTypes);
  final String label;
  final String includeItemTypes;
}

enum JellyfinDiscoveryKind {
  movies('Movies', 'Movie'),
  tvShows('TV Shows', 'Series');

  const JellyfinDiscoveryKind(this.label, this.includeItemType);
  final String label;
  final String includeItemType;
}

enum JellyfinDiscoverySort {
  topRated('Top Rated', 'CommunityRating', 'Descending'),
  recentlyAdded('Recently Added', 'DateCreated', 'Descending'),
  releaseDate('Release Date', 'PremiereDate', 'Descending');

  const JellyfinDiscoverySort(this.label, this.sortBy, this.sortOrder);
  final String label;
  final String sortBy;
  final String sortOrder;
}

class JellyfinApiClient {
  JellyfinApiClient({
    required String baseUrl,
    required this.identity,
    http.Client? client,
  })  : baseUrl = baseUrl.replaceFirst(RegExp(r'/$'), ''),
        _client = client ?? http.Client();

  final String baseUrl;
  final InstallationIdentity identity;
  final http.Client _client;
  String? accessToken;
  String? userId;

  Map<String, String> get headers {
    final token = cleanToken(accessToken);
    final authorization = StringBuffer(
      'MediaBrowser Client="${identity.clientName}", Device="${identity.deviceName}", DeviceId="${identity.deviceId}", Version="${identity.appVersion}"',
    );
    if (token != null) authorization.write(', Token="$token"');
    return <String, String>{'Accept': 'application/json', 'Content-Type': 'application/json', 'Authorization': authorization.toString()};
  }

  static String? cleanToken(String? token) {
    final value = token?.trim();
    if (value == null || value.isEmpty) return null;
    return value.replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '').trim();
  }

  Future<Map<String, dynamic>> healthCheck() async {
    try {
      final response = await _client.get(Uri.parse('$baseUrl/System/Info/Public'));
      _check(response);
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (error) {
      if (error is ServerConnectionException) rethrow;
      throw ServerConnectionException('Unable to reach Jellyfin-compatible server: $error');
    }
  }

  Future<void> authenticate({required String username, required String password}) async {
    final response = await _client.post(Uri.parse('$baseUrl/Users/AuthenticateByName'), headers: headers, body: jsonEncode(<String, dynamic>{'Username': username, 'Pw': password}));
    if (response.statusCode == 401 || response.statusCode == 403) throw JellyfinAuthException('Server rejected the supplied credentials (${response.statusCode})');
    _check(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    accessToken = data['AccessToken'] as String?;
    userId = (data['User'] as Map<String, dynamic>?)?['Id'] as String?;
    if (accessToken == null || userId == null) throw JellyfinAuthException('Authentication response did not include AccessToken and User.Id');
  }

  String _userQuery() {
    final id = userId;
    if (id == null || id.isEmpty) throw JellyfinAuthException('Authenticate before requesting user items');
    return 'UserId=${Uri.encodeQueryComponent(id)}';
  }

  String _requireUserId() {
    final id = userId;
    if (id == null || id.isEmpty) throw JellyfinAuthException('Authenticate before requesting user items');
    return id;
  }

  Map<String, dynamic> _jsonObject(http.Response response) {
    _check(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw ServerConnectionException('Server returned malformed JSON object');
    return Map<String, dynamic>.from(decoded);
  }

  List<Map<String, dynamic>> _jsonList(http.Response response) {
    _check(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! List) throw ServerConnectionException('Server returned malformed JSON list');
    return decoded.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList(growable: false);
  }

  JellyfinItemsPage<T> _page<T>(Map<String, dynamic> json, T Function(Map<String, dynamic>) parse, {String key = 'Items'}) {
    final values = (json[key] as List<dynamic>? ?? const <dynamic>[]).whereType<Map>().map((item) => parse(Map<String, dynamic>.from(item))).toList(growable: false);
    return JellyfinItemsPage<T>(items: values, totalRecordCount: _int(json['TotalRecordCount']), startIndex: _int(json['StartIndex']));
  }

  Uri _uri(Iterable<String> pathSegments, Map<String, Object?> query) {
    final queryParameters = <String, String>{
      for (final entry in query.entries)
        if (entry.value != null) entry.key: '${entry.value}',
    };
    return jellyfinUri(baseUrl, pathSegments, queryParameters: queryParameters.isEmpty ? null : queryParameters);
  }

  Future<JellyfinItemsPage<JellyfinLibraryItem>> getItemsPage({int? startIndex, int? limit}) async => _page(
        _jsonObject(await _client.get(_uri(<String>['Items'], <String, Object?>{'UserId': _requireUserId(), if (startIndex != null) 'StartIndex': startIndex, if (limit != null) 'Limit': limit}), headers: headers)),
        JellyfinLibraryItem.fromJson,
      );
  Future<List<JellyfinLibraryItem>> getItems() async => (await getItemsPage()).items;
  Future<List<JellyfinLibraryItem>> getLatestMovies({int limit = 20}) async => (await getLibraryItemsPage(kind: JellyfinLibraryKind.movies, sort: JellyfinLibrarySort.recentlyAdded, limit: limit)).items;
  Future<List<JellyfinLibraryItem>> getLatestTvShows({int limit = 20}) async => (await getLibraryItemsPage(kind: JellyfinLibraryKind.tvShows, sort: JellyfinLibrarySort.recentlyAdded, limit: limit)).items;
  Future<List<NextUpItem>> getNextUp({int limit = 12}) async => _page(
        _jsonObject(await _client.get(_uri(<String>['Shows', 'NextUp'], <String, Object?>{'UserId': _requireUserId(), 'Limit': limit, 'Fields': 'PrimaryImageAspectRatio,Overview,ParentId,Taglines'}), headers: headers)),
        NextUpItem.fromJson,
      ).items;
  Future<List<ResumableItem>> getResumeItems({int limit = 12}) async => _page(
        _jsonObject(await _client.get(_uri(<String>['Items'], <String, Object?>{'UserId': _requireUserId(), 'Filters': 'IsResumable', 'Recursive': true, 'SortBy': 'DatePlayed', 'SortOrder': 'Descending', 'Limit': limit, 'Fields': 'PrimaryImageAspectRatio,Overview,ParentId,Taglines'}), headers: headers)),
        ResumableItem.fromJson,
      ).items;
  Future<List<JellyfinLibraryItem>> getUserViews() async => _page(_jsonObject(await _client.get(_uri(<String>['Users', _requireUserId(), 'Views'], const <String, Object?>{}), headers: headers)), JellyfinLibraryItem.fromJson).items;
  Future<JellyfinItemsPage<JellyfinLibraryItem>> getSearchItemsPage({
    required String query,
    JellyfinSearchType type = JellyfinSearchType.all,
    String? genre,
    int startIndex = 0,
    int limit = 48,
  }) async =>
      _page(
        _jsonObject(await _client.get(_uri(<String>['Items'], <String, Object?>{
          'UserId': _requireUserId(),
          'SearchTerm': query,
          'IncludeItemTypes': type.includeItemTypes,
          'Recursive': true,
          'StartIndex': startIndex,
          'Limit': limit,
          'EnableTotalRecordCount': true,
          'EnableImages': true,
          'EnableUserData': true,
          if (genre != null && genre.trim().isNotEmpty) 'Genres': genre.trim(),
          'Fields': _detailFields,
        }), headers: headers)),
        JellyfinLibraryItem.fromJson,
      );

  Future<JellyfinItemsPage<JellyfinLibraryItem>> getDiscoveryItemsPage({
    required JellyfinDiscoveryKind kind,
    JellyfinDiscoverySort sort = JellyfinDiscoverySort.topRated,
    String? genre,
    int startIndex = 0,
    int limit = 48,
  }) async =>
      _page(
        _jsonObject(await _client.get(_uri(<String>['Items'], <String, Object?>{
          'UserId': _requireUserId(),
          'IncludeItemTypes': kind.includeItemType,
          'Recursive': true,
          'StartIndex': startIndex,
          'Limit': limit,
          'SortBy': sort.sortBy,
          'SortOrder': sort.sortOrder,
          'EnableTotalRecordCount': true,
          'EnableImages': true,
          'EnableUserData': true,
          if (genre != null && genre.trim().isNotEmpty) 'Genres': genre.trim(),
          'Fields': _detailFields,
        }), headers: headers)),
        JellyfinLibraryItem.fromJson,
      );

  Future<List<String>> getGenres() async {
    final page = _page(
      _jsonObject(await _client.get(_uri(<String>['Genres'], <String, Object?>{
        'UserId': _requireUserId(),
        'IncludeItemTypes': 'Movie,Series',
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'EnableTotalRecordCount': false,
      }), headers: headers)),
      (json) => '${json['Name'] ?? ''}'.trim(),
    );
    return List<String>.unmodifiable(page.items.where((name) => name.isNotEmpty));
  }

  Future<JellyfinLibraryItem> getItem(String itemId) async => JellyfinLibraryItem.fromJson(_jsonObject(await _client.get(_uri(<String>['Users', _requireUserId(), 'Items', itemId], <String, Object?>{'Fields': _detailFields}), headers: headers)));

  Future<List<JellyfinLibraryItem>> getSeasons({required String seriesId}) async => _page(
        _jsonObject(await _client.get(_uri(<String>['Shows', seriesId, 'Seasons'], <String, Object?>{
          'UserId': _requireUserId(),
          'Fields': _detailFields,
          'EnableImages': true,
          'EnableUserData': true,
        }), headers: headers)),
        JellyfinLibraryItem.fromJson,
      ).items;

  Future<List<JellyfinLibraryItem>> getEpisodes({required String seriesId, required String seasonId}) async => _page(
        _jsonObject(await _client.get(_uri(<String>['Shows', seriesId, 'Episodes'], <String, Object?>{
          'UserId': _requireUserId(),
          'SeasonId': seasonId,
          'Fields': _detailFields,
          'EnableImages': true,
          'EnableUserData': true,
        }), headers: headers)),
        JellyfinLibraryItem.fromJson,
      ).items;

  Future<List<JellyfinLibraryItem>> getSimilarItems({required String itemId, int limit = 12}) async => _page(
        _jsonObject(await _client.get(_uri(<String>['Items', itemId, 'Similar'], <String, Object?>{
          'UserId': _requireUserId(),
          'Limit': limit,
          'Fields': _detailFields,
        }), headers: headers)),
        JellyfinLibraryItem.fromJson,
      ).items;

  /// Jellyfin 10.10+ media segments are keyed by the logical video item ID.
  /// Returns null only when an older server does not expose this endpoint.
  Future<List<JellyfinMediaSegment>?> getMediaSegments({required String itemId}) async {
    final response = await _client.get(_uri(<String>['MediaSegments', itemId], const <String, Object?>{}), headers: headers);
    if (response.statusCode == 404 || response.statusCode == 405) return null;
    final body = _jsonObject(response);
    final items = body['Items'];
    if (items is! List) throw ServerConnectionException('Server returned malformed media segment response');
    return List<JellyfinMediaSegment>.unmodifiable(
      items.whereType<Map>().map((item) => JellyfinMediaSegment.fromJson(Map<String, dynamic>.from(item))).whereType<JellyfinMediaSegment>(),
    );
  }

  Future<JellyfinUserProfile> getCurrentUser() async => JellyfinUserProfile.fromJson(_jsonObject(await _client.get(_uri(<String>['Users', _requireUserId()], const <String, Object?>{}), headers: headers)));

  Future<List<JellyfinUserProfile>> getPublicUsers() async => List<JellyfinUserProfile>.unmodifiable(_jsonList(await _client.get(_uri(<String>['Users', 'Public'], const <String, Object?>{}), headers: headers)).map(JellyfinUserProfile.fromJson));

  Future<void> updateCurrentUserConfiguration(JellyfinUserConfiguration configuration) async {
    final id = _requireUserId();
    final body = jsonEncode(configuration.toUpdateJson());
    final response = await _client.post(_uri(<String>['Users', 'Configuration'], <String, Object?>{'userId': id}), headers: headers, body: body);
    if (response.statusCode == 404 || response.statusCode == 405) {
      final fallback = await _client.post(_uri(<String>['Users', id, 'Configuration'], const <String, Object?>{}), headers: headers, body: body);
      _check(fallback);
      return;
    }
    _check(response);
  }

  Future<void> reportSessionEnded() async {
    final response = await _client.post(_uri(<String>['Sessions', 'Logout'], const <String, Object?>{}), headers: headers);
    _check(response);
  }

  Uri? userPrimaryImageUri(JellyfinUserProfile profile) {
    if (profile.id.trim().isEmpty || profile.primaryImageTag == null || profile.primaryImageTag!.trim().isEmpty) return null;
    return _uri(<String>['Users', profile.id, 'Images', 'Primary'], <String, Object?>{'tag': profile.primaryImageTag});
  }

  Future<JellyfinItemsPage<JellyfinLibraryItem>> getLibraryItemsPage({
    required JellyfinLibraryKind kind,
    JellyfinLibrarySort sort = JellyfinLibrarySort.title,
    JellyfinLibraryFilter filter = JellyfinLibraryFilter.all,
    int startIndex = 0,
    int limit = 48,
    String? parentId,
  }) async =>
      _page(
        _jsonObject(await _client.get(_uri(<String>['Items'], <String, Object?>{
          'UserId': _requireUserId(),
          'IncludeItemTypes': kind.includeItemType,
          'Recursive': true,
          'StartIndex': startIndex,
          'Limit': limit,
          'SortBy': sort.sortBy,
          'SortOrder': sort.sortOrder,
          'EnableTotalRecordCount': true,
          if (filter.filter != null) 'Filters': filter.filter,
          if (parentId != null && parentId.isNotEmpty) 'ParentId': parentId,
          'Fields': 'PrimaryImageAspectRatio,Overview,ParentId,Taglines',
        }), headers: headers)),
        JellyfinLibraryItem.fromJson,
      );

  Future<void> setFavorite({required String itemId, required bool isFavorite}) => _setUserDataFlag(
        itemId: itemId,
        enabled: isFavorite,
        modernRoute: 'UserFavoriteItems',
        legacyRoute: 'FavoriteItems',
      );

  Future<void> setPlayed({required String itemId, required bool played}) => _setUserDataFlag(
        itemId: itemId,
        enabled: played,
        modernRoute: 'UserPlayedItems',
        legacyRoute: 'PlayedItems',
      );

  Future<void> toggleFavorite({required String itemId, required bool isFavorite}) => setFavorite(itemId: itemId, isFavorite: isFavorite);

  Future<void> _setUserDataFlag({required String itemId, required bool enabled, required String modernRoute, required String legacyRoute}) async {
    final id = _requireUserId();
    final modern = _uri(<String>[modernRoute, itemId], <String, Object?>{'userId': id});
    final response = enabled ? await _client.post(modern, headers: headers) : await _client.delete(modern, headers: headers);
    if (response.statusCode == 404 || response.statusCode == 405) {
      final legacy = _uri(<String>['Users', id, legacyRoute, itemId], const <String, Object?>{});
      final fallback = enabled ? await _client.post(legacy, headers: headers) : await _client.delete(legacy, headers: headers);
      _check(fallback);
      return;
    }
    _check(response);
  }

  Future<PlaybackInfoResponse> getPlaybackInfo(PlaybackInfoRequest request) async {
    final response = await _client.post(Uri.parse('$baseUrl/Items/${request.itemId}/PlaybackInfo?${_userQuery()}'), headers: headers, body: jsonEncode(request.toJson()));
    _check(response);
    return PlaybackInfoResponse.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Uri buildDirectPlayUri({
    required String itemId,
    required String mediaSourceId,
    String? playSessionId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) {
    final query = <String, String>{
      'static': 'true',
      'mediaSourceId': mediaSourceId,
      if (playSessionId != null && playSessionId.isNotEmpty) 'playSessionId': playSessionId,
      if (audioStreamIndex != null) 'audioStreamIndex': '$audioStreamIndex',
      if (subtitleStreamIndex != null) 'subtitleStreamIndex': '$subtitleStreamIndex',
    };
    final token = cleanToken(accessToken);
    if (token != null) query['api_key'] = token;
    return Uri.parse('$baseUrl/Videos/${Uri.encodeComponent(itemId)}/stream').replace(queryParameters: query);
  }

  Uri resolvePlaybackUri(String path) {
    final uri = Uri.parse(path);
    final resolved = uri.hasScheme ? uri : Uri.parse(baseUrl).resolve(path);
    final token = cleanToken(accessToken);
    return token != null && !resolved.queryParameters.containsKey('api_key') ? resolved.replace(queryParameters: <String, String>{...resolved.queryParameters, 'api_key': token}) : resolved;
  }

  Future<void> reportPlaybackStarted(Map<String, dynamic> payload) => _postReport('/Sessions/Playing', payload);
  Future<void> reportPlaybackProgress(Map<String, dynamic> payload) => _postReport('/Sessions/Playing/Progress', payload);
  Future<void> reportPlaybackStopped(Map<String, dynamic> payload) => _postReport('/Sessions/Playing/Stopped', payload);

  Future<void> _postReport(String path, Map<String, dynamic> payload) async {
    final response = await _client.post(Uri.parse('$baseUrl$path'), headers: headers, body: jsonEncode(payload));
    _check(response);
  }

  void _check(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) throw ServerConnectionException('Server request failed (${response.statusCode})', statusCode: response.statusCode);
  }

  void close() => _client.close();
}

int? _int(Object? value) => value is num ? value.toInt() : int.tryParse('$value');
const _detailFields = 'PrimaryImageAspectRatio,Overview,ParentId,Taglines,Genres,Studios,People,Status,EndDate,ChildCount,RecursiveItemCount,Chapters';
