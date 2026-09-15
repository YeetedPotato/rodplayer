import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/playback/playback_backend_registry.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/runtime_playback_environment.dart';
import 'package:rodplayer/platform/playback/native/native_playback_capability_adapters.dart';
import 'package:rodplayer/platform/playback/native/native_playback_capability_bridge.dart';
import 'package:rodplayer/platform/playback/native/native_playback_capability_models.dart';
import 'package:rodplayer/platform/playback/native/native_playback_capability_probes.dart';

void main() {
  group('Windows normalization', () {
    test('known hardware decoder maps to supported', () {
      final result = NativeComputeProbeResult.fromJson(<String, Object?>{
        'hardwareVideoDecoding': 'supported',
        'videoDecoders': <Object?>[
          <String, Object?>{
            'codec': 'video/avc',
            'support': 'supported',
            'hardwareAccelerated': 'supported',
            'softwareOnly': 'unsupported',
            'maxWidth': 3840,
            'maxHeight': 2160,
          },
        ],
      });

      final update = const NativeComputeCapabilityAdapter().convert(result);
      final capabilities = update.value!;
      final h264 = capabilities.videoCodecs.single;

      expect(update.isReported, isTrue);
      expect(capabilities.hardwareVideoDecoding, CapabilitySupport.supported);
      expect(h264.codec, 'h264');
      expect(h264.support, CapabilitySupport.supported);
      expect(h264.maxWidth, 3840);
    });

    test('absent codec remains unknown rather than unsupported', () {
      final result = NativeComputeProbeResult.fromJson(<String, Object?>{
        'videoDecoders': <Object?>[
          <String, Object?>{'codec': 'hevc', 'support': 'supported'},
        ],
      });
      final capabilities = const NativeComputeCapabilityAdapter().convert(result).value!;

      expect(capabilities.videoCodecs.any((codec) => codec.codec == 'av1'), isFalse);
      expect(capabilities.hardwareVideoDecoding, CapabilitySupport.unknown);
    });

    test('HDR decode does not imply HDR output', () {
      final compute = const NativeComputeCapabilityAdapter().convert(NativeComputeProbeResult(hdrDecode: HdrDecodeCapabilities(hdr10: CapabilitySupport.supported))).value!;
      final display = const NativeDisplayCapabilityAdapter().convert(const NativeDisplayProbeResult()).value!;

      expect(compute.hdrMetadataDecode.hdr10, CapabilitySupport.supported);
      expect(display.output.hdr10, CapabilitySupport.unknown);
    });

    test('generic HDR output does not imply Dolby Vision or HDR10+', () {
      final display = const NativeDisplayCapabilityAdapter().convert(const NativeDisplayProbeResult(genericHdrOutput: CapabilitySupport.supported)).value!;

      expect(display.outputColorCapability, CapabilitySupport.supported);
      expect(display.output.nativeDolbyVision, CapabilitySupport.unknown);
      expect(display.output.nativeHdr10Plus, CapabilitySupport.unknown);
    });
  });

  group('Android normalization', () {
    test('hardware decoder and software decoder distinction survives', () {
      final result = NativeComputeProbeResult.fromJson(<String, Object?>{
        'videoDecoders': <Object?>[
          <String, Object?>{'codec': 'video/hevc', 'support': 'supported', 'hardwareAccelerated': 'supported', 'softwareOnly': 'unsupported'},
          <String, Object?>{'codec': 'video/av01', 'support': 'supported', 'hardwareAccelerated': 'unsupported', 'softwareOnly': 'supported'},
        ],
      });
      final codecs = const NativeComputeCapabilityAdapter().convert(result).value!.videoCodecs;

      expect(codecs.singleWhere((codec) => codec.codec == 'hevc').support, CapabilitySupport.supported);
      expect(codecs.singleWhere((codec) => codec.codec == 'av1').support, CapabilitySupport.supported);
    });

    test('reported HDR display types map only to corresponding output fields', () {
      final hdr10 = const NativeDisplayCapabilityAdapter().convert(const NativeDisplayProbeResult(hdr10Output: CapabilitySupport.supported)).value!;
      final dolbyVision = const NativeDisplayCapabilityAdapter().convert(const NativeDisplayProbeResult(dolbyVisionOutput: CapabilitySupport.supported)).value!;
      final unknown = const NativeDisplayCapabilityAdapter().convert(const NativeDisplayProbeResult()).value!;

      expect(hdr10.output.hdr10, CapabilitySupport.supported);
      expect(hdr10.output.nativeDolbyVision, CapabilitySupport.unknown);
      expect(dolbyVision.output.nativeDolbyVision, CapabilitySupport.supported);
      expect(dolbyVision.output.hdr10, CapabilitySupport.unknown);
      expect(unknown.output.hlg, CapabilitySupport.unknown);
    });

    test('audio route data does not imply unsupported codec unless explicit', () {
      final audio = const NativeAudioCapabilityAdapter().convert(const NativeAudioProbeResult(routeName: 'HDMI', maxChannels: 8)).value!;

      expect(audio.route.name, 'HDMI');
      expect(audio.device.maxChannels, 8);
      expect(audio.sink.passthroughCodecs['truehd'], isNull);
    });
  });

  group('Apple normalization', () {
    test('hardware HEVC decode can be supported while Dolby Vision remains unknown', () {
      final compute = NativeComputeProbeResult.fromJson(<String, Object?>{
        'videoDecoders': <Object?>[
          <String, Object?>{'codec': 'hvc1', 'support': 'supported', 'hardwareAccelerated': 'supported'},
        ],
        'decodeDolbyVision': 'unknown',
      });
      final capabilities = const NativeComputeCapabilityAdapter().convert(compute).value!;

      expect(capabilities.videoCodecs.single.codec, 'hevc');
      expect(capabilities.videoCodecs.single.support, CapabilitySupport.supported);
      expect(capabilities.hdrMetadataDecode.dolbyVision, CapabilitySupport.unknown);
    });

    test('EDR or generic HDR state does not automatically imply native Dolby Vision', () {
      final display = const NativeDisplayCapabilityAdapter().convert(const NativeDisplayProbeResult(genericHdrOutput: CapabilitySupport.supported)).value!;

      expect(display.outputColorCapability, CapabilitySupport.supported);
      expect(display.output.nativeDolbyVision, CapabilitySupport.unknown);
    });

    test('audio route remains separate from backend capability', () {
      final audio = const NativeAudioCapabilityAdapter().convert(const NativeAudioProbeResult(routeName: 'Built-in Speakers', pcmOutput: CapabilitySupport.supported)).value!;

      expect(audio.route.name, 'Built-in Speakers');
      expect(audio.device.pcmOutput, CapabilitySupport.supported);
      expect(audio.engine.decodeCodecs, isEmpty);
    });
  });

  group('Backend registry', () {
    test('platform descriptors are deterministic and media_kit remains available', () {
      final registry = const PlaybackBackendRegistry();
      final android = registry.backendsFor(PlatformFamily.android);
      final windows = registry.backendsFor(PlatformFamily.windows);

      expect(android.map((backend) => backend.id), <String>['media_kit', 'android_native', 'android_compatibility']);
      expect(windows.map((backend) => backend.id), <String>['media_kit', 'windows_mpv']);
      expect(android.first.availability, BackendAvailability.available);
    });

    test('android native availability is explicit', () {
      final android = const PlaybackBackendRegistry(androidNativeAvailable: true).backendsFor(PlatformFamily.android);

      expect(android.singleWhere((backend) => backend.id == PlaybackBackendIds.androidNative).availability, BackendAvailability.available);
      expect(android.singleWhere((backend) => backend.id == PlaybackBackendIds.androidCompatibility).availability, BackendAvailability.unavailable);
    });

    test('future backends are not falsely marked available', () {
      final apple = const PlaybackBackendRegistry().backendsFor(PlatformFamily.ios);

      expect(apple.singleWhere((backend) => backend.id == PlaybackBackendIds.appleNative).availability, BackendAvailability.unavailable);
      expect(apple.singleWhere((backend) => backend.id == PlaybackBackendIds.appleCompatibility).availability, BackendAvailability.unavailable);
    });

    test('stable backend IDs are server independent', () {
      final allIds = <String>{
        for (final platform in PlatformFamily.values)
          for (final backend in const PlaybackBackendRegistry().backendsFor(platform)) backend.id,
      };

      expect(allIds, containsAll(<String>['media_kit', 'apple_native', 'android_native', 'windows_mpv']));
      expect(allIds.join(' ').toLowerCase(), isNot(contains('remux')));
    });
  });

  group('Bridge error handling', () {
    test('malformed payload returns unreported rather than crashing environment', () async {
      final probe = NativeComputeCapabilityProbe(bridge: _FakeBridge(compute: <String, Object?>{'videoDecoders': 'not-a-list'}));
      final update = await probe.probe(reason: PlaybackEnvironmentRefreshReason.manual);

      expect(update.isReported, isTrue);
      expect(update.value!.videoCodecs, isEmpty);
    });

    test('unsupported platform returns unreported', () async {
      final probe = NativeDisplayCapabilityProbe(bridge: const _FakeBridge());
      final update = await probe.probe(reason: PlaybackEnvironmentRefreshReason.manual);

      expect(update.isReported, isFalse);
    });

    test('prior valid domain state can survive unreported refresh', () async {
      final bridge = _MutableBridge(compute: <String, Object?>{'hardwareVideoDecoding': 'supported'});
      final provider = RuntimePlaybackEnvironmentProvider(
        identityProbe: const _IdentityProbe(),
        computeProbe: NativeComputeCapabilityProbe(bridge: bridge),
      );
      final first = await provider.load();
      bridge.compute = null;
      final second = await provider.refresh(PlaybackEnvironmentRefreshReason.manual);

      expect(first.compute.hardwareVideoDecoding, CapabilitySupport.supported);
      expect(second.compute.hardwareVideoDecoding, CapabilitySupport.supported);
    });
  });

  group('Checked-in host payload shapes', () {
    test('Android host payload shape decodes conservatively', () {
      final compute = NativeComputeProbeResult.fromJson(<String, Object?>{
        'hardwareVideoDecoding': 'supported',
        'videoDecoders': <Object?>[
          <String, Object?>{'codec': 'video/hevc', 'support': 'supported', 'hardwareAccelerated': 'supported', 'maxWidth': 3840},
          <String, Object?>{'codec': 'video/av01', 'support': 'supported', 'softwareOnly': 'supported'},
        ],
      });
      final display = NativeDisplayProbeResult.fromJson(<String, Object?>{'width': 3840, 'height': 2160, 'refreshRate': 59.94, 'hdr10Output': 'supported'});
      final audio = NativeAudioProbeResult.fromJson(<String, Object?>{
        'routeName': 'HDMI',
        'pcmOutput': 'supported',
        'passthroughCodecs': <String, Object?>{'ac3': 'supported'},
      });

      expect(const NativeComputeCapabilityAdapter().convert(compute).value!.videoCodecs.map((codec) => codec.codec).toList(), <String>['hevc', 'av1']);
      expect(const NativeDisplayCapabilityAdapter().convert(display).value!.output.hdr10, CapabilitySupport.supported);
      expect(const NativeAudioCapabilityAdapter().convert(audio).value!.sink.passthroughCodecs['ac3'], CapabilitySupport.supported);
    });

    test('Apple host payload shape leaves unproven capabilities unknown', () {
      final compute = NativeComputeProbeResult.fromJson(<String, Object?>{
        'hardwareVideoDecoding': 'supported',
        'videoDecoders': <Object?>[
          <String, Object?>{'codec': 'h264', 'support': 'supported', 'hardwareAccelerated': 'supported'},
          <String, Object?>{'codec': 'hevc', 'support': 'supported', 'hardwareAccelerated': 'supported'},
        ],
      });
      final display = NativeDisplayProbeResult.fromJson(<String, Object?>{'width': 1920, 'height': 1080, 'pixelRatio': 2.0, 'genericHdrOutput': 'supported'});
      final audio = NativeAudioProbeResult.fromJson(<String, Object?>{'routeName': 'Built-in Speakers', 'pcmOutput': 'supported'});

      expect(const NativeComputeCapabilityAdapter().convert(compute).value!.hdrMetadataDecode.dolbyVision, CapabilitySupport.unknown);
      expect(const NativeDisplayCapabilityAdapter().convert(display).value!.output.nativeHdr10Plus, CapabilitySupport.unknown);
      expect(const NativeAudioCapabilityAdapter().convert(audio).value!.sink.passthroughCodecs, isEmpty);
    });

    test('Windows host payload shape does not promote absent HDR or passthrough', () {
      final compute = NativeComputeProbeResult.fromJson(<String, Object?>{
        'hardwareVideoDecoding': 'supported',
        'videoDecoders': <Object?>[
          <String, Object?>{'codec': 'h264', 'support': 'supported', 'hardwareAccelerated': 'supported'},
        ],
      });
      final display = NativeDisplayProbeResult.fromJson(<String, Object?>{'width': 2560, 'height': 1440, 'refreshRate': 60.0});
      final audio = NativeAudioProbeResult.fromJson(<String, Object?>{'routeName': 'Default Output', 'pcmOutput': 'supported', 'maxChannels': 2});

      expect(const NativeComputeCapabilityAdapter().convert(compute).value!.videoCodecs.single.codec, 'h264');
      expect(const NativeDisplayCapabilityAdapter().convert(display).value!.output.hdr10, CapabilitySupport.unknown);
      expect(const NativeAudioCapabilityAdapter().convert(audio).value!.sink.passthroughCodecs, isEmpty);
    });
  });
}

class _FakeBridge implements NativePlaybackCapabilityBridge {
  const _FakeBridge({this.compute});

  final Object? compute;

  @override
  Future<NativeComputeProbeResult?> probeCompute() async => NativeComputeProbeResult.fromJson(compute);

  @override
  Future<NativeDisplayProbeResult?> probeDisplay() async => null;

  @override
  Future<NativeAudioProbeResult?> probeAudio() async => null;
}

class _MutableBridge implements NativePlaybackCapabilityBridge {
  _MutableBridge({this.compute});

  Object? compute;

  @override
  Future<NativeComputeProbeResult?> probeCompute() async => NativeComputeProbeResult.fromJson(compute);

  @override
  Future<NativeDisplayProbeResult?> probeDisplay() async => null;

  @override
  Future<NativeAudioProbeResult?> probeAudio() async => null;
}

class _IdentityProbe implements DeviceIdentityProbe {
  const _IdentityProbe();

  @override
  Future<DeviceIdentity> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  }) async =>
      const DeviceIdentity(
        installationId: 'device',
        clientName: 'RodPlayer',
        appVersion: 'test',
        platformFamily: PlatformFamily.unknown,
        deviceName: 'Test device',
      );
}
