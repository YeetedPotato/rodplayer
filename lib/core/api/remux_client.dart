import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

/// Client for a Remux Emby/Jellyfin compatibility layer.
class RemuxClient {
  RemuxClient({required String baseUrl, http.Client? client})
      : baseUrl = baseUrl.replaceFirst(RegExp(r'/$'), ''),
        _client = client ?? http.Client(),
        deviceId = const Uuid().v4();

  final String baseUrl;
  final http.Client _client;
  final String deviceId;
  String? accessToken;
  String? sessionId;

  static const deviceProfile = {
    'Name': 'RodPlayer UHD Remux',
    'MaxStreamingBitrate': 140000000,
    'MaxStaticBitrate': 140000000,
    'DirectPlayProfiles': [
      {'Container': 'mp4,mkv,ts,m2ts', 'Type': 'Video', 'VideoCodec': 'h264,hevc,av1', 'AudioCodec': 'aac,ac3,eac3,truehd,dts,flac'}
    ],
    'TranscodingProfiles': [],
  };

  Map<String, String> get _headers {
    final token = _cleanToken(accessToken);
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null) ...{
        // Send the token using the common Emby/Jellyfin and bearer conventions.
        'Authorization': 'Bearer $token',
        'X-Emby-Token': token,
        'X-MediaBrowser-Token': token,
      },
    };
  }

  static String? _cleanToken(String? token) {
    final value = token?.trim();
    if (value == null || value.isEmpty) return null;
    return value.replaceFirst(RegExp(r'^Bearer\\s+', caseSensitive: false), '').trim();
  }

  Future<List<dynamic>> search(String query) async {
    final response = await _client.get(Uri.parse('$baseUrl/Items?searchTerm=${Uri.encodeQueryComponent(query)}&Recursive=true'), headers: _headers);
    _check(response);
    return (jsonDecode(response.body) as Map<String, dynamic>)['Items'] as List<dynamic>? ?? [];
  }

  Future<Uri> getStreamUri(String itemId) async {
    final response = await _client.post(Uri.parse('$baseUrl/Items/$itemId/PlaybackInfo'), headers: _headers, body: jsonEncode({'DeviceProfile': deviceProfile, 'StartTimeTicks': 0}));
    _check(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final sources = (data['MediaSources'] as List<dynamic>? ?? []);
    if (sources.isEmpty) throw StateError('Remux returned no playable media source');
    return Uri.parse((sources.first as Map<String, dynamic>)['Path'] as String);
  }

  Future<void> reportProgress({required String itemId, required Duration position, required Duration duration, bool isPaused = false}) async {
    if (sessionId == null) return;
    final ticks = position.inMicroseconds * 10;
    final totalTicks = duration.inMicroseconds * 10;
    await _client.post(Uri.parse('$baseUrl/Sessions/Playing/Progress'), headers: _headers, body: jsonEncode({'ItemId': itemId, 'SessionId': sessionId, 'PositionTicks': ticks, 'MediaSourceId': itemId, 'IsPaused': isPaused, 'PlayMethod': 'DirectPlay', 'EventName': 'timeupdate', 'RunTimeTicks': totalTicks}));
  }

  void _check(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) throw StateError('Remux request failed (${response.statusCode})');
  }

  void close() => _client.close();
}
