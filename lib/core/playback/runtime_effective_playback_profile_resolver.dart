import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/playback_backend_registry.dart';

class CompositeEffectivePlaybackProfileResolver implements EffectivePlaybackProfileResolver {
  const CompositeEffectivePlaybackProfileResolver({
    this.legacyResolver = const LegacyConservativePlaybackProfileResolver(),
    this.runtimeResolver = const RuntimeEffectivePlaybackProfileResolver(),
  });

  final EffectivePlaybackProfileResolver legacyResolver;
  final EffectivePlaybackProfileResolver runtimeResolver;

  @override
  EffectivePlaybackProfile resolve(PlaybackEnvironment environment, PlaybackBackendDescriptor backend) {
    if (backend.id == PlaybackBackendIds.appleNative) return runtimeResolver.resolve(environment, backend);
    return legacyResolver.resolve(environment, backend);
  }
}

class RuntimeCapabilityIntersection {
  const RuntimeCapabilityIntersection._();

  static CapabilitySupport combine(Iterable<CapabilitySupport> layers) {
    var sawLayer = false;
    var sawUnknown = false;
    for (final layer in layers) {
      sawLayer = true;
      if (layer == CapabilitySupport.unsupported) return CapabilitySupport.unsupported;
      if (layer == CapabilitySupport.unknown) sawUnknown = true;
    }
    if (!sawLayer) return CapabilitySupport.unknown;
    return sawUnknown ? CapabilitySupport.unknown : CapabilitySupport.supported;
  }
}

class RuntimeEffectivePlaybackProfileResolver implements EffectivePlaybackProfileResolver {
  const RuntimeEffectivePlaybackProfileResolver();

  @override
  EffectivePlaybackProfile resolve(PlaybackEnvironment environment, PlaybackBackendDescriptor backend) {
    final videoRules = <VideoCodecCapabilityRule>[
      for (final rule in backend.capabilities.videoCodecRules)
        if (_videoCodecSupport(environment, backend.capabilities, rule.codec) == CapabilitySupport.supported) rule,
    ];
    final audioRules = <AudioCodecCapabilityRule>[
      for (final rule in backend.capabilities.audioCodecRules)
        if (_audioCodecSupport(environment, backend.capabilities, rule.codec) == CapabilitySupport.supported) rule,
    ];
    return EffectivePlaybackProfile(
      backendId: backend.id,
      capabilities: backend.capabilities,
      deviceProfile: EffectiveDeviceProfile(
        maxStreamingBitrate: environment.network.maxStreamingBitrate,
        directPlayRules: _directPlayRules(environment, backend.capabilities),
        transcodingRules: backend.capabilities.transcodingRules,
        videoCodecRules: videoRules,
        audioCodecRules: audioRules,
        subtitleRules: backend.capabilities.subtitleRules,
      ),
    );
  }

  List<DirectPlayCapabilityRule> _directPlayRules(PlaybackEnvironment environment, PlaybackBackendCapabilities backend) {
    final rules = <DirectPlayCapabilityRule>[];
    for (final rule in backend.directPlayRules) {
      final videoCodecs = _supportedCodecs(rule.videoCodecs, (codec) => _videoCodecSupport(environment, backend, codec));
      final audioCodecs = _supportedCodecs(rule.audioCodecs, (codec) => _audioCodecSupport(environment, backend, codec));
      if (rule.videoCodecs.isNotEmpty && videoCodecs.isEmpty) continue;
      if (rule.audioCodecs.isNotEmpty && audioCodecs.isEmpty) continue;
      rules.add(DirectPlayCapabilityRule(
        containers: rule.containers,
        type: rule.type,
        videoCodecs: videoCodecs,
        audioCodecs: audioCodecs,
      ));
    }
    return rules;
  }

  List<String> _supportedCodecs(List<String> codecs, CapabilitySupport Function(String codec) supportFor) => <String>[
        for (final codec in codecs)
          if (supportFor(codec) == CapabilitySupport.supported) codec,
      ];

  CapabilitySupport hdrOutputSupport(PlaybackEnvironment environment, CapabilitySupport backendPreservesHdr) => RuntimeCapabilityIntersection.combine(<CapabilitySupport>[
        backendPreservesHdr,
        environment.display.output.hdr10,
      ]);

  CapabilitySupport audioPassthroughSupport(PlaybackEnvironment environment, PlaybackBackendCapabilities backend, String codec) => RuntimeCapabilityIntersection.combine(<CapabilitySupport>[
        backend.audioCodecSupport(codec),
        backend.passthrough,
        environment.audio.device.passthrough,
        environment.audio.route.passthrough,
        environment.audio.sink.passthroughCodecs[codec] ?? CapabilitySupport.unknown,
      ]);

  CapabilitySupport _videoCodecSupport(PlaybackEnvironment environment, PlaybackBackendCapabilities backend, String codec) {
    var deviceCodec = CapabilitySupport.unknown;
    for (final entry in environment.compute.videoCodecs) {
      if (entry.codec == codec) {
        deviceCodec = entry.support;
        break;
      }
    }
    return RuntimeCapabilityIntersection.combine(<CapabilitySupport>[
      backend.videoCodecSupport(codec),
      deviceCodec,
    ]);
  }

  CapabilitySupport _audioCodecSupport(PlaybackEnvironment environment, PlaybackBackendCapabilities backend, String codec) {
    return RuntimeCapabilityIntersection.combine(<CapabilitySupport>[
      backend.audioCodecSupport(codec),
      environment.audio.device.pcmOutput,
    ]);
  }
}
