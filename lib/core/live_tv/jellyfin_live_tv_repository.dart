import 'package:flutter/foundation.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/api/models/live_tv.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/playback/multi_backend_playback_negotiator.dart';
import 'package:rodplayer/core/playback/playback_negotiator.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';

/// Live TV server support is independent of client platform and runtime
/// support. Unknown remains unknown until the server responds.
final class JellyfinLiveTvRepository {
  JellyfinLiveTvRepository({required this.client, required this.negotiator});

  final JellyfinApiClient client;
  final PlaybackNegotiator negotiator;
  final ValueNotifier<CapabilitySupport> serverCapability =
      ValueNotifier<CapabilitySupport>(CapabilitySupport.unknown);
  bool _disposed = false;

  Future<JellyfinItemsPage<JellyfinLiveTvChannel>> channels({
    int startIndex = 0,
    int limit = 100,
  }) async {
    try {
      final page = await client.getLiveTvChannelsPage(
        startIndex: startIndex,
        limit: limit,
      );
      _recordSupported();
      return page;
    } on ServerConnectionException catch (error) {
      _recordUnavailable(error);
      rethrow;
    }
  }

  Future<JellyfinItemsPage<JellyfinLiveTvProgram>> guide({
    Iterable<String> channelIds = const <String>[],
    required DateTime start,
    required DateTime end,
    int startIndex = 0,
    int limit = 200,
  }) async {
    try {
      final page = await client.getLiveTvProgramsPage(
        channelIds: channelIds,
        start: start,
        end: end,
        startIndex: startIndex,
        limit: limit,
      );
      _recordSupported();
      return page;
    } on ServerConnectionException catch (error) {
      _recordUnavailable(error);
      rethrow;
    }
  }

  Future<JellyfinLiveTvProgram> program(String id) =>
      client.getLiveTvProgram(id);

  /// Channels are Jellyfin items, so live tune negotiation uses the existing
  /// authoritative PlaybackInfo negotiator and runtime registry.
  Future<PlaybackPlanDecision> negotiateChannel(String channelId) =>
      negotiator.negotiateDecision(itemId: channelId);

  void _recordSupported() {
    if (!_disposed) serverCapability.value = CapabilitySupport.supported;
  }

  void _recordUnavailable(ServerConnectionException error) {
    if (!_disposed &&
        serverCapability.value != CapabilitySupport.supported &&
        (error.statusCode == 404 || error.statusCode == 405)) {
      serverCapability.value = CapabilitySupport.unsupported;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    serverCapability.dispose();
  }
}
