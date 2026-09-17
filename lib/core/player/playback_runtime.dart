import 'package:rodplayer/core/playback/advanced_playback.dart';
import 'package:rodplayer/core/playback/logical_playback_session.dart';
import 'package:rodplayer/core/playback/playback_metadata.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/player/playback_engine.dart';
import 'package:rodplayer/core/player/playback_video_surface.dart';
import 'package:rodplayer/core/player/track_controller.dart';

/// Read-only, backend-neutral controls for the currently active runtime.
/// The coordinator replaces this snapshot whenever it replaces a runtime.
class PlaybackRuntimeControlsSnapshot {
  const PlaybackRuntimeControlsSnapshot({this.tracks, this.advanced});

  const PlaybackRuntimeControlsSnapshot.unavailable()
      : tracks = null,
        advanced = null;

  final TrackSelectionController? tracks;
  final AdvancedPlaybackControls? advanced;

  AdvancedPlaybackCapabilities get capabilities {
    final base = advanced?.capabilities ?? const AdvancedPlaybackCapabilities.unavailable();
    final trackCapabilities = tracks?.capabilities ?? const TrackSelectionCapabilities.unavailable();
    return base.withTrackSelection(
      audioTrackSwitching: trackCapabilities.audioSelection,
      subtitleTrackSwitching: trackCapabilities.subtitleSelection,
    );
  }

  factory PlaybackRuntimeControlsSnapshot.fromSession(PlaybackRuntimeSession session) => PlaybackRuntimeControlsSnapshot(
        tracks: session.tracks,
        advanced: session.advanced,
      );
}

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
    TrackSelectionController? tracks,
    this.advanced,
  }) : _tracks = tracks;

  final String runtimeId;
  final PlaybackPlan plan;
  final PlaybackEngine engine;
  final PlaybackVideoSurface? surface;
  TrackSelectionController? _tracks;
  TrackSelectionController? get tracks => _tracks;
  final AdvancedPlaybackControls? advanced;

  /// Runtime controls and track selection have separate owners. Track support
  /// is always derived from [tracks], never declared independently by controls.
  AdvancedPlaybackCapabilities get advancedCapabilities {
    final base = advanced?.capabilities ?? const AdvancedPlaybackCapabilities.unavailable();
    final trackCapabilities = tracks?.capabilities ?? const TrackSelectionCapabilities.unavailable();
    return base.withTrackSelection(
      audioTrackSwitching: trackCapabilities.audioSelection,
      subtitleTrackSwitching: trackCapabilities.subtitleSelection,
    );
  }

  void synchronizeMetadata(PlaybackMetadata metadata) {
    final controls = advanced;
    if (controls == null) return;
    try {
      controls.setChapters(metadata.chapters);
    } on Object {
      // Optional server metadata must never prevent playback activation.
    }
    try {
      controls.setMarkers(metadata.markers);
    } on Object {
      // Keep marker synchronization isolated from chapter synchronization.
    }
  }

  void bindLogicalSession(LogicalPlaybackSession session) {
    final tracks = _tracks;
    if (tracks != null && tracks is! LogicalSessionTrackSelectionController) {
      _tracks = LogicalSessionTrackSelectionController(delegate: tracks, session: session);
    }
  }
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
