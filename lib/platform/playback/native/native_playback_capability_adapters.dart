import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/runtime_playback_environment.dart';
import 'package:rodplayer/platform/playback/native/native_playback_capability_models.dart';

class NativeComputeCapabilityAdapter {
  const NativeComputeCapabilityAdapter();

  PlaybackProbeUpdate<ComputeCapabilities> convert(NativeComputeProbeResult? result) {
    if (result == null) return const PlaybackProbeUpdate<ComputeCapabilities>.unreported();
    return PlaybackProbeUpdate<ComputeCapabilities>.reported(ComputeCapabilities(
      hardwareVideoDecoding: result.hardwareVideoDecoding,
      softwareVideoDecoding: result.softwareVideoDecoding,
      hardwareAcceleration: result.hardwareAcceleration,
      hdrMetadataDecode: result.hdrDecode,
      videoCodecs: result.videoDecoders
          .map(
            (decoder) => VideoCodecComputeCapability(
              codec: decoder.codec,
              support: decoder.support,
              profiles: decoder.profiles,
              levels: decoder.levels,
              maxBitDepth: decoder.maxBitDepth,
              maxWidth: decoder.maxWidth,
              maxHeight: decoder.maxHeight,
              maxFrameRate: decoder.maxFrameRate,
            ),
          )
          .toList(growable: false),
    ));
  }
}

class NativeDisplayCapabilityAdapter {
  const NativeDisplayCapabilityAdapter();

  PlaybackProbeUpdate<DisplayCapabilities> convert(NativeDisplayProbeResult? result) {
    if (result == null) return const PlaybackProbeUpdate<DisplayCapabilities>.unreported();
    return PlaybackProbeUpdate<DisplayCapabilities>.reported(DisplayCapabilities(
      currentWidth: result.width,
      currentHeight: result.height,
      pixelRatio: result.pixelRatio,
      refreshRate: result.refreshRate,
      displayId: result.displayId,
      displayName: result.displayName,
      activeHdr: result.activeHdr,
      outputColorCapability: result.genericHdrOutput,
      output: HdrOutputCapabilities(
        hdr10: result.hdr10Output,
        nativeHdr10Plus: result.hdr10PlusOutput,
        hlg: result.hlgOutput,
        nativeDolbyVision: result.dolbyVisionOutput,
      ),
      toneMapping: ToneMappingCapabilities(
        hdrToHdr: result.hdrToHdrToneMapping,
        hdrToSdr: result.hdrToSdrToneMapping,
      ),
    ));
  }
}

class NativeAudioCapabilityAdapter {
  const NativeAudioCapabilityAdapter();

  PlaybackProbeUpdate<AudioCapabilities> convert(NativeAudioProbeResult? result) {
    if (result == null) return const PlaybackProbeUpdate<AudioCapabilities>.unreported();
    return PlaybackProbeUpdate<AudioCapabilities>.reported(AudioCapabilities(
      device: DeviceAudioCapabilities(
        pcmOutput: result.pcmOutput,
        passthrough: result.passthrough,
        maxChannels: result.maxChannels,
        sampleRates: result.sampleRates,
      ),
      route: CurrentAudioRoute(
        name: result.routeName,
        passthrough: result.passthrough,
        maxChannels: result.maxChannels,
      ),
      sink: ConnectedSinkCapabilities(
        name: result.sinkName,
        passthroughCodecs: result.passthroughCodecs,
        maxChannels: result.maxChannels,
        objectAudio: result.objectAudio,
      ),
      effective: EffectiveAudioCapabilities(
        fidelity: result.fidelity,
        spatialMetadata: result.spatialMetadata,
        lossless: result.lossless,
        objectAudio: result.objectAudio,
        maxChannels: result.maxChannels,
      ),
    ));
  }
}
