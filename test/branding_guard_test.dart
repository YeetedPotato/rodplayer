import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public source does not expose Remux product branding', () {
    final allowed = <String>{'lib/core/security/credential_migration.dart', 'lib/core/device/installation_identity.dart'};
    final files = Directory('lib').listSync(recursive: true).whereType<File>().where((file) => file.path.endsWith('.dart'));
    for (final file in files) {
      final relative = file.path.replaceFirst('./', '');
      if (allowed.contains(relative)) continue;
      expect(file.readAsStringSync().toLowerCase(), isNot(contains('remux')), reason: relative);
    }
  });
}
