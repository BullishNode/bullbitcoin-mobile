import 'package:bb_mobile/features/get_paid/invoices/domain/invoice_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats invoice fiat minor units with server currency precision', () {
    expect(invoiceFiatMinorToMajorString(12345, 'USD'), '123.45');
    expect(invoiceFiatMinorToMajorString(12345, 'COP'), '12345');
  });

  test('returns invoice fiat minor unit factors with server precision', () {
    expect(invoiceMajorToMinorUnitFactor('USD'), 100);
    expect(invoiceMajorToMinorUnitFactor('COP'), 1);
  });
}
