import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts wallet backup only from the foreground initialization path', () {
    final locatorSource = File('lib/locator.dart').readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();
    final backgroundSource = File(
      'lib/core/background_tasks/handler.dart',
    ).readAsStringSync();
    final starts = RegExp(
      r'WalletBackupLocator\.start\(locator\)',
    ).allMatches(locatorSource);
    final foregroundMethod = locatorSource.indexOf(
      'static void startForeground(GetIt locator)',
    );

    expect(starts, hasLength(1));
    expect(foregroundMethod, greaterThanOrEqualTo(0));
    expect(starts.single.start, greaterThan(foregroundMethod));
    expect(mainSource, contains('AppLocator.startForeground(locator);'));
    expect(
      backgroundSource,
      isNot(contains('AppLocator.startForeground(locator);')),
    );
  });
}
