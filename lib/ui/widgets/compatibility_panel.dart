import 'package:flutter/material.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';

class PlaybackDiagnosticsSnapshot {
  const PlaybackDiagnosticsSnapshot({this.video, this.audio, this.mode});

  final String? video;
  final String? audio;
  final String? mode;

  bool get hasData => video != null || audio != null || mode != null;
}

class CompatibilityPanel extends StatelessWidget {
  const CompatibilityPanel({super.key, this.snapshot});

  final PlaybackDiagnosticsSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final data = snapshot;
    if (data == null || !data.hasData) return const SizedBox.shrink();
    final t = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('Playback diagnostics', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (data.video != null) _row('Video', data.video!, t),
          if (data.audio != null) _row('Audio', data.audio!, t),
          if (data.mode != null) _row('Mode', data.mode!, t),
        ]),
      ),
    );
  }

  Widget _row(String title, String value, RodPlayerTheme t) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(children: <Widget>[
          SizedBox(width: 72, child: Text(title, style: TextStyle(color: t.textMuted))),
          Expanded(child: Text(value, style: TextStyle(color: t.textSecondary))),
        ]),
      );
}
