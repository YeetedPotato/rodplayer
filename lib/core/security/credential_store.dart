import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class CredentialStore {
  Future<void> writeToken(String key, String token);
  Future<String?> readToken(String key);
  Future<void> deleteToken(String key);
}

class SecureCredentialStore implements CredentialStore {
  const SecureCredentialStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              mOptions: MacOsOptions(useDataProtectionKeyChain: false),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<void> writeToken(String key, String token) =>
      _storage.write(key: key, value: token);

  @override
  Future<String?> readToken(String key) => _storage.read(key: key);

  @override
  Future<void> deleteToken(String key) => _storage.delete(key: key);
}

class MemoryCredentialStore implements CredentialStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> writeToken(String key, String token) async {
    _values[key] = token;
  }

  @override
  Future<String?> readToken(String key) async => _values[key];

  @override
  Future<void> deleteToken(String key) async {
    _values.remove(key);
  }
}
