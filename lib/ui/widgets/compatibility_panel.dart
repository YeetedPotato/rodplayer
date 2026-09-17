import 'package:flutter/material.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/playback/playback_diagnostics.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';

class CompatibilityPanel extends StatelessWidget {
  const CompatibilityPanel({super.key, required this.snapshot, required this.runtimeDiagnostics});
  final PlaybackDiagnosticsSnapshot? snapshot;
  final CapabilitySupport runtimeDiagnostics;

  @override
  Widget build(BuildContext context) {
    final data = snapshot;
    if (data == null) return const Center(child: Text('Playback diagnostics unavailable'));
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Text('Stats for Nerds', style: Theme.of(context).textTheme.titleLarge),
      _section('Playback', theme),
      _row('Method', _playMethod(data.playMethod), theme),
      _row('Backend', data.backendId, theme),
      if (data.runtimeId != null) _row('Runtime', data.runtimeId!, theme),
      if (data.deliveryMode != null) _row('Delivery', _deliveryMode(data.deliveryMode!), theme),
      _row('Video', _enum(data.videoOperation), theme),
      _row('Audio', _enum(data.audioOperation), theme),
      _row('Subtitles', _enum(data.subtitleOperation), theme),
      _row('HDR', _hdr(data.hdrHandling), theme),
      if (data.transcodeReasons.isNotEmpty) _row('Reasons', data.transcodeReasons.join(', '), theme),
      _section('Source', theme),
      if (data.container != null) _row('Container', data.container!, theme),
      if (data.protocol != null) _row('Protocol', data.protocol!, theme),
      if (data.sourceBitrate != null) _row('Bitrate', _bitrate(data.sourceBitrate!), theme),
      if (data.videoStream != null) ..._video(data.videoStream!, theme),
      if (data.audioStream != null) ..._audio(data.audioStream!, theme),
      if (data.subtitleStream != null) ..._subtitle(data.subtitleStream!, theme),
      _section('Runtime telemetry', theme),
      _row('Availability', switch (runtimeDiagnostics) { CapabilitySupport.supported => 'Supported', CapabilitySupport.unknown => 'Unknown', CapabilitySupport.unsupported => 'Not reported' }, theme),
    ]))));
  }

  List<Widget> _video(PlaybackDiagnosticsStream value, RodPlayerTheme theme) => <Widget>[
    _section('Video', theme),
    if (value.codec != null) _row('Codec', value.codec!, theme),
    if (value.profile != null) _row('Profile', value.profile!, theme),
    if (value.width != null && value.height != null) _row('Resolution', '${value.width}x${value.height}', theme),
    if (value.averageFrameRate != null || value.realFrameRate != null) _row('FPS', '${value.averageFrameRate ?? value.realFrameRate}', theme),
    if (value.bitDepth != null) _row('Bit depth', '${value.bitDepth}', theme),
    if (value.bitRate != null) _row('Bitrate', _bitrate(value.bitRate!), theme),
    if (value.videoRange != null) _row('Range', value.videoRange!, theme),
    if (value.videoRangeType != null) _row('Range type', value.videoRangeType!, theme),
  ];
  List<Widget> _audio(PlaybackDiagnosticsStream value, RodPlayerTheme theme) => <Widget>[
    _section('Audio', theme),
    if (value.codec != null) _row('Codec', value.codec!, theme),
    if (value.profile != null) _row('Profile', value.profile!, theme),
    if (value.channels != null) _row('Channels', '${value.channels}', theme),
    if (value.channelLayout != null) _row('Layout', value.channelLayout!, theme),
    if (value.audioSpatialFormat != null) _row('Spatial', value.audioSpatialFormat!, theme),
    if (value.language != null) _row('Language', value.language!, theme),
    if (value.title != null) _row('Title', value.title!, theme),
    if (value.bitRate != null) _row('Bitrate', _bitrate(value.bitRate!), theme),
  ];
  List<Widget> _subtitle(PlaybackDiagnosticsStream value, RodPlayerTheme theme) => <Widget>[
    _section('Subtitles', theme),
    if (value.codec != null) _row('Codec', value.codec!, theme),
    if (value.language != null) _row('Language', value.language!, theme),
    if (value.title != null) _row('Title', value.title!, theme),
    if (value.isExternal != null) _row('External', value.isExternal! ? 'Yes' : 'No', theme),
    if (value.isForced != null) _row('Forced', value.isForced! ? 'Yes' : 'No', theme),
    if (value.isDefault != null) _row('Default', value.isDefault! ? 'Yes' : 'No', theme),
    if (value.isTextSubtitleStream != null) _row('Text', value.isTextSubtitleStream! ? 'Yes' : 'No', theme),
  ];
  Widget _section(String text, RodPlayerTheme theme) => Padding(padding: const EdgeInsets.only(top: 12, bottom: 5), child: Text(text, style: TextStyle(color: theme.goldBright, fontWeight: FontWeight.w700)));
  Widget _row(String label, String value, RodPlayerTheme theme) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[SizedBox(width: 92, child: Text(label, style: TextStyle(color: theme.textMuted))), Expanded(child: Text(value, style: TextStyle(color: theme.textSecondary)))]));
  String _enum(Object value) => value.toString().split('.').last.replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match.group(1)}').trim().replaceFirstMapped(RegExp(r'^.'), (match) => match.group(0)!.toUpperCase());
  String _playMethod(PlayMethod value) => switch (value) { PlayMethod.directPlay => 'Direct Play', PlayMethod.directStream => 'Direct Stream', PlayMethod.transcode => 'Transcode' };
  String _deliveryMode(PlaybackDeliveryMode value) => switch (value) { PlaybackDeliveryMode.directPlay => 'Direct Play', PlaybackDeliveryMode.directStream => 'Direct Stream', PlaybackDeliveryMode.transcode => 'Transcode' };
  String _hdr(HdrHandling value) => switch (value) { HdrHandling.preserve => 'Preserve', HdrHandling.toneMapToSdr => 'Tone map to SDR', HdrHandling.none => 'None', HdrHandling.unknown => 'Unknown' };
  String _bitrate(int value) => value >= 1000000 ? '${(value / 1000000).toStringAsFixed(1)} Mbps' : '${(value / 1000).round()} kbps';
}
