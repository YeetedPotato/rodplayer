import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rodplayer/core/api/models/playback_info_request.dart';
import 'package:rodplayer/core/api/models/playback_info_response.dart';
import 'package:rodplayer/core/device/installation_identity.dart';

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

  List<dynamic> _items(http.Response response, {String key = 'Items'}) {
    _check(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data[key] as List<dynamic>?) ?? const <dynamic>[];
  }

  Future<List<dynamic>> getItems() async => _items(await _client.get(Uri.parse('$baseUrl/Items?${_userQuery()}'), headers: headers));
  Future<List<dynamic>> getLatestMovies({int limit = 20}) async => _items(await _client.get(Uri.parse('$baseUrl/Items?${_userQuery()}&IncludeItemTypes=Movie&Recursive=true&SortBy=DateCreated&SortOrder=Descending&Limit=$limit&Fields=PrimaryImageAspectRatio,UserData'), headers: headers));
  Future<List<dynamic>> getLatestTvShows({int limit = 20}) async => _items(await _client.get(Uri.parse('$baseUrl/Items?${_userQuery()}&IncludeItemTypes=Series&Recursive=true&SortBy=DateCreated&SortOrder=Descending&Limit=$limit&Fields=PrimaryImageAspectRatio,UserData'), headers: headers));
  Future<List<dynamic>> getNextUp({int limit = 12}) async => _items(await _client.get(Uri.parse('$baseUrl/Shows/NextUp?${_userQuery()}&Limit=$limit&Fields=PrimaryImageAspectRatio,UserData,SeriesName,SeasonNumber,IndexNumber,RunTimeTicks'), headers: headers));
  Future<List<dynamic>> getResumeItems({int limit = 12}) async => _items(await _client.get(Uri.parse('$baseUrl/Items?${_userQuery()}&Filters=IsResumable&Recursive=true&SortBy=DatePlayed&SortOrder=Descending&Limit=$limit&Fields=PrimaryImageAspectRatio,BackdropImageTags,UserData,SeriesName,SeasonNumber,IndexNumber,RunTimeTicks'), headers: headers));
  Future<List<dynamic>> getUserViews() async => _items(await _client.get(Uri.parse('$baseUrl/Users/$userId/Views'), headers: headers));
  Future<List<dynamic>> search({required String query, int limit = 20}) async => _items(await _client.get(Uri.parse('$baseUrl/Search/Hints?${_userQuery()}&SearchTerm=${Uri.encodeQueryComponent(query)}&Limit=$limit&IncludeItemTypes=Movie,Series,Episode'), headers: headers), key: 'SearchHints');

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
