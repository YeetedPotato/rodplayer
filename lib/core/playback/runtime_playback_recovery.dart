import 'package:rodplayer/core/playback/logical_playback_session.dart';
import 'package:rodplayer/core/playback/playback_negotiator.dart';
import 'package:rodplayer/core/playback/multi_backend_playback_negotiator.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/core/player/playback_runtime_coordinator.dart';

/// One backend-neutral recovery operation for the active runtime session.
typedef RuntimeRecoveryNegotiation = Future<List<PlaybackBackendCandidate>> Function({required String itemId, int? audioStreamIndex, int? subtitleStreamIndex});

class RuntimePlaybackRecovery {
  RuntimePlaybackRecovery({required this.coordinator, required this.session, this.negotiator, this.negotiate, this.maxRetries = 1}) : assert(negotiator != null || negotiate != null);

  final PlaybackRuntimeCoordinator coordinator;
  final LogicalPlaybackSession session;
  final PlaybackNegotiator? negotiator;
  final RuntimeRecoveryNegotiation? negotiate;
  final int maxRetries;
  var _generation = 0;
  var _recovering = false;
  var _disposed = false;

  Future<void> recover() async {
    if (_disposed || _recovering) return;
    _recovering = true;
    final generation = _generation;
    try {
      final active = coordinator.active;
      if (active == null) return;
      final engine = active.engine;
      final position = engine.position;
      final wasPlaying = engine.playing.value;
      for (var attempt = 0; attempt < maxRetries; attempt++) {
        try {
          await engine.retry();
          if (!_active(generation, active)) return;
          if (engine.error.value?.isNotEmpty == true) continue;
          await engine.seek(position);
          if (!_active(generation, active)) return;
          if (wasPlaying) { await engine.play(); } else { await engine.pause(); }
          if (!_active(generation, active)) return;
          return;
        } on Object {
          if (!_active(generation, active)) return;
        }
      }
      if (!_active(generation, active)) return;
      final candidates = negotiate != null
          ? await negotiate!(itemId: session.itemId, audioStreamIndex: session.selectedAudio, subtitleStreamIndex: session.selectedSubtitle)
          : (await negotiator!.negotiateDecision(itemId: session.itemId, audioStreamIndex: session.selectedAudio, subtitleStreamIndex: session.selectedSubtitle)).orderedUsableCandidates;
      if (!_active(generation, active)) return;
      final activated = await coordinator.activateCandidates(candidates, prepare: (candidate) async {
        await candidate.engine.seek(position);
        if (!_active(generation, active)) throw StateError('Recovery was superseded');
        if (wasPlaying) { await candidate.engine.play(); } else { await candidate.engine.pause(); }
        if (!_active(generation, active)) throw StateError('Recovery was superseded');
      });
      if (!_disposed && generation == _generation && identical(coordinator.active, activated)) session.position = position;
    } on Object {
      // The existing runtime remains authoritative when fallback activation fails.
    } finally {
      if (generation == _generation) _recovering = false;
    }
  }

  void invalidate() { _generation += 1; _recovering = false; }
  bool _active(int generation, PlaybackRuntimeSession active) => !_disposed && generation == _generation && identical(coordinator.active, active);
  void dispose() { _disposed = true; invalidate(); }
}
