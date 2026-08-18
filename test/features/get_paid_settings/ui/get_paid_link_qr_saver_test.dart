import 'package:bb_mobile/features/get_paid_settings/ui/get_paid_link_qr_saver.dart';
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

  test('failed when the write throws', () async {
    final outcome = await mapSaveDialogResult(
      () async => throw Exception('io error'),
    );
    expect(outcome, QrImageSaveOutcome.failed);
  });
}
