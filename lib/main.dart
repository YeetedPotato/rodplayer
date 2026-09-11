import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'core/api/remux_client.dart';
import 'core/player/player_controller.dart';
import 'ui/player/video_player_view.dart';

void main() { WidgetsFlutterBinding.ensureInitialized(); MediaKit.ensureInitialized(); runApp(const RodPlayerApp()); }
class RodPlayerApp extends StatelessWidget { const RodPlayerApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(title: 'RodPlayer', theme: ThemeData.dark(useMaterial3: true), home: Builder(builder: (context) => const _EmptyHome())); }
class _EmptyHome extends StatelessWidget { const _EmptyHome(); @override Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Configure a Remux server to begin playback.'))); }
// VideoPlayerView is exported for integration screens and route wiring.
// ignore: unused_element
Widget playerRoute(RodPlayerEngine engine, RemuxClient client, String itemId) => VideoPlayerView(engine: engine, client: client, itemId: itemId);
