import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/downloads/download_job_store.dart';
import 'package:rodplayer/core/downloads/download_models.dart';
import 'package:rodplayer/core/models/server_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test(
    'offline assets with equal item IDs retain source-specific provenance',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final jobs = PreferencesDownloadJobStore(prefs);
      final owner = _job().owner;
      DownloadJob asset(String id, String source) => DownloadJob(
            id: id,
            owner: owner,
            itemId: 'item-1',
            mediaSourceId: source,
            state: DownloadJobState.completed,
            revision: 3,
            updatedAt: DateTime.utc(2026),
            fileReference: 'file-$id',
          );
      final a = asset('a', 'source-a');
      final b = asset('b', 'source-b');
      await jobs.save(a);
      await jobs.save(b);
      final files = _Files(quota: null)..existing.addAll(['file-a', 'file-b']);
      final resolver = OfflinePlaybackSourceResolver(jobs: jobs, files: files);
      expect(
        (await resolver.resolve(
          a,
        ) as OfflineAssetAvailable)
            .asset
            .mediaIdentity
            .mediaSourceId,
        'source-a',
      );
      expect(
        (await resolver.resolve(
          b,
        ) as OfflineAssetAvailable)
            .asset
            .mediaIdentity
            .mediaSourceId,
        'source-b',
      );
      final forged = DownloadJob(
        id: a.id,
        owner: owner,
        itemId: a.itemId,
        mediaSourceId: 'source-b',
        state: a.state,
        revision: a.revision,
        updatedAt: a.updatedAt,
        fileReference: a.fileReference,
      );
      expect(await resolver.resolve(forged), isA<OfflineAssetUnavailable>());
    },
  );

  test('download state machine rejects impossible transitions', () {
    final job = _job();
    expect(
      () => job.transition(
        DownloadJobState.completed,
        at: DateTime.utc(2026),
        fileReference: 'asset',
      ),
      throwsStateError,
    );
    final preparing = job.transition(
      DownloadJobState.preparing,
      at: DateTime.utc(2026),
    );
    final downloading = preparing.transition(
      DownloadJobState.downloading,
      at: DateTime.utc(2026),
      expectedBytes: 100,
    );
    final paused = downloading.transition(
      DownloadJobState.paused,
      at: DateTime.utc(2026),
      bytesReceived: 40,
    );
    expect(
      paused
          .transition(DownloadJobState.downloading, at: DateTime.utc(2026))
          .bytesReceived,
      40,
    );
    final completed = downloading.transition(
      DownloadJobState.completed,
      at: DateTime.utc(2026),
      bytesReceived: 100,
      fileReference: 'asset',
    );
    expect(completed.state, DownloadJobState.completed);
    expect(
      () => completed.transition(
        DownloadJobState.downloading,
        at: DateTime.utc(2026),
      ),
      throwsStateError,
    );
  });

  test(
    'one hundred pause/resume state transitions retain monotonic revision',
    () {
      var job = _job()
          .transition(DownloadJobState.preparing, at: DateTime.utc(2026))
          .transition(
            DownloadJobState.downloading,
            at: DateTime.utc(2026),
            expectedBytes: 1000,
          );
      for (var index = 0; index < 100; index++) {
        job = job
            .transition(DownloadJobState.paused, at: DateTime.utc(2026, 1, 2))
            .transition(
              DownloadJobState.downloading,
              at: DateTime.utc(2026, 1, 2),
            );
      }
      expect(job.state, DownloadJobState.downloading);
      expect(job.revision, 202);
      expect(job.bytesReceived, 0);
    },
  );

  test(
    'preferences job store survives reload without credential fields',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = PreferencesDownloadJobStore(prefs);
      await store.save(_job());
      final reloaded = await PreferencesDownloadJobStore(prefs).load();
      expect(reloaded.single.mediaIdentity, _job().mediaIdentity);
      expect(
        prefs.getString(PreferencesDownloadJobStore.preferenceKey),
        isNot(contains('token')),
      );
      expect(reloaded.single.toJson().keys, isNot(contains('accessToken')));
    },
  );

  test(
    'download enqueue is idempotent for the same account item and source',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = PreferencesDownloadJobStore(prefs);
      final first = _job();
      final duplicate = DownloadJob(
        id: 'job-duplicate',
        owner: first.owner,
        itemId: first.itemId,
        mediaSourceId: first.mediaSourceId,
        state: DownloadJobState.queued,
        revision: 0,
        updatedAt: DateTime.utc(2026, 2),
      );

      expect((await store.enqueueIfAbsent(first)).id, first.id);
      expect((await store.enqueueIfAbsent(duplicate)).id, first.id);
      expect((await store.load()).map((job) => job.id), <String>[first.id]);
    },
  );

  test(
    'job ID cannot be rebound to another source and job storage is bounded',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = PreferencesDownloadJobStore(prefs, maxJobs: 1);
      final original = _job();
      await store.enqueueIfAbsent(original);

      final changedSource = DownloadJob(
        id: original.id,
        owner: original.owner,
        itemId: original.itemId,
        mediaSourceId: 'different-source',
        state: DownloadJobState.queued,
        revision: original.revision + 1,
        updatedAt: DateTime.utc(2026, 1, 2),
      );
      await expectLater(store.save(changedSource), throwsStateError);
      await expectLater(
        store.enqueueIfAbsent(
          DownloadJob(
            id: 'job-2',
            owner: original.owner,
            itemId: 'another-item',
            mediaSourceId: original.mediaSourceId,
            state: DownloadJobState.queued,
            revision: 0,
            updatedAt: DateTime.utc(2026, 1, 2),
          ),
        ),
        throwsStateError,
      );
      expect((await store.load()).single.mediaSourceId, original.mediaSourceId);
    },
  );

  test('corrupt job metadata is preserved and reported', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PreferencesDownloadJobStore.preferenceKey, '{broken');
    await expectLater(
      PreferencesDownloadJobStore(prefs).load(),
      throwsA(isA<DownloadJobStoreCorruptException>()),
    );
    expect(
      prefs.getString(PreferencesDownloadJobStore.preferenceKey),
      '{broken',
    );
  });

  test(
    'managed storage reports quota before allocation and validates references',
    () async {
      final files = _Files(quota: 50);
      final manager = ManagedDownloadStorageManager(files);
      final rejected = await manager.allocate(jobId: 'job', expectedBytes: 51);
      expect(rejected.result, DownloadStorageResult.quotaExceeded);
      expect(files.allocations, 0);
      final accepted = await manager.allocate(jobId: 'job', expectedBytes: 50);
      expect(accepted.result, DownloadStorageResult.allocated);
      expect(files.allocations, 1);
      expect(() => ManagedFileReference('../escape'), throwsFormatException);
    },
  );

  test(
    'offline playback resolves only the exact owned, completed local asset',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final job = _job()
          .transition(DownloadJobState.preparing, at: DateTime.utc(2026))
          .transition(DownloadJobState.downloading, at: DateTime.utc(2026))
          .transition(
            DownloadJobState.completed,
            at: DateTime.utc(2026),
            fileReference: 'asset',
          );
      final store = PreferencesDownloadJobStore(prefs);
      await store.save(job);
      final files = _Files(quota: 100)..existing.add('asset');
      final resolved = await OfflinePlaybackSourceResolver(
        jobs: store,
        files: files,
      ).resolve(job);
      expect(resolved, isA<OfflineAssetAvailable>());
      expect(
        await OfflinePlaybackSourceResolver(
          jobs: store,
          files: files,
        ).resolve(_job()),
        isA<OfflineAssetUnavailable>(),
      );
    },
  );

  test(
      'durable outbox manual actions supersede stale progress and stale completion',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final outbox = PreferencesOfflineWatchActionOutbox(prefs);
    final identity = _job().mediaIdentity;
    final progress = await outbox.enqueueProgress(identity, 100);
    final manual = await outbox.enqueueManual(identity, watched: true);
    await outbox.completeSync(progress);
    expect(
      (await PreferencesOfflineWatchActionOutbox(prefs).load()).single.revision,
      manual.revision,
    );
    expect(
      (await outbox.enqueueProgress(identity, 120)).kind,
      OfflineUserActionKind.watched,
    );
    await outbox.completeSync(manual);
    expect(await outbox.load(), isEmpty);
  });

  test('outbox sync resolves the action owner and retries failures', () async {
    final prefs = await SharedPreferences.getInstance();
    final outbox = PreferencesOfflineWatchActionOutbox(prefs);
    final identity = _job().mediaIdentity;
    await outbox.enqueueManual(identity, watched: true);
    final resolver = _ExecutorResolver()..unavailable = true;
    final service = OfflineWatchActionSyncService(
      outbox: outbox,
      executors: resolver,
    );

    expect(
      await service.synchronizePending(),
      OfflineActionSyncResult.accountUnavailable,
    );
    expect((await outbox.load()).single.kind, OfflineUserActionKind.watched);

    resolver
      ..unavailable = false
      ..executor.fail = true;
    expect(await service.synchronizePending(), OfflineActionSyncResult.failed);
    expect((await outbox.load()).single.kind, OfflineUserActionKind.watched);

    resolver.executor.fail = false;
    expect(
      await service.synchronizePending(),
      OfflineActionSyncResult.complete,
    );
    expect(await outbox.load(), isEmpty);
    expect(resolver.requestedOwners, everyElement(identity.accountId));
    expect(resolver.requestedOwners, hasLength(3));
  });

  test(
    'offline action outbox rejects growth beyond its configured bound',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final outbox = PreferencesOfflineWatchActionOutbox(
        prefs,
        maxPendingActions: 1,
      );
      final first = _job().mediaIdentity;
      final second = ServerMediaItemId(
        accountId: first.accountId,
        itemId: 'item-2',
      );
      await outbox.enqueueManual(first, watched: true);
      await expectLater(
        outbox.enqueueManual(second, watched: false),
        throwsStateError,
      );
      expect((await outbox.load()).single.identity, first);
    },
  );

  test(
    'sync completion cannot erase a newer action enqueued in flight',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final outbox = PreferencesOfflineWatchActionOutbox(prefs);
      final identity = _job().mediaIdentity;
      final oldAction = await outbox.enqueueProgress(identity, 100);
      final executor = _Executor()..pending = Completer<void>();
      final service = OfflineWatchActionSyncService(
        outbox: outbox,
        executors: _ExecutorResolver()..executor = executor,
      );

      final syncing = service.synchronizePending();
      await Future<void>.delayed(Duration.zero);
      final newer = await outbox.enqueueManual(identity, watched: false);
      executor.pending!.complete();
      expect(await syncing, OfflineActionSyncResult.complete);

      final remaining = await outbox.load();
      expect(remaining, hasLength(1));
      expect(remaining.single.revision, greaterThan(oldAction.revision));
      expect(remaining.single.revision, newer.revision);
      expect(remaining.single.kind, OfflineUserActionKind.unwatched);
    },
  );

  test('concurrent outbox sync requests share one server operation', () async {
    final prefs = await SharedPreferences.getInstance();
    final outbox = PreferencesOfflineWatchActionOutbox(prefs);
    final identity = _job().mediaIdentity;
    await outbox.enqueueManual(identity, watched: true);
    final executor = _Executor()..pending = Completer<void>();
    final resolver = _ExecutorResolver()..executor = executor;
    final service = OfflineWatchActionSyncService(
      outbox: outbox,
      executors: resolver,
    );

    final first = service.synchronizePending();
    await Future<void>.delayed(Duration.zero);
    final second = service.synchronizePending();
    expect(identical(first, second), isTrue);
    expect(executor.applied, hasLength(1));
    executor.pending!.complete();
    expect(
      await Future.wait(<Future<OfflineActionSyncResult>>[first, second]),
      everyElement(OfflineActionSyncResult.complete),
    );
    expect(executor.applied, hasLength(1));
    expect(resolver.requestedOwners, <ServerAccountId>[identity.accountId]);
  });
}

DownloadJob _job() => DownloadJob(
      id: 'job-1',
      owner: ServerAccountId(serverId: ServerId('server-1'), userId: 'user-1'),
      itemId: 'item-1',
      mediaSourceId: 'source-1',
      state: DownloadJobState.queued,
      revision: 0,
      updatedAt: DateTime.utc(2026),
    );

final class _Files implements ManagedDownloadFileStore {
  _Files({required this.quota});
  int? quota;
  int allocations = 0;
  final Set<String> existing = <String>{};
  @override
  Future<int?> availableQuotaBytes() async => quota;
  @override
  Future<ManagedFileReference> allocate(String jobId) async {
    allocations++;
    return ManagedFileReference(jobId);
  }

  @override
  Future<void> delete(ManagedFileReference reference) async =>
      existing.remove(reference.value);
  @override
  Future<bool> exists(ManagedFileReference reference) async =>
      existing.contains(reference.value);
  @override
  Future<ManagedFileReference> finalize(ManagedFileReference temporary) async =>
      temporary;
  @override
  Future<int> size(ManagedFileReference reference) async => 0;
}

final class _ExecutorResolver implements OfflineUserActionExecutorResolver {
  final List<ServerAccountId> requestedOwners = <ServerAccountId>[];
  _Executor executor = _Executor();
  bool unavailable = false;

  @override
  Future<OfflineUserActionExecutor?> resolve(ServerAccountId owner) async {
    requestedOwners.add(owner);
    return unavailable ? null : executor;
  }
}

final class _Executor implements OfflineUserActionExecutor {
  bool fail = false;
  Completer<void>? pending;
  final List<OfflineUserAction> applied = <OfflineUserAction>[];

  @override
  Future<void> apply(OfflineUserAction action) async {
    if (fail) throw StateError('simulated server failure');
    applied.add(action);
    await pending?.future;
  }
}
