import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CompatibilityPanel has no fake 4K/HDR/Atmos defaults', () {
    final source = File('lib/ui/widgets/compatibility_panel.dart').readAsStringSync();
    expect(source, isNot(contains('4K UHD')));
    expect(source, isNot(contains('HDR10+')));
    expect(source, isNot(contains('Atmos / 7.1')));
  });
}
