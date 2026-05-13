import 'package:bb_mobile/features/get_paid/invoices/domain/entities/invoice.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/primitives/invoice_status.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/value_objects/invoice_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 5, 11, 12);

  test('isPayable is true only for active payable states before expiry', () {
    expect(_invoice(status: InvoiceStatus.unpaid).isPayable(now), isTrue);
    expect(_invoice(status: InvoiceStatus.inProgress).isPayable(now), isTrue);
    expect(_invoice(status: InvoiceStatus.paid).isPayable(now), isFalse);
    expect(
      _invoice(status: InvoiceStatus.unpaid, expiresAt: now).isPayable(now),
      isFalse,
    );
  });

  test('isCancellable is true only for unpaid invoices', () {
    expect(_invoice(status: InvoiceStatus.unpaid).isCancellable, isTrue);
    expect(_invoice(status: InvoiceStatus.inProgress).isCancellable, isFalse);
    expect(_invoice(status: InvoiceStatus.expired).isCancellable, isFalse);
    expect(_invoice(status: InvoiceStatus.cancelled).isCancellable, isFalse);
  });

  test('timeUntilExpiry clamps expired invoices to zero', () {
    expect(
      _invoice(
        expiresAt: now.add(const Duration(minutes: 5)),
      ).timeUntilExpiry(now),
      const Duration(minutes: 5),
    );
    expect(
      _invoice(
        expiresAt: now.subtract(const Duration(seconds: 1)),
      ).timeUntilExpiry(now),
      Duration.zero,
    );
  });

  test('publicUrlFor builds linked and unlinked invoice URLs', () {
    final id = InvoiceId('00000000-0000-0000-0000-000000000001');

    expect(
      _invoice(nymOwner: 'alice').publicUrlFor(domain: 'bullpay.ca').value,
      invoicePublicUrlFor(nym: 'alice', id: id, domain: 'bullpay.ca').value,
    );
    expect(
      _invoice(nymOwner: null).publicUrlFor(domain: 'bullpay.ca').value,
      invoicePublicUrlFor(nym: null, id: id, domain: 'bullpay.ca').value,
    );
  });

  test('invoicePublicUrlFor is the shared invoice URL contract', () {
    final id = InvoiceId('00000000-0000-0000-0000-000000000001');

    expect(
      invoicePublicUrlFor(nym: 'alice', id: id, domain: 'bullpay.ca').value,
      'https://bullpay.ca/alice/i/00000000-0000-0000-0000-000000000001',
    );
    expect(
      invoicePublicUrlFor(nym: null, id: id, domain: 'bullpay.ca').value,
      'https://bullpay.ca/invoice/00000000-0000-0000-0000-000000000001',
    );
  });
}

Invoice _invoice({
  InvoiceStatus status = InvoiceStatus.unpaid,
  String? nymOwner = 'alice',
  DateTime? expiresAt,
}) {
  return Invoice(
    id: InvoiceId('00000000-0000-0000-0000-000000000001'),
    nymOwner: nymOwner,
    origin: 'wallet',
    status: status,
    amountSat: 1000,
    fiatAmountMinor: null,
    fiatCurrency: null,
    publicDescription: 'Coffee',
    recipientName: 'Alice',
    invoiceNumber: 'INV-1',
    acceptBtc: true,
    acceptLn: true,
    acceptLiquid: true,
    bitcoinAddress: 'bc1qexample',
    liquidAddress: 'lq1example',
    createdAt: DateTime.utc(2026, 5, 11, 11),
    expiresAt: expiresAt ?? DateTime.utc(2026, 5, 11, 13),
    paidVia: null,
    paidAt: null,
    paidAmountSat: null,
    shareUrl: null,
  );
}
