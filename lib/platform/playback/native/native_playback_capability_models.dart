import 'package:rodplayer/core/playback/playback_environment.dart';

enum NativePlaybackHostPlatform { windows, android, apple, unknown }

class NativeVideoDecoderCapability {
  const NativeVideoDecoderCapability({
    required this.codec,
    required this.support,
    this.hardwareAccelerated = CapabilitySupport.unknown,
    this.softwareOnly = CapabilitySupport.unknown,
    this.profiles = const <String>[],
    this.levels = const <int>[],
    this.maxBitDepth,
    this.maxWidth,
    this.maxHeight,
    this.maxFrameRate,
  });

  final String codec;
  final CapabilitySupport support;
  final CapabilitySupport hardwareAccelerated;
  final CapabilitySupport softwareOnly;
  final List<String> profiles;
  final List<int> levels;
  final int? maxBitDepth;
  final int? maxWidth;
  final int? maxHeight;
  final double? maxFrameRate;

  static NativeVideoDecoderCapability? fromJson(Object? value) {
    if (value is! Map) return null;
    final codec = _string(value['codec']);
    if (codec == null || codec.isEmpty) return null;
    return NativeVideoDecoderCapability(
      codec: normalizeVideoCodec(codec),
      support: _support(value['support']),
      hardwareAccelerated: _support(value['hardwareAccelerated']),
      softwareOnly: _support(value['softwareOnly']),
      profiles: _strings(value['profiles']),
      levels: _ints(value['levels']),
      maxBitDepth: _int(value['maxBitDepth']),
      maxWidth: _int(value['maxWidth']),
      maxHeight: _int(value['maxHeight']),
      maxFrameRate: _double(value['maxFrameRate']),
    );
  }
}

class NativeComputeProbeResult {
  const NativeComputeProbeResult({
    this.adapterName,
    this.vendorId,
    this.deviceId,
    this.adapterIdentifier,
    this.softwareRenderer = CapabilitySupport.unknown,
    this.hardwareAcceleration = CapabilitySupport.unknown,
    this.hardwareVideoDecoding = CapabilitySupport.unknown,
    this.softwareVideoDecoding = CapabilitySupport.unknown,
    this.hdrDecode = const HdrDecodeCapabilities(),
    this.videoDecoders = const <NativeVideoDecoderCapability>[],
  });

  final String? adapterName;
  final int? vendorId;
  final int? deviceId;
  final String? adapterIdentifier;
  final CapabilitySupport softwareRenderer;
  final CapabilitySupport hardwareAcceleration;
  final CapabilitySupport hardwareVideoDecoding;
  final CapabilitySupport softwareVideoDecoding;
  final HdrDecodeCapabilities hdrDecode;
  final List<NativeVideoDecoderCapability> videoDecoders;

  static NativeComputeProbeResult? fromJson(Object? value) {
    if (value is! Map) return null;
    return NativeComputeProbeResult(
      adapterName: _string(value['adapterName']),
      vendorId: _int(value['vendorId']),
      deviceId: _int(value['deviceId']),
      adapterIdentifier: _string(value['adapterIdentifier']),
      softwareRenderer: _support(value['softwareRenderer']),
      hardwareAcceleration: _support(value['hardwareAcceleration']),
      hardwareVideoDecoding: _support(value['hardwareVideoDecoding']),
      softwareVideoDecoding: _support(value['softwareVideoDecoding']),
      hdrDecode: HdrDecodeCapabilities(
        hdr10: _support(value['decodeHdr10']),
        hdr10PlusMetadata: _support(value['decodeHdr10PlusMetadata']),
        hlg: _support(value['decodeHlg']),
        dolbyVision: _support(value['decodeDolbyVision']),
      ),
      videoDecoders: _list(value['videoDecoders']).map(NativeVideoDecoderCapability.fromJson).whereType<NativeVideoDecoderCapability>().toList(growable: false),
    );
  }
}

class NativeDisplayProbeResult {
  const NativeDisplayProbeResult({
    this.width,
    this.height,
    this.pixelRatio,
    this.refreshRate,
    this.displayId,
    this.displayName,
    this.activeHdr = CapabilitySupport.unknown,
    this.genericHdrOutput = CapabilitySupport.unknown,
    this.hdr10Output = CapabilitySupport.unknown,
    this.hdr10PlusOutput = CapabilitySupport.unknown,
    this.hlgOutput = CapabilitySupport.unknown,
    this.dolbyVisionOutput = CapabilitySupport.unknown,
    this.hdrToHdrToneMapping = CapabilitySupport.unknown,
    this.hdrToSdrToneMapping = CapabilitySupport.unknown,
  });

  final int? width;
  final int? height;
  final double? pixelRatio;
  final double? refreshRate;
  final String? displayId;
  final String? displayName;
  final CapabilitySupport activeHdr;
  final CapabilitySupport genericHdrOutput;
  final CapabilitySupport hdr10Output;
  final CapabilitySupport hdr10PlusOutput;
  final CapabilitySupport hlgOutput;
  final CapabilitySupport dolbyVisionOutput;
  final CapabilitySupport hdrToHdrToneMapping;
  final CapabilitySupport hdrToSdrToneMapping;

  static NativeDisplayProbeResult? fromJson(Object? value) {
    if (value is! Map) return null;
    return NativeDisplayProbeResult(
      width: _int(value['width']),
      height: _int(value['height']),
      pixelRatio: _double(value['pixelRatio']),
      refreshRate: _double(value['refreshRate']),
      displayId: _string(value['displayId']),
      displayName: _string(value['displayName']),
      activeHdr: _support(value['activeHdr']),
      genericHdrOutput: _support(value['genericHdrOutput']),
      hdr10Output: _support(value['hdr10Output']),
      hdr10PlusOutput: _support(value['hdr10PlusOutput']),
      hlgOutput: _support(value['hlgOutput']),
      dolbyVisionOutput: _support(value['dolbyVisionOutput']),
      hdrToHdrToneMapping: _support(value['hdrToHdrToneMapping']),
      hdrToSdrToneMapping: _support(value['hdrToSdrToneMapping']),
    );
  }
}

class NativeAudioProbeResult {
  const NativeAudioProbeResult({
    this.routeName,
    this.sinkName,
    this.pcmOutput = CapabilitySupport.unknown,
    this.passthrough = CapabilitySupport.unknown,
    this.maxChannels,
    this.sampleRates = const <int>[],
    this.passthroughCodecs = const <String, CapabilitySupport>{},
    this.lossless = CapabilitySupport.unknown,
    this.fidelity = CapabilitySupport.unknown,
    this.spatialMetadata = CapabilitySupport.unknown,
    this.objectAudio = CapabilitySupport.unknown,
  });

  final String? routeName;
  final String? sinkName;
  final CapabilitySupport pcmOutput;
  final CapabilitySupport passthrough;
  final int? maxChannels;
  final List<int> sampleRates;
  final Map<String, CapabilitySupport> passthroughCodecs;
  final CapabilitySupport lossless;
  final CapabilitySupport fidelity;
  final CapabilitySupport spatialMetadata;
  final CapabilitySupport objectAudio;

  static NativeAudioProbeResult? fromJson(Object? value) {
    if (value is! Map) return null;
    final passthrough = <String, CapabilitySupport>{};
    final nativeCodecs = value['passthroughCodecs'];
    if (nativeCodecs is Map) {
      for (final entry in nativeCodecs.entries) {
        final codec = _string(entry.key);
        if (codec != null) passthrough[normalizeAudioCodec(codec)] = _support(entry.value);
      }
    }
    return NativeAudioProbeResult(
      routeName: _string(value['routeName']),
      sinkName: _string(value['sinkName']),
      pcmOutput: _support(value['pcmOutput']),
      passthrough: _support(value['passthrough']),
      maxChannels: _int(value['maxChannels']),
      sampleRates: _ints(value['sampleRates']),
      passthroughCodecs: Map<String, CapabilitySupport>.unmodifiable(passthrough),
      lossless: _support(value['lossless']),
      fidelity: _support(value['fidelity']),
      spatialMetadata: _support(value['spatialMetadata']),
      objectAudio: _support(value['objectAudio']),
    );
  }
}

String normalizeVideoCodec(String codec) {
  final value = codec.toLowerCase().replaceAll('_', '-');
  if (value == 'avc' || value == 'h.264' || value == 'h264' || value == 'video/avc') return 'h264';
  if (value == 'h.265' || value == 'h265' || value == 'hevc' || value == 'hvc1' || value == 'hev1' || value == 'video/hevc') return 'hevc';
  if (value == 'av01' || value == 'av1' || value == 'video/av01') return 'av1';
  if (value == 'vp9' || value == 'video/x-vnd.on2.vp9') return 'vp9';
  if (value == 'vp8' || value == 'video/x-vnd.on2.vp8') return 'vp8';
  if (value == 'mpeg4' || value == 'mp4v-es' || value == 'video/mp4v-es') return 'mpeg4';
  if (value == 'mpeg2' || value == 'mpeg-2' || value == 'video/mpeg2') return 'mpeg2';
  return 'other';
}

String normalizeAudioCodec(String codec) {
  final value = codec.toLowerCase().replaceAll('_', '-');
  if (value == 'aac' || value == 'audio/mp4a-latm') return 'aac';
  if (value == 'ac3' || value == 'ac-3' || value == 'audio/ac3') return 'ac3';
  if (value == 'eac3' || value == 'e-ac-3' || value == 'audio/eac3' || value == 'eac3-joc') return 'eac3';
  if (value == 'truehd' || value == 'mlp') return 'truehd';
  if (value == 'dts' || value == 'dts-hd' || value == 'dtsx' || value == 'dts-x') return 'dts';
  if (value == 'flac') return 'flac';
  if (value == 'mp3' || value == 'mpeg') return 'mp3';
  if (value == 'opus') return 'opus';
  if (value == 'vorbis') return 'vorbis';
  if (value == 'alac') return 'alac';
  if (value == 'pcm' || value == 'lpcm') return 'pcm';
  return 'other';
}

CapabilitySupport _support(Object? value) {
  if (value is bool) return value ? CapabilitySupport.supported : CapabilitySupport.unsupported;
  if (value is! String) return CapabilitySupport.unknown;
  return switch (value.toLowerCase()) {
    'supported' => CapabilitySupport.supported,
    'true' => CapabilitySupport.supported,
    'unsupported' => CapabilitySupport.unsupported,
    'false' => CapabilitySupport.unsupported,
    _ => CapabilitySupport.unknown,
  };
}

String? _string(Object? value) => value is String ? value : null;

int? _int(Object? value) => switch (value) {
      int() => value,
      double() => value.round(),
      _ => null,
    };

double? _double(Object? value) => switch (value) {
      int() => value.toDouble(),
      double() => value,
      _ => null,
    };

List<Object?> _list(Object? value) => value is List ? value.cast<Object?>() : const <Object?>[];

List<String> _strings(Object? value) => _list(value).whereType<String>().toList(growable: false);

List<int> _ints(Object? value) => _list(value).map(_int).whereType<int>().toList(growable: false);
