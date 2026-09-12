import 'dart:async';
import 'dart:convert';

/// Supplies cached Jellyfin tokens and deduplicates refreshes.
class StreamTokenProvider {
  StreamTokenProvider({
    required this.refreshToken,
    this.initialToken,
    this.refreshBuffer = const Duration(minutes: 1),
  });

  final Future<String> Function() refreshToken;
  final String? initialToken;
  final Duration refreshBuffer;
  Future<String>? _refreshing;
  String? _token;

  Future<String> getValidToken({bool forceRefresh = false}) {
    _token ??= initialToken;
    if (!forceRefresh && _token != null && !_expiresSoon(_token!)) {
      return Future<String>.value(_token!);
    }
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<String> _refresh() async {
    final token = await refreshToken();
    if (token.isEmpty) throw StateError('Token refresh returned an empty token');
    _token = token;
    return token;
  }

  bool _expiresSoon(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return false;
      final payload = json.decode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = payload is Map<String, dynamic> ? payload['exp'] : null;
      if (exp is! num) return false;
      return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000)
          .isBefore(DateTime.now().add(refreshBuffer));
    } catch (_) {
      return false;
    }
  }
}
