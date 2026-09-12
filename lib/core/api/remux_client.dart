import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rodplayer/core/capabilities/platform_capabilities.dart';
import 'package:uuid/uuid.dart';

class RemuxAuthException implements Exception {
  RemuxAuthException(this.message);
  final String message;
  @override
  String toString() => 'RemuxAuthException: $message';
}

class RemuxConnectionException implements Exception {
  RemuxConnectionException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => 'RemuxConnectionException: $message';
}

class RemuxClient {
  RemuxClient({required String baseUrl, http.Client? client})
      : baseUrl = baseUrl.replaceFirst(RegExp(r'/$'), ''),
        _client = client ?? http.Client(),
        deviceId = const Uuid().v4();

  final String baseUrl;
  final http.Client _client;
  final String deviceId;
  String? accessToken;
  String? userId;
  String? sessionId;

  Map<String, String> get _headers {
    final token = _cleanToken(accessToken);
    final authorization = StringBuffer(
      'MediaBrowser Client="rodplayer", Device="FireTV", DeviceId="$deviceId", Version="1.0.0"',
    );
    if (token != null) authorization.write(', Token="$token"');
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': authorization.toString(),
    };
  }

  static String? _cleanToken(String? token) {
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
      if (error is RemuxConnectionException) rethrow;
      throw RemuxConnectionException('Unable to reach Remux server: $error');
    }
  }

  Future<void> authenticate({required String username, required String password}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/Users/AuthenticateByName'),
      headers: _headers,
      body: jsonEncode({'Username': username, 'Pw': password}),
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw RemuxAuthException('Jellyfin rejected the supplied credentials (${response.statusCode})');
    }
    _check(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    accessToken = data['AccessToken'] as String?;
    userId = (data['User'] as Map<String, dynamic>?)?['Id'] as String?;
    if (accessToken == null || userId == null) {
      throw RemuxAuthException('Authentication response did not include AccessToken and User.Id');
    }
  }

  String _userQuery() {
    final id = userId;
    if (id == null || id.isEmpty) throw RemuxAuthException('Authenticate before requesting user items');
    return 'userId=${Uri.encodeQueryComponent(id)}';
  }

  Future<Uri> getStreamUri(String itemId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/Items/$itemId/PlaybackInfo?${_userQuery()}'),
      headers: _headers,
      body: jsonEncode({
        'DeviceProfile': DeviceCapabilities.currentDeviceProfile(),
        'StartTimeTicks': 0,
      }),
    );
    _check(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final sources = data['MediaSources'] as List<dynamic>? ?? [];
    for (final value in sources) {
      if (value is! Map<String, dynamic>) continue;
      for (final key in const ['DirectStreamUrl', 'TranscodingUrl', 'Path']) {
        final candidate = value[key];
        if (candidate is! String || candidate.trim().isEmpty) continue;
        final parsed = Uri.parse(candidate.trim());
        if (key == 'Path' && parsed.scheme.isNotEmpty && !{'http', 'https', 'file'}.contains(parsed.scheme)) continue;
        final resolved = parsed.hasScheme ? parsed : Uri.parse(baseUrl).resolve(candidate.trim());
        final token = _cleanToken(accessToken);
        if (token != null && !resolved.queryParameters.containsKey('api_key')) {
          return resolved.replace(queryParameters: {...resolved.queryParameters, 'api_key': token});
        }
        return resolved;
      }
    }
    throw RemuxConnectionException('Remux returned no playable media source');
  }

  void _check(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RemuxConnectionException('Remux request failed (${response.statusCode})', statusCode: response.statusCode);
    }
  }

  void close() => _client.close();
}
