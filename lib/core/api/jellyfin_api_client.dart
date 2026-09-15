import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rodplayer/core/api/models/playback_info_request.dart';
import 'package:rodplayer/core/api/models/playback_info_response.dart';
import 'package:rodplayer/core/device/installation_identity.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';

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
  Future<List<JellyfinSearchHint>> search({required String query, int limit = 20}) async => _page(
        _jsonObject(await _client.get(_uri(<String>['Search', 'Hints'], <String, Object?>{'UserId': _requireUserId(), 'SearchTerm': query, 'Limit': limit, 'IncludeItemTypes': 'Movie,Series,Episode'}), headers: headers)),
        JellyfinSearchHint.fromJson,
        key: 'SearchHints',
      ).items;

  Future<JellyfinLibraryItem> getItem(String itemId) async => JellyfinLibraryItem.fromJson(_jsonObject(await _client.get(_uri(<String>['Users', _requireUserId(), 'Items', itemId], const <String, Object?>{}), headers: headers)));

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

  Future<void> toggleFavorite({required String itemId, required bool isFavorite}) async {
    final endpoint = Uri.parse('$baseUrl/Users/$userId/FavoriteItems/$itemId');
    final response = isFavorite ? await _client.post(endpoint, headers: headers) : await _client.delete(endpoint, headers: headers);
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
