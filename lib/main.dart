import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rodplayer/core/api/remux_client.dart';
import 'package:rodplayer/core/player/player_controller.dart';
import 'package:rodplayer/core/theme/remux_theme.dart';
import 'package:rodplayer/ui/player/video_player_view.dart';
import 'package:rodplayer/ui/screens/browse_screen.dart';
import 'package:rodplayer/ui/screens/login_screen.dart';

Future<void> main() async { WidgetsFlutterBinding.ensureInitialized(); MediaKit.ensureInitialized(); runApp(RodPlayerApp(preferences: await SharedPreferences.getInstance())); }
class RodPlayerApp extends StatelessWidget { const RodPlayerApp({required this.preferences, super.key}); final SharedPreferences preferences; @override Widget build(BuildContext context) => MaterialApp(title: 'Remux', theme: remuxThemeData(), home: RodPlayerShell(preferences: preferences)); }
class RodPlayerShell extends StatefulWidget { const RodPlayerShell({required this.preferences, super.key}); final SharedPreferences preferences; @override State<RodPlayerShell> createState() => _RodPlayerShellState(); }
class _RodPlayerShellState extends State<RodPlayerShell> { RemuxClient? _client; bool _loading = true;
 @override void initState(){super.initState(); _restore();}
 void _restore(){final p=widget.preferences; final url=p.getString('remux_server_url'); final token=p.getString('remux_access_token'); final user=p.getString('remux_user_id'); if(url != null && token != null && user != null && url.isNotEmpty && token.isNotEmpty && user.isNotEmpty){_client=RemuxClient(baseUrl:url)..accessToken=token..userId=user;} setState(()=>_loading=false);}
 Future<void> _authenticated(String url, RemuxClient client) async {await widget.preferences.setString('remux_server_url',url); await widget.preferences.setString('remux_access_token',client.accessToken!); await widget.preferences.setString('remux_user_id',client.userId!); if(mounted)setState(()=>_client=client);}
 Future<void> _logout() async {await widget.preferences.remove('remux_server_url'); await widget.preferences.remove('remux_access_token'); await widget.preferences.remove('remux_user_id'); _client?.close(); if(mounted)setState(()=>_client=null);}
 @override Widget build(BuildContext context){if(_loading)return const Scaffold(body:Center(child:CircularProgressIndicator())); if(_client==null)return LoginScreen(onAuthenticated:_authenticated); return CallbackShortcuts(bindings:{const SingleActivator(LogicalKeyboardKey.escape):(){Navigator.maybePop(context);}},child:BrowseScreen(client:_client!,onLogout:_logout));}}
Widget playerRoute(RodPlayerEngine engine, RemuxClient client, String itemId)=>VideoPlayerView(engine:engine,client:client,itemId:itemId);
