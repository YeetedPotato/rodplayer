import 'package:flutter/foundation.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';

abstract interface class PlaybackEngine {
  String get id;
  ValueListenable<String?> get error;
  ValueListenable<bool> get playing;
  ValueListenable<bool> get buffering;
  Duration get position;

  Future<void> load(PlaybackPlan plan);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();
  Future<void> dispose();
}
