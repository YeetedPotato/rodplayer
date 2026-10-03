import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'companion_remote_protocol.dart';

abstract interface class RemoteDeviceStore {
  Future<List<PairedRemoteDevice>> load();
  Future<void> save(PairedRemoteDevice device);
}

/// Local approval/revocation lifecycle. This records metadata only; it does
/// not create a pairing secret or enable a network transport.
final class CompanionPairingCoordinator {
  CompanionPairingCoordinator({required this.store});

  final RemoteDeviceStore store;
  Future<void> _operations = Future<void>.value();

  Future<PairedRemoteDevice> request({
    required RemoteDeviceId id,
    required String label,
    required DateTime at,
    DateTime? expiresAt,
  }) =>
      _serialize(() async {
        final normalizedLabel = label.trim();
        if (normalizedLabel.isEmpty || normalizedLabel.length > 80) {
          throw ArgumentError.value(label, 'label');
        }
        if (expiresAt != null && !expiresAt.isAfter(at)) {
          throw ArgumentError.value(expiresAt, 'expiresAt');
        }
        final existing = await _find(id);
        if (existing?.status == RemoteDeviceStatus.paired &&
            existing!.isAuthorizedAt(at)) {
          throw StateError('An authorized remote device is already paired');
        }
        final pending = PairedRemoteDevice(
          id: id,
          label: normalizedLabel,
          status: RemoteDeviceStatus.pairing,
          pairedAt: at,
          expiresAt: expiresAt,
        );
        await store.save(pending);
        return pending;
      });

  Future<PairedRemoteDevice> approve(
    RemoteDeviceId id, {
    required DateTime at,
  }) =>
      _serialize(() async {
        final device = await _find(id);
        if (device == null) throw StateError('Pairing request does not exist');
        final approved = device.approve(at: at);
        await store.save(approved);
        return approved;
      });

  Future<PairedRemoteDevice> revoke(
    RemoteDeviceId id, {
    required DateTime at,
  }) =>
      _serialize(() async {
        final device = await _find(id);
        if (device == null) throw StateError('Remote device does not exist');
        if (device.status == RemoteDeviceStatus.revoked) return device;
        final revoked = device.revoke(at);
        await store.save(revoked);
        return revoked;
      });

  Future<int> expire(DateTime at) => _serialize(() async {
        final devices = await store.load();
        var expired = 0;
        for (final device in devices) {
          final expiry = device.expiresAt;
          if (expiry == null ||
              at.isBefore(expiry) ||
              (device.status != RemoteDeviceStatus.pairing &&
                  device.status != RemoteDeviceStatus.paired)) {
            continue;
          }
          await store.save(device.expire());
          expired++;
        }
        return expired;
      });

  Future<PairedRemoteDevice?> _find(RemoteDeviceId id) async {
    for (final device in await store.load()) {
      if (device.id == id) return device;
    }
    return null;
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _operations = _operations.then((_) async {
      try {
        result.complete(await operation());
      } on Object catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }
}

/// Stores only user-approved nonsecret peer metadata. Pairing keys and
/// transport credentials are deliberately not representable here.
final class PreferencesRemoteDeviceStore implements RemoteDeviceStore {
  PreferencesRemoteDeviceStore(this.preferences);
  static const preferenceKey = 'nautilus_remote_devices_v1';
  final SharedPreferences preferences;
  Future<void> _writes = Future<void>.value();

  @override
  Future<List<PairedRemoteDevice>> load() async {
    await _writes;
    return _decode(preferences.getString(preferenceKey));
  }

  List<PairedRemoteDevice> _decode(String? raw) {
    if (raw == null) return const <PairedRemoteDevice>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map ||
          decoded['version'] != 1 ||
          decoded['devices'] is! List ||
          (decoded['devices'] as List).length > 32) {
        throw const FormatException();
      }
      return List<PairedRemoteDevice>.unmodifiable(
        (decoded['devices'] as List)
            .map((item) => _fromJson(Map<String, Object?>.from(item as Map))),
      );
    } on Object {
      throw const RemoteDeviceStoreCorruptException();
    }
  }

  @override
  Future<void> save(PairedRemoteDevice device) {
    final done = Completer<void>();
    _writes = _writes.then((_) async {
      final oldRaw = preferences.getString(preferenceKey);
      try {
        final devices = <String, PairedRemoteDevice>{
          for (final value in _decode(oldRaw)) value.id.value: value,
        };
        devices[device.id.value] = device;
        if (devices.length > 32)
          throw StateError('Remote device limit reached');
        final encoded = jsonEncode(<String, Object?>{
          'version': 1,
          'devices': devices.values.map(_toJson).toList(growable: false),
        });
        if (!await preferences.setString(preferenceKey, encoded) ||
            preferences.getString(preferenceKey) != encoded) {
          throw StateError('Remote device metadata write verification failed');
        }
        done.complete();
      } on Object catch (error, stack) {
        try {
          if (oldRaw == null) {
            await preferences.remove(preferenceKey);
          } else {
            await preferences.setString(preferenceKey, oldRaw);
          }
        } on Object {}
        done.completeError(error, stack);
      }
    });
    return done.future;
  }

  Map<String, Object?> _toJson(PairedRemoteDevice device) => <String, Object?>{
        'id': device.id.value,
        'label': device.label,
        'status': device.status.name,
        'pairedAt': device.pairedAt.toUtc().toIso8601String(),
        if (device.expiresAt != null)
          'expiresAt': device.expiresAt!.toUtc().toIso8601String(),
        if (device.revokedAt != null)
          'revokedAt': device.revokedAt!.toUtc().toIso8601String(),
      };

  PairedRemoteDevice _fromJson(Map<String, Object?> json) {
    final statusName = json['status'];
    final status = RemoteDeviceStatus.values
        .where((item) => item.name == statusName)
        .toList(growable: false);
    if (status.length != 1)
      throw const FormatException('Invalid remote device status');
    final label = json['label'];
    if (label is! String || label.trim().isEmpty || label.length > 80)
      throw const FormatException('Invalid remote device label');
    return PairedRemoteDevice(
      id: RemoteDeviceId(json['id']! as String),
      label: label,
      status: status.single,
      pairedAt: DateTime.parse(json['pairedAt']! as String),
      expiresAt: json['expiresAt'] is String
          ? DateTime.parse(json['expiresAt']! as String)
          : null,
      revokedAt: json['revokedAt'] is String
          ? DateTime.parse(json['revokedAt']! as String)
          : null,
    );
  }
}

final class RemoteDeviceStoreCorruptException implements Exception {
  const RemoteDeviceStoreCorruptException();
}
