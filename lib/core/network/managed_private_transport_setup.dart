import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:rodplayer/core/network/family_enrollment.dart';
import 'package:rodplayer/core/network/private_network_runtime.dart';
import 'package:rodplayer/core/network/private_transport_profile.dart';
import 'package:rodplayer/core/network/private_transport_profile_association.dart';
import 'package:rodplayer/core/security/credential_migration.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef EnrollmentClientFactory = FamilyEnrollmentClient Function(Uri endpoint);

/// Shared by setup instances in this process; only a process restart clears it.
final class ManagedPrivateTransportTeardownGate {
  bool _unconfirmed = false;
}

class ManagedPrivateTransportPersistence {
  const ManagedPrivateTransportPersistence();

  Future<bool> setString(
          SharedPreferences preferences, String key, String value) =>
      preferences.setString(key, value);

  Future<bool> remove(SharedPreferences preferences, String key) =>
      preferences.remove(key);

  Future<void> saveProfile(
          SharedPreferences preferences, PrivateTransportProfile profile) =>
      PrivateTransportProfileStore(preferences).put(profile);

  Future<void> associate(
          SharedPreferences preferences, String serverUrl, String profileId) =>
      PrivateTransportProfileAssociation(preferences)
          .associate(serverUrl, profileId);
}

/// Enrolls one owner-supplied service; the native node owns its retained identity.
class ManagedPrivateTransportSetup {
  ManagedPrivateTransportSetup({
    required this.preferences,
    required this.runtimeFactory,
    required this.enrollmentClientFactory,
    this.persistence = const ManagedPrivateTransportPersistence(),
    ManagedPrivateTransportTeardownGate? teardownGate,
  }) : _teardownGate = teardownGate ?? _processTeardownGate;

  static final _processTeardownGate = ManagedPrivateTransportTeardownGate();

  final SharedPreferences preferences;
  final PrivateNetworkRuntime Function() runtimeFactory;
  final EnrollmentClientFactory enrollmentClientFactory;
  final ManagedPrivateTransportPersistence persistence;
  final ManagedPrivateTransportTeardownGate _teardownGate;

  Future<void> configure({
    required String canonicalServerUrl,
    required String invitationText,
    required String setupCode,
  }) async {
    if (_teardownGate._unconfirmed) {
      throw StateError('Private access setup unavailable until restart');
    }
    if (!PrivateTransportProfileAssociation.validCanonicalServerUrl(
        canonicalServerUrl)) {
      throw const FormatException('Invalid canonical server URL');
    }
    final invitation = PrivateTransportInvitation.parse(invitationText);
    if (preferences
        .containsKey(PrivateTransportProfileAssociation.pendingSetupKey)) {
      throw StateError('An unfinished private setup requires recovery');
    }
    final enrollmentClient =
        enrollmentClientFactory(invitation.enrollmentEndpoint);
    late final FamilyEnrollmentResult enrollment;
    try {
      enrollment = await enrollmentClient.enroll(setupCode);
    } finally {
      enrollmentClient.close();
    }

    final profile = invitation.profileFrom(enrollment);
    final runtime = runtimeFactory();
    final ready = Completer<PrivateNetworkStatus?>();
    PrivateNetworkStatus? latestStatus;
    var statusRevision = 0;
    var bootstrapped = false;
    var streamFailed = false;
    var finished = false;
    final subscription = runtime.statuses.listen(
      (status) {
        if (finished) return;
        latestStatus = status;
        statusRevision++;
        if (status.canProxy) {
          if (bootstrapped && !ready.isCompleted) ready.complete(status);
        } else if (bootstrapped && _terminal(status) && !ready.isCompleted) {
          ready.complete(null);
        }
      },
      onError: (Object _, StackTrace __) {
        if (finished) return;
        streamFailed = true;
        if (!ready.isCompleted) ready.complete(null);
      },
      onDone: () {
        if (finished) return;
        streamFailed = true;
        if (!ready.isCompleted) ready.complete(null);
      },
    );
    // A rejected bootstrap may refer to an already-owned native node. Do not
    // stop that unrelated lifecycle on an identity mismatch.
    late final PrivateNetworkStatus result;
    try {
      result = await runtime.bootstrap(invitation.bootstrapFrom(enrollment));
    } catch (_) {
      finished = true;
      try {
        await subscription.cancel();
      } catch (_) {
        _teardownGate._unconfirmed = true;
      }
      rethrow;
    }
    try {
      bootstrapped = true;
      final beforeStatusRead = statusRevision;
      final current = await runtime.status();
      final effective = beforeStatusRead == statusRevision
          ? current
          : latestStatus ?? current;
      if (!result.hasPersistedIdentity ||
          streamFailed ||
          (result.canProxy && !effective.canProxy) ||
          _terminal(effective)) {
        throw StateError('Private transport is not ready');
      }
      if (!effective.canProxy) {
        final observed = await ready.future
            .timeout(const Duration(seconds: 45), onTimeout: () => null);
        if (streamFailed ||
            observed?.canProxy != true ||
            latestStatus?.canProxy != true) {
          throw StateError('Private transport is not ready');
        }
      }
    } finally {
      // Stop preserves native identity. Never reset after a partial enrollment.
      finished = true;
      var cancellationFailed = false;
      try {
        await subscription.cancel();
      } catch (_) {
        _teardownGate._unconfirmed = true;
        cancellationFailed = true;
      }
      await runtime.stop();
      if (cancellationFailed) {
        throw StateError('Private transport listener did not close');
      }
    }

    const keys = [
      CredentialMigration.serverUrlKey,
      PrivateTransportProfileStore.preferenceKey,
      PrivateTransportProfileAssociation.preferenceKey,
    ];
    final before = {for (final key in keys) key: preferences.get(key)};
    const markerKey = PrivateTransportProfileAssociation.pendingSetupKey;
    final marker = PrivateTransportProfileAssociation.pendingSetupRecord(
        canonicalServerUrl, profile.id);
    if (!await persistence.setString(preferences, markerKey, marker) ||
        preferences.getString(markerKey) != marker) {
      throw StateError('Could not begin private transport setup');
    }
    try {
      if (!await persistence.setString(
          preferences, CredentialMigration.serverUrlKey, canonicalServerUrl)) {
        throw StateError('Could not save canonical server');
      }
      await persistence.saveProfile(preferences, profile);
      await persistence.associate(preferences, canonicalServerUrl, profile.id);
      if (!_stablePrivateStateMatches(canonicalServerUrl, profile)) {
        throw StateError('Could not verify private transport setup');
      }
    } catch (_) {
      var restored = true;
      for (final key in keys.reversed) {
        try {
          if (!await _restore(key, before[key]) ||
              !_sameRaw(preferences.get(key), before[key])) {
            restored = false;
          }
        } catch (_) {
          restored = false;
        }
      }
      if (restored) await _clearMarker(marker);
      rethrow;
    }
    if (!await _clearMarker(marker,
        canonicalServerUrl: canonicalServerUrl, profile: profile)) {
      throw StateError('Could not finish private transport setup');
    }
  }

  bool _terminal(PrivateNetworkStatus status) =>
      !status.canProxy &&
      !(status.hasPersistedIdentity &&
          (status.state == PrivateNetworkState.starting ||
              (status.state == PrivateNetworkState.unavailable &&
                  (status.unavailableReason ==
                          PrivateNetworkUnavailableReason
                              .directPathUnavailable ||
                      status.unavailableReason ==
                          PrivateNetworkUnavailableReason.transportFailure))));

  bool _stablePrivateStateMatches(
      String canonicalServerUrl, PrivateTransportProfile profile) {
    try {
      final saved = PrivateTransportProfileStore(preferences).find(profile.id);
      return preferences.getString(CredentialMigration.serverUrlKey) ==
              canonicalServerUrl &&
          saved != null &&
          jsonEncode(saved.toJson()) == jsonEncode(profile.toJson()) &&
          preferences.getString(
                  PrivateTransportProfileAssociation.preferenceKey) ==
              PrivateTransportProfileAssociation.associationRecord(
                  canonicalServerUrl, profile.id);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _clearMarker(String marker,
      {String? canonicalServerUrl, PrivateTransportProfile? profile}) async {
    const key = PrivateTransportProfileAssociation.pendingSetupKey;
    try {
      if (await persistence.remove(preferences, key) &&
          !preferences.containsKey(key)) {
        await preferences.reload();
        if (!preferences.containsKey(key)) return true;
      }
    } catch (_) {
      // Keep this transaction fail-closed when marker clearing fails.
    }
    try {
      await persistence.setString(preferences, key, marker);
    } catch (_) {
      // A verified private association may still be durable without it.
    }
    try {
      await preferences.reload();
    } catch (_) {
      return false;
    }
    if (!preferences.containsKey(key) &&
        !(canonicalServerUrl != null &&
            profile != null &&
            _stablePrivateStateMatches(canonicalServerUrl, profile))) {
      try {
        await persistence.setString(preferences, key, marker);
      } catch (_) {
        // A broken preference store cannot confirm a durable transaction.
      }
    }
    // A failed/ambiguous clear is never reported as setup success. If the
    // marker is absent, only the exact verified private association can route.
    return false;
  }

  bool _sameRaw(Object? actual, Object? expected) =>
      actual is List<String> && expected is List<String>
          ? listEquals(actual, expected)
          : actual == expected;

  Future<bool> _restore(String key, Object? value) async {
    if (value == null) {
      return persistence.remove(preferences, key);
    } else if (value is String) {
      return persistence.setString(preferences, key, value);
    } else if (value is bool) {
      return preferences.setBool(key, value);
    } else if (value is int) {
      return preferences.setInt(key, value);
    } else if (value is double) {
      return preferences.setDouble(key, value);
    } else if (value is List<String>) {
      return preferences.setStringList(key, value);
    }
    return false;
  }
}
