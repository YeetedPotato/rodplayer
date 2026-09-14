import 'package:flutter/foundation.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';

abstract interface class PlaybackEngine {
  String get id;
  ValueListenable<String?> get error;
  ValueListenable<bool> get playing;
  ValueListenable<bool> get buffering;
  ValueListenable<Duration> get positionListenable;
  ValueListenable<Duration> get durationListenable;
  ValueListenable<double> get volume;
  Stream<String> get statuses;
  Duration get position;
  Duration get duration;

  Future<void> load(PlaybackPlan plan);
  Future<void> play();
  Future<void> pause();
  Future<void> playOrPause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double value);
  Future<void> retry();
  Future<void> stop();
  Future<void> dispose();
}
