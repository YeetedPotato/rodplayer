import 'package:rodplayer/core/playback/advanced_playback.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/player/playback_engine.dart';
import 'package:rodplayer/core/player/playback_video_surface.dart';
import 'package:rodplayer/core/player/track_controller.dart';

class PlaybackRuntimeUnavailableException implements Exception {
  const PlaybackRuntimeUnavailableException(this.backendId);

  final String backendId;

  @override
  String toString() => 'PlaybackRuntimeUnavailableException: no runtime registered for "$backendId"';
}

class PlaybackActivationException implements Exception {
  const PlaybackActivationException(this.backendId, this.error);

  final String backendId;
  final Object error;

  @override
  String toString() => 'PlaybackActivationException: failed to activate "$backendId": $error';
}

class PlaybackActivationAggregateException implements Exception {
  const PlaybackActivationAggregateException(this.failures);

  final Map<String, Object> failures;

  @override
  String toString() => 'PlaybackActivationAggregateException: ${failures.entries.map((entry) => '${entry.key}: ${entry.value}').join('; ')}';
}

abstract interface class PlaybackBackendRuntime {
  String get backendId;
  bool get isAvailable;
  Future<PlaybackRuntimeSession> open(PlaybackPlan plan);
}

class PlaybackRuntimeSession {
  PlaybackRuntimeSession({
    required this.runtimeId,
    required this.plan,
    required this.engine,
    this.surface,
    this.tracks,
    this.advanced,
  });

  final String runtimeId;
  final PlaybackPlan plan;
  final PlaybackEngine engine;
  final PlaybackVideoSurface? surface;
  final TrackSelectionController? tracks;
  final AdvancedPlaybackControls? advanced;

  /// Explicit all-unsupported fallback for runtimes without advanced controls.
  AdvancedPlaybackCapabilities get advancedCapabilities => advanced?.capabilities ?? const AdvancedPlaybackCapabilities.unavailable();
  var _disposed = false;

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await engine.stop();
    await engine.dispose();
  }
}

class PlaybackRuntimeRegistry {
  const PlaybackRuntimeRegistry({
    this.runtimes = const <PlaybackBackendRuntime>[],
    this.executableBackendIds = const <String>{'media_kit'},
  });

  final List<PlaybackBackendRuntime> runtimes;
  final Set<String> executableBackendIds;

  PlaybackBackendRuntime? resolve(String backendId) {
    for (final runtime in runtimes) {
      if (runtime.backendId == backendId && runtime.isAvailable) return runtime;
    }
    return null;
  }

  bool canExecute(String backendId) => executableBackendIds.contains(backendId) || resolve(backendId) != null;
}
