import 'package:rodplayer/core/models/server_identity.dart';

enum DownloadJobState {
  queued,
  preparing,
  downloading,
  paused,
  completed,
  failed,
  cancelled,
  removing
}

enum OfflineUserActionKind { progress, watched, unwatched }

final class DownloadJob {
  const DownloadJob({
    required this.id,
    required this.owner,
    required this.itemId,
    required this.mediaSourceId,
    required this.state,
    required this.revision,
    required this.updatedAt,
    this.bytesReceived = 0,
    this.expectedBytes,
    this.fileReference,
    this.errorCode,
    this.retryCount = 0,
  });

  final String id;
  final ServerAccountId owner;
  final String itemId;
  final String mediaSourceId;
  final DownloadJobState state;
  final int revision;
  final DateTime updatedAt;
  final int bytesReceived;
  final int? expectedBytes;
  final String? fileReference;
  final String? errorCode;
  final int retryCount;

  ServerMediaItemId get mediaIdentity =>
      ServerMediaItemId(accountId: owner, itemId: itemId);

  DownloadJob transition(
    DownloadJobState next, {
    required DateTime at,
    int? bytesReceived,
    int? expectedBytes,
    String? fileReference,
    String? errorCode,
  }) {
    if (!_allowedTransitions[state]!.contains(next))
      throw StateError('Invalid download state transition: $state -> $next');
    final received = bytesReceived ?? this.bytesReceived;
    final expected = expectedBytes ?? this.expectedBytes;
    if (received < 0 ||
        (expected != null && (expected < 0 || received > expected)))
      throw ArgumentError('Invalid download byte counts');
    if (next == DownloadJobState.completed &&
        (fileReference ?? this.fileReference) == null)
      throw StateError('Completed download requires a managed file reference');
    return DownloadJob(
      id: id,
      owner: owner,
      itemId: itemId,
      mediaSourceId: mediaSourceId,
      state: next,
      revision: revision + 1,
      updatedAt: at,
      bytesReceived: received,
      expectedBytes: expected,
      fileReference: fileReference ?? this.fileReference,
      errorCode: errorCode,
      retryCount: retryCount +
          (next == DownloadJobState.preparing &&
                  state == DownloadJobState.failed
              ? 1
              : 0),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'owner': owner.toJson(),
        'itemId': itemId,
        'mediaSourceId': mediaSourceId,
        'state': state.name,
        'revision': revision,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'bytesReceived': bytesReceived,
        if (expectedBytes != null) 'expectedBytes': expectedBytes,
        if (fileReference != null) 'fileReference': fileReference,
        if (errorCode != null) 'errorCode': errorCode,
        'retryCount': retryCount,
      };

  factory DownloadJob.fromJson(Map<String, Object?> json) {
    final stateName = json['state'];
    DownloadJobState? state;
    for (final value in DownloadJobState.values) {
      if (value.name == stateName) {
        state = value;
        break;
      }
    }
    if (state == null) throw const FormatException('Invalid download state');
    return DownloadJob(
      id: _required(json['id'], 'job ID'),
      owner: ServerAccountId.fromJson(
          Map<String, Object?>.from(json['owner']! as Map)),
      itemId: _required(json['itemId'], 'item ID'),
      mediaSourceId: _required(json['mediaSourceId'], 'media source ID'),
      state: state,
      revision: _nonnegative(json['revision']),
      updatedAt: DateTime.parse(json['updatedAt']! as String).toUtc(),
      bytesReceived: _nonnegative(json['bytesReceived']),
      expectedBytes: json['expectedBytes'] == null
          ? null
          : _nonnegative(json['expectedBytes']),
      fileReference: json['fileReference'] as String?,
      errorCode: json['errorCode'] as String?,
      retryCount: _nonnegative(json['retryCount']),
    );
  }
}

const Map<DownloadJobState, Set<DownloadJobState>> _allowedTransitions =
    <DownloadJobState, Set<DownloadJobState>>{
  DownloadJobState.queued: <DownloadJobState>{
    DownloadJobState.preparing,
    DownloadJobState.cancelled,
    DownloadJobState.removing
  },
  DownloadJobState.preparing: <DownloadJobState>{
    DownloadJobState.downloading,
    DownloadJobState.failed,
    DownloadJobState.cancelled
  },
  DownloadJobState.downloading: <DownloadJobState>{
    DownloadJobState.paused,
    DownloadJobState.completed,
    DownloadJobState.failed,
    DownloadJobState.cancelled
  },
  DownloadJobState.paused: <DownloadJobState>{
    DownloadJobState.downloading,
    DownloadJobState.cancelled,
    DownloadJobState.removing
  },
  DownloadJobState.completed: <DownloadJobState>{DownloadJobState.removing},
  DownloadJobState.failed: <DownloadJobState>{
    DownloadJobState.preparing,
    DownloadJobState.cancelled,
    DownloadJobState.removing
  },
  DownloadJobState.cancelled: <DownloadJobState>{DownloadJobState.removing},
  DownloadJobState.removing: <DownloadJobState>{},
};

final class OfflineUserAction {
  const OfflineUserAction(
      {required this.identity,
      required this.kind,
      required this.revision,
      this.positionTicks});
  final ServerMediaItemId identity;
  final OfflineUserActionKind kind;
  final int revision;
  final int? positionTicks;
}

/// Latest-wins local outbox. Manual watched/unwatched actions supersede older
/// progress; an in-flight completion only removes the revision it sent.
final class OfflineWatchActionLedger {
  final Map<ServerMediaItemId, OfflineUserAction> _pending = {};
  int _revision = 0;

  Iterable<OfflineUserAction> get pending =>
      List<OfflineUserAction>.unmodifiable(_pending.values);

  OfflineUserAction enqueueProgress(ServerMediaItemId identity, int ticks) {
    if (ticks < 0) throw ArgumentError.value(ticks, 'ticks');
    final existing = _pending[identity];
    if (existing?.kind == OfflineUserActionKind.watched ||
        existing?.kind == OfflineUserActionKind.unwatched) return existing!;
    return _set(identity, OfflineUserActionKind.progress, ticks);
  }

  OfflineUserAction enqueueManual(ServerMediaItemId identity,
          {required bool watched}) =>
      _set(
          identity,
          watched
              ? OfflineUserActionKind.watched
              : OfflineUserActionKind.unwatched,
          null);

  void completeSync(OfflineUserAction sent) {
    if (_pending[sent.identity]?.revision == sent.revision)
      _pending.remove(sent.identity);
  }

  OfflineUserAction _set(
      ServerMediaItemId identity, OfflineUserActionKind kind, int? ticks) {
    final next = OfflineUserAction(
        identity: identity,
        kind: kind,
        revision: ++_revision,
        positionTicks: ticks);
    _pending[identity] = next;
    return next;
  }
}

String _required(Object? value, String field) {
  if (value is! String || value.trim().isEmpty || value.trim() != value)
    throw FormatException('Invalid $field');
  return value;
}

int _nonnegative(Object? value) {
  if (value is! int || value < 0)
    throw const FormatException('Invalid nonnegative integer');
  return value;
}
