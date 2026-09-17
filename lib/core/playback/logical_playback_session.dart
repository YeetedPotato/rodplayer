import 'package:flutter/foundation.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/playback/playback_metadata.dart';

class ServerPlaybackSession {
  const ServerPlaybackSession({required this.playSessionId, required this.mediaSourceId, required this.playMethod});

  final String? playSessionId;
  final String mediaSourceId;
  final PlayMethod playMethod;

  factory ServerPlaybackSession.fromPlan(PlaybackPlan plan) => ServerPlaybackSession(
        playSessionId: plan.playSessionId,
        mediaSourceId: plan.mediaSourceId,
        playMethod: plan.playMethod,
      );
}

class LogicalPlaybackSession {
  LogicalPlaybackSession({
    required this.id,
    required this.itemId,
    required PlaybackPlan activePlan,
    this.position = Duration.zero,
    PlaybackMetadata? metadata,
  })  : activePlan = activePlan,
        activeServerSession = ServerPlaybackSession.fromPlan(activePlan),
        selectedAudio = activePlan.selectedAudioStreamIndex,
        selectedSubtitle = activePlan.selectedSubtitleStreamIndex,
        metadata = metadata ?? PlaybackMetadata.fromPlan(activePlan) {
    _metadataNotifier = ValueNotifier<PlaybackMetadata>(this.metadata);
  }

  final String id;
  final String itemId;
  PlaybackPlan activePlan;
  ServerPlaybackSession activeServerSession;
  Duration position;
  int? selectedAudio;
  int? selectedSubtitle;
  PlaybackMetadata metadata;
  late final ValueNotifier<PlaybackMetadata> _metadataNotifier;
  ValueListenable<PlaybackMetadata> get metadataListenable => _metadataNotifier;

  void activatePlan(PlaybackPlan plan) {
    activePlan = plan;
    activeServerSession = ServerPlaybackSession.fromPlan(plan);
    selectedAudio = plan.selectedAudioStreamIndex;
    selectedSubtitle = plan.selectedSubtitleStreamIndex;
    updateMetadata(metadata.withPlanSource(plan));
  }

  void updateMetadata(PlaybackMetadata value) {
    metadata = value;
    _metadataNotifier.value = value;
  }
}
import 'package:flutter/foundation.dart';
import 'package:flutter/foundation.dart';
