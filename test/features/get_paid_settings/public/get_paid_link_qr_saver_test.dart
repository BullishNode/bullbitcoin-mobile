import 'package:bb_mobile/features/get_paid_settings/public/get_paid_link_qr_saver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saved when the system dialog returns a destination', () async {
    final outcome = await mapSaveDialogResult(
      () async => '/tmp/pos-terminal-qr.png',
    );
    expect(outcome, QrImageSaveOutcome.saved);
  });

  test('cancelled (neutral) when the user dismisses the dialog', () async {
    final outcome = await mapSaveDialogResult(() async => null);
    expect(outcome, QrImageSaveOutcome.cancelled);
  });

  test('failed when the write throws a recoverable exception', () async {
    final outcome = await mapSaveDialogResult(
      () async => throw Exception('io error'),
    );
    expect(outcome, QrImageSaveOutcome.failed);
  });

  test('does not convert programmer errors into save failures', () async {
    final future = mapSaveDialogResult(
      () async => throw StateError('broken save adapter'),
    );

    await expectLater(future, throwsA(isA<StateError>()));
  });
}
