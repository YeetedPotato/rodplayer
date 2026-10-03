import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rodplayer/core/models/server_identity.dart';
import 'package:rodplayer/core/models/server_registry.dart';
import 'package:rodplayer/core/session/server_session.dart';

final class ActiveServerContext {
  ActiveServerContext({required this.generation, required this.session})
      : serverId = session.serverId,
        accountId = session.accountId {
    if (generation < 1) throw ArgumentError.value(generation, 'generation');
  }

  final ServerId serverId;
  final ServerAccountId accountId;
  final int generation;
  final ServerSession session;
}

enum ServerSwitchOutcome { activated, alreadyActive, superseded }

class ActivePlaybackPreventsServerSwitch implements Exception {
  const ActivePlaybackPreventsServerSwitch();

  @override
  String toString() => 'ActivePlaybackPreventsServerSwitch';
}

final class ActiveServerOperation<T> {
  const ActiveServerOperation.current(this.value)
      : isCurrent = true,
        generation = null;
  const ActiveServerOperation.stale(this.generation)
      : value = null,
        isCurrent = false;

  final T? value;
  final bool isCurrent;
  final int? generation;
}

/// Owns one active account/session at a time. Switches are serialized so the
/// last requested transition cannot publish partially over an earlier one.
/// PrivateNetworkRuntime is intentionally not a dependency of this controller.
final class ActiveServerController {
  ActiveServerController({
    required this.sessions,
    required this.persistActiveServer,
    required this.hasActivePlayback,
    ActiveServerContext? initial,
  }) : current = ValueNotifier<ActiveServerContext?>(initial) {
    if (initial != null) _generation = initial.generation;
  }

  final ServerSessionFactory sessions;
  final Future<void> Function(ServerRecord, ServerAccountId, String)
      persistActiveServer;
  final bool Function() hasActivePlayback;
  final ValueNotifier<ActiveServerContext?> current;

  Future<void> _queue = Future<void>.value();
  int _generation = 0;
  bool _disposed = false;
  bool _lastPreviousSessionCleanupFailed = false;

  bool get lastPreviousSessionCleanupFailed =>
      _lastPreviousSessionCleanupFailed;

  ActiveServerContext? get active => current.value;

  Future<ServerSwitchOutcome> switchTo(
    ServerRecord server,
    ServerUserAccount account,
  ) {
    if (_disposed)
      return Future<ServerSwitchOutcome>.error(
          StateError('Active server controller is disposed'));
    if (account.identity.serverId != server.id ||
        !server.accounts
            .any((candidate) => candidate.identity == account.identity)) {
      return Future<ServerSwitchOutcome>.error(
        StateError('Account is not associated with the selected server'),
      );
    }
    final result = Completer<ServerSwitchOutcome>();
    _queue = _queue.then((_) async {
      try {
        result.complete(await _switchNow(server, account));
      } on Object catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<ServerSwitchOutcome> _switchNow(
    ServerRecord server,
    ServerUserAccount account,
  ) async {
    if (_disposed) throw StateError('Active server controller is disposed');
    final existing = active;
    if (existing != null &&
        existing.serverId == server.id &&
        existing.accountId == account.identity &&
        !existing.session.isClosed) {
      return ServerSwitchOutcome.alreadyActive;
    }
    if (hasActivePlayback()) throw const ActivePlaybackPreventsServerSwitch();

    final candidateGeneration = _generation + 1;
    final candidate = await sessions.open(
      server,
      account,
      isCurrent: () =>
          !_disposed && current.value?.generation == candidateGeneration,
    );
    if (_disposed) {
      await candidate.close();
      throw StateError('Active server controller is disposed');
    }
    if (candidate.serverId != server.id ||
        candidate.accountId != account.identity) {
      await candidate.close();
      throw StateError('Opened session identity did not match request');
    }
    if (candidate.verifiedSystemId == null ||
        (server.verifiedSystemId != null &&
            candidate.verifiedSystemId != server.verifiedSystemId)) {
      await candidate.close();
      throw StateError('Verified server identity did not match registry');
    }

    try {
      await persistActiveServer(
          server, account.identity, candidate.verifiedSystemId!);
    } on Object {
      await candidate.close();
      rethrow;
    }
    if (_disposed) {
      await candidate.close();
      throw StateError('Active server controller is disposed');
    }

    final previous = active;
    final next = ActiveServerContext(
      generation: candidateGeneration,
      session: candidate,
    );
    _generation = candidateGeneration;
    current.value = next;
    _lastPreviousSessionCleanupFailed = false;
    if (previous != null) {
      try {
        await previous.session.close();
      } on Object {
        // The candidate is already active and durable; old-session cleanup
        // failure must not misreport the committed switch as a failed switch.
        _lastPreviousSessionCleanupFailed = true;
      }
    }
    return ServerSwitchOutcome.activated;
  }

  /// Restores exactly the persisted active server/account. It never guesses a
  /// different server if the selected one cannot initialize.
  Future<bool> restore(ServerRegistrySnapshot snapshot) {
    if (_disposed) {
      return Future<bool>.error(
          StateError('Active server controller is disposed'));
    }
    final result = Completer<bool>();
    _queue = _queue.then((_) async {
      try {
        result.complete(await _restoreNow(snapshot));
      } on Object catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<bool> _restoreNow(ServerRegistrySnapshot snapshot) async {
    if (_disposed) throw StateError('Active server controller is disposed');
    if (active != null) throw StateError('An active server is already set');
    final serverId = snapshot.activeServerId;
    final accountId = snapshot.activeAccountId;
    if (serverId == null || accountId == null) return false;
    final server = snapshot.server(serverId);
    if (server == null) throw StateError('Persisted active server is missing');
    ServerUserAccount? account;
    for (final candidate in server.accounts) {
      if (candidate.identity == accountId) {
        account = candidate;
        break;
      }
    }
    if (account == null) {
      throw StateError('Persisted active account is missing');
    }
    final sessionGeneration = _generation + 1;
    final session = await sessions.open(
      server,
      account,
      isCurrent: () =>
          !_disposed && current.value?.generation == sessionGeneration,
    );
    if (_disposed ||
        session.serverId != serverId ||
        session.accountId != accountId ||
        session.verifiedSystemId == null ||
        (server.verifiedSystemId != null &&
            server.verifiedSystemId != session.verifiedSystemId)) {
      await session.close();
      if (_disposed) return false;
      throw StateError('Restored session identity did not match registry');
    }
    try {
      await persistActiveServer(
        server,
        accountId,
        session.verifiedSystemId!,
      );
    } on Object {
      await session.close();
      rethrow;
    }
    if (_disposed || session.isClosed) {
      await session.close();
      return false;
    }
    current.value = ActiveServerContext(
      generation: sessionGeneration,
      session: session,
    );
    _generation = sessionGeneration;
    return true;
  }

  bool isCurrent(ActiveServerContext context) =>
      !_disposed && identical(active, context) && !context.session.isClosed;

  /// Runs an operation against one captured generation and labels its result
  /// stale if a switch completed before the operation returned.
  Future<ActiveServerOperation<T>> run<T>(
    Future<T> Function(ActiveServerContext context) operation,
  ) async {
    final captured = active;
    if (captured == null || !isCurrent(captured)) {
      return ActiveServerOperation<T>.stale(null);
    }
    final value = await operation(captured);
    if (!isCurrent(captured)) {
      return ActiveServerOperation<T>.stale(captured.generation);
    }
    return ActiveServerOperation<T>.current(value);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _queue;
    final previous = active;
    current.value = null;
    try {
      if (previous != null) await previous.session.close();
    } finally {
      current.dispose();
    }
  }
}

/// Compatibility bridge for existing single-client screens. It exposes only
/// the currently active session and can attach provenance without making
/// widgets aware of registry or switching internals.
final class ActiveServerClientAdapter {
  const ActiveServerClientAdapter(this.controller);

  final ActiveServerController controller;

  ServerSession? get session => controller.active?.session;
  ServerId? get serverId => controller.active?.serverId;
  ServerAccountId? get accountId => controller.active?.accountId;
  int? get generation => controller.active?.generation;

  ServerMediaItemId itemIdentity(String itemId) {
    final context = controller.active;
    if (context == null) throw StateError('No active server session');
    return ServerMediaItemId(accountId: context.accountId, itemId: itemId);
  }
}
