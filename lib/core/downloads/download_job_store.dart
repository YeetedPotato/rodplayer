import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:rodplayer/core/models/server_identity.dart';

import 'download_models.dart';

abstract interface class DownloadJobStore {
  Future<List<DownloadJob>> load();
  Future<DownloadJob> enqueueIfAbsent(DownloadJob job);
  Future<void> save(DownloadJob job);
  Future<void> remove(String jobId);
}

/// Durable versioned metadata snapshot. It stores only job metadata and
/// opaque managed-file references; credentials and media bytes are excluded.
final class PreferencesDownloadJobStore implements DownloadJobStore {
  PreferencesDownloadJobStore(this.preferences, {this.maxJobs = 512}) {
    if (maxJobs < 1 || maxJobs > maximumSupportedJobs) {
      throw ArgumentError.value(maxJobs, 'maxJobs');
    }
  }
  static const preferenceKey = 'nautilus_download_jobs_v1';
  static const maximumSupportedJobs = 10000;
  final SharedPreferences preferences;
  final int maxJobs;
  Future<void> _writes = Future<void>.value();

  @override
  Future<List<DownloadJob>> load() async {
    await _writes;
    return _decode(preferences.getString(preferenceKey));
  }

  List<DownloadJob> _decode(String? raw) {
    if (raw == null) return const <DownloadJob>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map ||
          decoded['version'] != 1 ||
          decoded['jobs'] is! List ||
          (decoded['jobs'] as List).length > maxJobs) {
        throw const FormatException();
      }
      return List<DownloadJob>.unmodifiable(
        (decoded['jobs'] as List).map(
          (value) =>
              DownloadJob.fromJson(Map<String, Object?>.from(value as Map)),
        ),
      );
    } on Object {
      // Leave corrupt bytes intact; never silently erase user download state.
      throw const DownloadJobStoreCorruptException();
    }
  }

  @override
  Future<DownloadJob> enqueueIfAbsent(DownloadJob job) => _update((jobs) {
    final sameId = jobs[job.id];
    if (sameId != null && !_sameDownloadIdentity(sameId, job)) {
      throw StateError('Download job ID belongs to another source');
    }
    for (final existing in jobs.values) {
      if (existing.owner == job.owner &&
          existing.itemId == job.itemId &&
          existing.mediaSourceId == job.mediaSourceId &&
          existing.state != DownloadJobState.cancelled &&
          existing.state != DownloadJobState.removing) {
        return existing;
      }
    }
    if (sameId == null && jobs.length >= maxJobs) {
      throw StateError('Download job limit reached');
    }
    jobs[job.id] = job;
    return job;
  });

  @override
  Future<void> save(DownloadJob job) => _update((jobs) {
    final existing = jobs[job.id];
    if (existing != null) {
      if (!_sameDownloadIdentity(existing, job)) {
        throw StateError('Download job identity cannot change');
      }
      if (job.revision < existing.revision) {
        throw StateError('Stale download job revision');
      }
    } else if (jobs.length >= maxJobs) {
      throw StateError('Download job limit reached');
    }
    jobs[job.id] = job;
  });

  @override
  Future<void> remove(String jobId) => _update((jobs) {
    final job = jobs[jobId];
    if (job != null && job.state != DownloadJobState.removing) {
      throw StateError(
        'Download must enter removing state before metadata deletion',
      );
    }
    jobs.remove(jobId);
  });

  Future<T> _update<T>(T Function(Map<String, DownloadJob>) mutate) {
    final done = Completer<T>();
    _writes = _writes.then((_) async {
      final oldRaw = preferences.getString(preferenceKey);
      try {
        final jobs = <String, DownloadJob>{
          for (final job in _decode(oldRaw)) job.id: job,
        };
        final result = mutate(jobs);
        final encoded = jsonEncode(<String, Object?>{
          'version': 1,
          'jobs': jobs.values
              .map((job) => job.toJson())
              .toList(growable: false),
        });
        if (!await preferences.setString(preferenceKey, encoded) ||
            preferences.getString(preferenceKey) != encoded) {
          throw StateError('Download job metadata write verification failed');
        }
        done.complete(result);
      } on Object catch (error, stack) {
        try {
          if (oldRaw == null) {
            await preferences.remove(preferenceKey);
          } else {
            await preferences.setString(preferenceKey, oldRaw);
          }
        } on Object {
          // The original storage failure remains authoritative.
        }
        done.completeError(error, stack);
      }
    });
    return done.future;
  }
}

bool _sameDownloadIdentity(DownloadJob first, DownloadJob second) =>
    first.owner == second.owner &&
    first.itemId == second.itemId &&
    first.mediaSourceId == second.mediaSourceId;

final class DownloadJobStoreCorruptException implements Exception {
  const DownloadJobStoreCorruptException();
}

/// Durable per-item outbox. The preference record contains only scoped item
/// identity, action, position, and revision; no credentials or URLs.
final class PreferencesOfflineWatchActionOutbox {
  PreferencesOfflineWatchActionOutbox(
    this.preferences, {
    this.maxPendingActions = 10000,
  }) {
    if (maxPendingActions < 1 || maxPendingActions > 100000) {
      throw ArgumentError.value(maxPendingActions, 'maxPendingActions');
    }
  }
  static const preferenceKey = 'nautilus_offline_watch_outbox_v1';
  final SharedPreferences preferences;
  final int maxPendingActions;
  Future<void> _writes = Future<void>.value();
  int _revision = 0;

  Future<List<OfflineUserAction>> load() async {
    await _writes;
    return _decodeActions(preferences.getString(preferenceKey));
  }

  List<OfflineUserAction> _decodeActions(String? raw) {
    if (raw == null) return const <OfflineUserAction>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map ||
          decoded['version'] != 1 ||
          decoded['actions'] is! List ||
          (decoded['actions'] as List).length > maxPendingActions) {
        throw const FormatException();
      }
      final values = (decoded['actions'] as List)
          .map((value) {
            final json = Map<String, Object?>.from(value as Map);
            final action = OfflineUserAction(
              identity: ServerMediaItemId(
                accountId: ServerAccountId.fromJson(
                  Map<String, Object?>.from(json['account']! as Map),
                ),
                itemId: json['itemId']! as String,
              ),
              kind: OfflineUserActionKind.values.firstWhere(
                (kind) => kind.name == json['kind'],
              ),
              revision: json['revision']! as int,
              positionTicks: json['positionTicks'] as int?,
            );
            if (action.revision < 0 || (action.positionTicks ?? 0) < 0)
              throw const FormatException();
            if (action.revision > _revision) _revision = action.revision;
            return action;
          })
          .toList(growable: false);
      return List<OfflineUserAction>.unmodifiable(values);
    } on Object {
      throw const DownloadJobStoreCorruptException();
    }
  }

  Future<OfflineUserAction> enqueueProgress(
    ServerMediaItemId identity,
    int ticks,
  ) async {
    if (ticks < 0) throw ArgumentError.value(ticks, 'ticks');
    return _mutate((actions) {
      final current = actions[identity];
      if (current?.kind == OfflineUserActionKind.watched ||
          current?.kind == OfflineUserActionKind.unwatched)
        return current!;
      return _replace(actions, identity, OfflineUserActionKind.progress, ticks);
    });
  }

  Future<OfflineUserAction> enqueueManual(
    ServerMediaItemId identity, {
    required bool watched,
  }) => _mutate(
    (actions) => _replace(
      actions,
      identity,
      watched ? OfflineUserActionKind.watched : OfflineUserActionKind.unwatched,
      null,
    ),
  );

  Future<void> completeSync(OfflineUserAction sent) async {
    await _mutate<void>((actions) {
      if (actions[sent.identity]?.revision == sent.revision)
        actions.remove(sent.identity);
    });
  }

  OfflineUserAction _replace(
    Map<ServerMediaItemId, OfflineUserAction> actions,
    ServerMediaItemId identity,
    OfflineUserActionKind kind,
    int? ticks,
  ) {
    if (!actions.containsKey(identity) && actions.length >= maxPendingActions) {
      throw StateError('Offline action outbox limit reached');
    }
    final value = OfflineUserAction(
      identity: identity,
      kind: kind,
      revision: ++_revision,
      positionTicks: ticks,
    );
    actions[identity] = value;
    return value;
  }

  Future<T> _mutate<T>(
    T Function(Map<ServerMediaItemId, OfflineUserAction>) action,
  ) {
    final result = Completer<T>();
    _writes = _writes.then((_) async {
      final oldRaw = preferences.getString(preferenceKey);
      try {
        final actions = <ServerMediaItemId, OfflineUserAction>{
          for (final item in _decodeActions(oldRaw)) item.identity: item,
        };
        final value = action(actions);
        final encoded = jsonEncode(<String, Object?>{
          'version': 1,
          'actions': actions.values
              .map(
                (entry) => <String, Object?>{
                  'account': entry.identity.accountId.toJson(),
                  'itemId': entry.identity.itemId,
                  'kind': entry.kind.name,
                  'revision': entry.revision,
                  if (entry.positionTicks != null)
                    'positionTicks': entry.positionTicks,
                },
              )
              .toList(growable: false),
        });
        if (!await preferences.setString(preferenceKey, encoded) ||
            preferences.getString(preferenceKey) != encoded) {
          throw StateError('Offline outbox write verification failed');
        }
        result.complete(value);
      } on Object catch (error, stack) {
        try {
          if (oldRaw == null) {
            await preferences.remove(preferenceKey);
          } else {
            await preferences.setString(preferenceKey, oldRaw);
          }
        } on Object {}
        result.completeError(error, stack);
      }
    });
    return result.future;
  }
}

enum OfflineActionSyncResult { complete, accountUnavailable, failed }

/// Account-scoped executor resolves an authenticated server session from the
/// action's owner. Implementations must keep credentials in secure storage and
/// use that session's ServiceTransport; the outbox never selects the active
/// account implicitly.
abstract interface class OfflineUserActionExecutor {
  Future<void> apply(OfflineUserAction action);
}

abstract interface class OfflineUserActionExecutorResolver {
  Future<OfflineUserActionExecutor?> resolve(ServerAccountId owner);
}

/// Bounded, sequential synchronization of durable offline actions. Failed
/// actions remain pending for a later retry. Completing an old snapshot cannot
/// remove a newer local action because the outbox checks its revision.
final class OfflineWatchActionSyncService {
  OfflineWatchActionSyncService({
    required this.outbox,
    required this.executors,
    this.maxActionsPerRun = 32,
  }) {
    if (maxActionsPerRun < 1) {
      throw ArgumentError.value(maxActionsPerRun, 'maxActionsPerRun');
    }
  }

  final PreferencesOfflineWatchActionOutbox outbox;
  final OfflineUserActionExecutorResolver executors;
  final int maxActionsPerRun;
  Future<OfflineActionSyncResult>? _syncing;

  Future<OfflineActionSyncResult> synchronizePending() {
    final active = _syncing;
    if (active != null) return active;
    late final Future<OfflineActionSyncResult> operation;
    operation = _synchronizePending().whenComplete(() {
      if (identical(_syncing, operation)) _syncing = null;
    });
    _syncing = operation;
    return operation;
  }

  Future<OfflineActionSyncResult> _synchronizePending() async {
    final List<OfflineUserAction> pending;
    try {
      pending = await outbox.load();
    } on Object {
      return OfflineActionSyncResult.failed;
    }
    final limit = pending.length < maxActionsPerRun
        ? pending.length
        : maxActionsPerRun;
    for (final action in pending.take(limit)) {
      final OfflineUserActionExecutor? executor;
      try {
        executor = await executors.resolve(action.identity.accountId);
      } on Object {
        return OfflineActionSyncResult.failed;
      }
      if (executor == null) return OfflineActionSyncResult.accountUnavailable;
      try {
        await executor.apply(action);
      } on Object {
        return OfflineActionSyncResult.failed;
      }
      try {
        await outbox.completeSync(action);
      } on Object {
        return OfflineActionSyncResult.failed;
      }
    }
    return OfflineActionSyncResult.complete;
  }
}

/// Durable per-item outbox. The preference record contains only scoped item
/// identity, action, position, and revision; no credentials or URLs.
final class ManagedFileReference {
  ManagedFileReference(String value) : value = _validate(value);
  final String value;
  static String _validate(String value) {
    if (value.isEmpty ||
        value.contains('..') ||
        value.contains('/') ||
        value.contains('\\')) {
      throw FormatException('Invalid managed file reference');
    }
    return value;
  }
}

abstract interface class ManagedDownloadFileStore {
  Future<ManagedFileReference> allocate(String jobId);
  Future<ManagedFileReference> finalize(ManagedFileReference temporary);
  Future<void> delete(ManagedFileReference reference);
  Future<bool> exists(ManagedFileReference reference);
  Future<int> size(ManagedFileReference reference);
  Future<int?> availableQuotaBytes();
}

enum DownloadStorageResult { allocated, quotaExceeded }

final class ManagedDownloadStorageManager {
  const ManagedDownloadStorageManager(this.files);
  final ManagedDownloadFileStore files;

  Future<({DownloadStorageResult result, ManagedFileReference? reference})>
  allocate({required String jobId, required int expectedBytes}) async {
    final quota = await files.availableQuotaBytes();
    if (expectedBytes < 0 || (quota != null && expectedBytes > quota)) {
      return (result: DownloadStorageResult.quotaExceeded, reference: null);
    }
    return (
      result: DownloadStorageResult.allocated,
      reference: await files.allocate(jobId),
    );
  }
}

final class OfflinePlaybackAsset {
  const OfflinePlaybackAsset({
    required this.mediaIdentity,
    required this.reference,
  });
  final DownloadJob mediaIdentity;
  final ManagedFileReference reference;
}

sealed class OfflinePlaybackResolution {
  const OfflinePlaybackResolution();
}

final class OfflineAssetAvailable extends OfflinePlaybackResolution {
  const OfflineAssetAvailable(this.asset);
  final OfflinePlaybackAsset asset;
}

final class OfflineAssetUnavailable extends OfflinePlaybackResolution {
  const OfflineAssetUnavailable();
}

/// Resolves solely to a verified managed local asset. It never constructs a
/// server URL or falls back to an arbitrary network path.
final class OfflinePlaybackSourceResolver {
  const OfflinePlaybackSourceResolver({
    required this.jobs,
    required this.files,
  });
  final DownloadJobStore jobs;
  final ManagedDownloadFileStore files;

  Future<OfflinePlaybackResolution> resolve(DownloadJob target) async {
    if (target.state != DownloadJobState.completed ||
        target.fileReference == null)
      return const OfflineAssetUnavailable();
    final jobs = await this.jobs.load();
    DownloadJob? match;
    for (final job in jobs) {
      if (job.id == target.id &&
          job.revision == target.revision &&
          job.mediaIdentity == target.mediaIdentity &&
          job.mediaSourceId == target.mediaSourceId &&
          job.state == DownloadJobState.completed &&
          job.fileReference == target.fileReference) {
        match = job;
        break;
      }
    }
    if (match == null) return const OfflineAssetUnavailable();
    try {
      final ref = ManagedFileReference(target.fileReference!);
      if (!await files.exists(ref)) return const OfflineAssetUnavailable();
      return OfflineAssetAvailable(
        OfflinePlaybackAsset(mediaIdentity: target, reference: ref),
      );
    } on FormatException {
      return const OfflineAssetUnavailable();
    }
  }
}
