import 'package:rodplayer/core/diagnostics/sanitized_diagnostics.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';

/// Combines independent feature gates without treating missing knowledge as
/// support. A known unsupported prerequisite wins over an unknown one so the
/// UI can explain a concrete blocker when one exists.
FeatureAvailability effectiveFeatureAvailability({
  required CapabilitySupport server,
  required CapabilitySupport platform,
  required CapabilitySupport backend,
  required bool? enabledPreference,
}) {
  if (enabledPreference == false) {
    return const FeatureAvailability(
      support: CapabilitySupport.unsupported,
      reason: AvailabilityReason.userPreference,
    );
  }
  if (enabledPreference == null) {
    return const FeatureAvailability(
      support: CapabilitySupport.unknown,
      reason: AvailabilityReason.userPreference,
    );
  }

  final values = <(CapabilitySupport, AvailabilityReason)>[
    (server, AvailabilityReason.serverCapability),
    (platform, AvailabilityReason.platformCapability),
    (backend, AvailabilityReason.playbackBackend),
  ];
  for (final (support, reason) in values) {
    if (support == CapabilitySupport.unsupported) {
      return FeatureAvailability(support: support, reason: reason);
    }
  }
  for (final (support, reason) in values) {
    if (support == CapabilitySupport.unknown) {
      return FeatureAvailability(support: support, reason: reason);
    }
  }
  return const FeatureAvailability(
    support: CapabilitySupport.supported,
    reason: AvailabilityReason.ready,
  );
}
