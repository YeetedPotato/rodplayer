import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/player/playback_command_controller.dart';

void main() {
  test('preview request carries source identity and returns provenance',
      () async {
    final cancellation = ScrubPreviewCancellationToken();
    final source = _Source();
    final result = await source.request(ScrubPreviewRequest(
      position: const Duration(seconds: 30),
      source: const ScrubPreviewSourceIdentity(
          serverId: 'server', itemId: 'item', mediaSourceId: 'source'),
      cancellation: cancellation,
    ));
    expect(result, isA<ScrubPreviewAvailable>());
    expect((result as ScrubPreviewAvailable).provenance,
        ScrubPreviewProvenance.serverTrickplay);
  });

  test('cancelled preview resolves as typed unavailable instead of stale bytes',
      () async {
    final cancellation = ScrubPreviewCancellationToken()..cancel();
    final result = await _Source().request(ScrubPreviewRequest(
      position: Duration.zero,
      source: const ScrubPreviewSourceIdentity(
          serverId: 'server', itemId: 'item', mediaSourceId: 'source'),
      cancellation: cancellation,
    ));
    expect(result, isA<ScrubPreviewUnavailable>());
    expect((result as ScrubPreviewUnavailable).reason,
        ScrubPreviewUnavailableReason.cancelled);
  });
}

final class _Source implements ScrubPreviewSource {
  @override
  Future<ScrubPreviewResult> request(ScrubPreviewRequest request) async {
    if (request.cancellation.isCancelled) {
      return const ScrubPreviewUnavailable(
          ScrubPreviewUnavailableReason.cancelled);
    }
    return ScrubPreviewAvailable(
      bytes: Uint8List(0),
      provenance: ScrubPreviewProvenance.serverTrickplay,
    );
  }
}
