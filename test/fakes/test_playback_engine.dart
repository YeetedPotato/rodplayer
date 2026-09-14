import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/player/playback_engine.dart';

class TestPlaybackEngine implements PlaybackEngine {
  @override
  final String id;

  @override
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);
  @override
  final ValueNotifier<bool> playing = ValueNotifier<bool>(false);
  @override
  final ValueNotifier<bool> buffering = ValueNotifier<bool>(false);
  @override
  final ValueNotifier<Duration> positionListenable = ValueNotifier<Duration>(Duration.zero);
  @override
  final ValueNotifier<Duration> durationListenable = ValueNotifier<Duration>(Duration.zero);
  @override
  final ValueNotifier<double> volume = ValueNotifier<double>(100);
  @override
  final Stream<String> statuses = const Stream<String>.empty();

  PlaybackPlan? loadedPlan;
  bool stopped = false;
  bool disposed = false;

  TestPlaybackEngine({this.id = 'test'});

  @override
  Duration get position => positionListenable.value;

  @override
  Duration get duration => durationListenable.value;

  set position(Duration value) => positionListenable.value = value;
  set duration(Duration value) => durationListenable.value = value;

  @override
  Future<void> load(PlaybackPlan plan) async {
    loadedPlan = plan;
    stopped = false;
  }

  @override
  Future<void> play() async {
    playing.value = true;
  }

  @override
  Future<void> pause() async {
    playing.value = false;
  }

  @override
  Future<void> playOrPause() => playing.value ? pause() : play();

  @override
  Future<void> seek(Duration position) async {
    this.position = position;
  }

  @override
  Future<void> setVolume(double value) async {
    volume.value = value.clamp(0, 100).toDouble();
  }

  @override
  Future<void> retry() async {}

  @override
  Future<void> stop() async {
    stopped = true;
    playing.value = false;
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    error.dispose();
    playing.dispose();
    buffering.dispose();
    positionListenable.dispose();
    durationListenable.dispose();
    volume.dispose();
  }
}
