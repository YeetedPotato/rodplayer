import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:rodplayer/core/api/remux_client.dart';
import 'package:rodplayer/core/player/player_controller.dart';
import 'package:rodplayer/core/theme/remux_theme.dart';

class VideoPlayerView extends StatefulWidget {
  const VideoPlayerView({super.key, required this.engine, required this.client, this.itemId});
  final RemuxEngine engine;
  final RemuxClient client;
  final String? itemId;
  @override State<VideoPlayerView> createState() => _VideoPlayerViewState();
}
class _VideoPlayerViewState extends State<VideoPlayerView> {
  Timer? _keepAlive;
  @override void initState() { super.initState(); widget.engine.error.addListener(_showPlaybackError); _keepAlive = Timer.periodic(const Duration(seconds: 10), (_) => unawaited(_report())); }
  void _showPlaybackError() { final message = widget.engine.error.value; if (!mounted || message == null || message.isEmpty) return; WidgetsBinding.instance.addPostFrameCallback((_) { if (!mounted) return; final theme = Theme.of(context).extension<RemuxTheme>() ?? const RemuxTheme(); ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text('Playback error: $message', style: TextStyle(color: theme.textPrimary)), backgroundColor: theme.obsidianRaised, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(theme.radiusMedium), side: BorderSide(color: theme.goldBright.withValues(alpha: 0.38))), action: SnackBarAction(label: 'RETRY', textColor: theme.goldBright, onPressed: () => unawaited(widget.engine.retry())))); }); }
  Future<void> _report() async { final id = widget.itemId; if (id == null) return; final playerState = widget.engine.player.state; await widget.client.reportProgress(itemId: id, position: playerState.position, duration: playerState.duration, isPaused: !playerState.playing); }
  @override void dispose() { widget.engine.error.removeListener(_showPlaybackError); _keepAlive?.cancel(); unawaited(_report()); super.dispose(); }
  @override Widget build(BuildContext context) { return PopScope(canPop: true, child: FocusTraversalGroup(policy: OrderedTraversalPolicy(), child: Focus(autofocus: true, onKeyEvent: (_, event) { if (event.logicalKey.keyLabel == 'Media Play Pause') widget.engine.player.playOrPause(); return KeyEventResult.ignored; }, child: Scaffold(backgroundColor: Colors.black, body: Stack(children: [Center(child: Video(controller: widget.engine.controller, controls: AdaptiveVideoControls)), Positioned(top: 20, left: 20, child: _Hud(engine: widget.engine)), Positioned(left: 20, right: 20, bottom: 24, child: _StatusBar(engine: widget.engine))]))))); }
}
class _Hud extends StatelessWidget { const _Hud({required this.engine}); final RemuxEngine engine; @override Widget build(BuildContext context) { final theme = Theme.of(context).extension<RemuxTheme>() ?? const RemuxTheme(); return StreamBuilder<bool>(stream: engine.player.stream.playing, builder: (_, snapshot) => Focus(child: DecoratedBox(decoration: BoxDecoration(color: theme.obsidianRaised, borderRadius: BorderRadius.circular(theme.radiusMedium), border: Border.all(color: theme.goldBright, width: 2), boxShadow: theme.goldGlow), child: IconButton(color: theme.goldBright, icon: Icon(snapshot.data == true ? Icons.pause : Icons.play_arrow), onPressed: engine.player.playOrPause)))); } }
class _StatusBar extends StatelessWidget { const _StatusBar({required this.engine}); final RemuxEngine engine; @override Widget build(BuildContext context) { final theme = Theme.of(context).extension<RemuxTheme>() ?? const RemuxTheme(); return StreamBuilder<String>(stream: engine.statuses, builder: (_, snapshot) { final message = snapshot.data; if (message == null || message.isEmpty) return const SizedBox.shrink(); return DecoratedBox(decoration: BoxDecoration(color: theme.obsidianRaised.withValues(alpha: 0.94), borderRadius: BorderRadius.circular(theme.radiusMedium), border: Border.all(color: theme.goldBright.withValues(alpha: 0.8)), boxShadow: theme.goldGlow), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.info_outline, color: theme.goldBright, size: 18), const SizedBox(width: 10), Flexible(child: Text(message, style: TextStyle(color: theme.goldBright), maxLines: 2, overflow: TextOverflow.ellipsis))]))); }); } }
