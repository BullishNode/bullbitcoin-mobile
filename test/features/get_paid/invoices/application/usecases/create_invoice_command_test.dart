import 'package:bb_mobile/features/get_paid/invoices/application/invoices_application_error.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/create_invoice_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 5, 11, 12);

  test('accepts a valid sat-denominated command', () {
    expect(() => _command(now: now), returnsNormally);
  });

  test('rejects invalid linked nym', () {
    expect(
      () => _command(now: now, linkToPageNym: 'Alice'),
      throwsA(isA<InvoicesValidationError>()),
    );
  });

  test('rejects metadata over backend UTF-8 byte caps', () {
    expect(
      () => _command(now: now, publicDescription: 'a' * 1001),
      throwsA(isA<InvoicesValidationError>()),
    );
    expect(
      () => _command(now: now, recipientName: '😀' * 26),
      throwsA(isA<InvoicesValidationError>()),
    );
    expect(
      () => _command(now: now, invoiceNumber: '😀' * 13),
      throwsA(isA<InvoicesValidationError>()),
    );
  });

  test('rejects fiat amounts over backend minor-unit cap', () {
    expect(
      () => _command(
        now: now,
        amountSat: null,
        fiatAmountMinor: 1000000000,
        fiatCurrency: 'USD',
      ),
      returnsNormally,
    );
    expect(
      () => _command(
        now: now,
        amountSat: null,
        fiatAmountMinor: 1000000001,
        fiatCurrency: 'USD',
      ),
      throwsA(isA<InvoicesValidationError>()),
    );
  });
}

CreateInvoiceCommand _command({
  required DateTime now,
  int? amountSat = 1000,
  int? fiatAmountMinor,
  String? fiatCurrency,
  String? publicDescription = 'Coffee',
  String? recipientName = 'Alice',
  String? invoiceNumber = 'INV-1',
  String? linkToPageNym = 'alice',
}) {
  return CreateInvoiceCommand(
    amountSat: amountSat,
    fiatAmountMinor: fiatAmountMinor,
    fiatCurrency: fiatCurrency,
    publicDescription: publicDescription,
    recipientName: recipientName,
    invoiceNumber: invoiceNumber,
    acceptBtc: true,
    acceptLn: true,
    acceptLiquid: true,
    expiresAt: now.add(const Duration(hours: 1)),
    linkToPageNym: linkToPageNym,
    privateMemo: null,
    now: now,
  );
}
