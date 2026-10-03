import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/capabilities/effective_feature_capability.dart';
import 'package:rodplayer/core/diagnostics/sanitized_diagnostics.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';

void main() {
  test('feature is supported only when every required source is supported',
      () {
    final result = effectiveFeatureAvailability(
      server: CapabilitySupport.supported,
      platform: CapabilitySupport.supported,
      backend: CapabilitySupport.supported,
      enabledPreference: true,
    );
    expect(result.support, CapabilitySupport.supported);
    expect(result.reason, AvailabilityReason.ready);
  });

  test('known unsupported prerequisite is reported before unknown state', () {
    final result = effectiveFeatureAvailability(
      server: CapabilitySupport.unknown,
      platform: CapabilitySupport.unsupported,
      backend: CapabilitySupport.unknown,
      enabledPreference: true,
    );
    expect(result.support, CapabilitySupport.unsupported);
    expect(result.reason, AvailabilityReason.platformCapability);
  });

  test('unknown never becomes supported and user preference gates the feature',
      () {
    final unknown = effectiveFeatureAvailability(
      server: CapabilitySupport.supported,
      platform: CapabilitySupport.unknown,
      backend: CapabilitySupport.supported,
      enabledPreference: true,
    );
    expect(unknown.support, CapabilitySupport.unknown);
    expect(unknown.reason, AvailabilityReason.platformCapability);

    final disabled = effectiveFeatureAvailability(
      server: CapabilitySupport.supported,
      platform: CapabilitySupport.supported,
      backend: CapabilitySupport.supported,
      enabledPreference: false,
    );
    expect(disabled.support, CapabilitySupport.unsupported);
    expect(disabled.reason, AvailabilityReason.userPreference);
  });
}
