import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/playback/stream_token_provider.dart';

void main() {
  test('returns the initial token when valid', () async {
    var calls = 0;
    final provider = StreamTokenProvider(
      initialToken: 'plain-token',
      refreshToken: () async {
        calls++;
        return 'new-token';
      },
    );

    expect(await provider.getValidToken(), 'plain-token');
    expect(calls, 0);
  });

  test('refreshes when forced', () async {
    final provider = StreamTokenProvider(
      initialToken: 'old-token',
      refreshToken: () async => 'new-token',
    );

    expect(await provider.getValidToken(forceRefresh: true), 'new-token');
  });

  test('deduplicates concurrent refreshes', () async {
    var calls = 0;
    final gate = Completer<void>();
    final provider = StreamTokenProvider(refreshToken: () async {
      calls++;
      await gate.future;
      return 'fresh-token';
    });

    final first = provider.getValidToken(forceRefresh: true);
    final second = provider.getValidToken(forceRefresh: true);
    gate.complete();
    expect(await Future.wait([first, second]), ['fresh-token', 'fresh-token']);
    expect(calls, 1);
  });

  test('propagates refresh failures and permits a later retry', () async {
    var calls = 0;
    final provider = StreamTokenProvider(refreshToken: () async {
      calls++;
      if (calls == 1) throw StateError('offline');
      return 'recovered-token';
    });

    expect(provider.getValidToken(), throwsA(isA<StateError>()));
    expect(await provider.getValidToken(), 'recovered-token');
  });
}
