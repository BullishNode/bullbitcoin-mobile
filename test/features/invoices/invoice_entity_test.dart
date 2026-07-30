import 'package:bb_mobile/features/invoices/domain/entities/invoice.dart';
import 'package:bb_mobile/features/invoices/domain/entities/invoice_payment_event.dart';
import 'package:bb_mobile/features/invoices/domain/entities/invoice_status_snapshot.dart';
import 'package:bb_mobile/features/invoices/domain/primitives/invoice_status.dart';
import 'package:bb_mobile/features/invoices/domain/primitives/payment_method.dart';
import 'package:bb_mobile/features/invoices/domain/value_objects/invoice_id.dart';
import 'package:flutter_test/flutter_test.dart';

Invoice _invoice({
  required InvoiceStatus status,
  String? nymOwner,
  required DateTime expiresAt,
  bool? acceptingPayments,
  int? paidAmountSat,
}) {
  return Invoice(
    id: InvoiceId('inv-1'),
    nymOwner: nymOwner,
    status: status,
    amountSat: 25000,
    remainingAmountSat: 25000,
    acceptingPayments: acceptingPayments,
    acceptBtc: false,
    acceptLn: true,
    acceptLiquid: true,
    createdAt: DateTime.utc(2024, 1, 1),
    expiresAt: expiresAt,
    paidAmountSat: paidAmountSat,
  );
}

void main() {
  final now = DateTime.utc(2024, 1, 2, 12);

  InvoiceStatusSnapshot snapshot(InvoiceStatus status) {
    return InvoiceStatusSnapshot(
      status: status,
      pricingMode: 'sat',
      settlementStatus: 'pending',
      amountSat: 25000,
      remainingAmountSat: 25000,
      paymentToleranceSat: 0,
      rateLocksUntil: now.add(const Duration(hours: 1)),
      expiresAt: now.add(const Duration(hours: 1)),
      acceptBtc: true,
      acceptLn: true,
      acceptLiquid: true,
    );
  }

  group('isCancellable', () {
    test('true only for unpaid', () {
      for (final status in InvoiceStatus.values) {
        final invoice = _invoice(
          status: status,
          expiresAt: now.add(const Duration(days: 1)),
        );
        expect(invoice.isCancellable, status == InvoiceStatus.unpaid);
      }
    });
  });

  group('isPayable', () {
    test('unpaid before expiry is payable', () {
      expect(
        _invoice(
          status: InvoiceStatus.unpaid,
          expiresAt: now.add(const Duration(hours: 1)),
        ).isPayable(now),
        isTrue,
      );
    });

    test('unpaid past expiry is not payable', () {
      expect(
        _invoice(
          status: InvoiceStatus.unpaid,
          expiresAt: now.subtract(const Duration(hours: 1)),
        ).isPayable(now),
        isFalse,
      );
    });

    test('paid is never payable', () {
      expect(
        _invoice(
          status: InvoiceStatus.paid,
          expiresAt: now.add(const Duration(hours: 1)),
        ).isPayable(now),
        isFalse,
      );
    });

    test('unsupported is never payable even before expiry', () {
      expect(
        _invoice(
          status: InvoiceStatus.unsupported,
          expiresAt: now.add(const Duration(hours: 1)),
        ).isPayable(now),
        isFalse,
      );
    });

    test('explicitly closed unpaid invoice is not payable', () {
      expect(
        _invoice(
          status: InvoiceStatus.unpaid,
          acceptingPayments: false,
          expiresAt: now.add(const Duration(hours: 1)),
        ).isPayable(now),
        isFalse,
      );
    });

    test('positive evidence overrides contradictory admission', () {
      final invoice = _invoice(
        status: InvoiceStatus.unpaid,
        acceptingPayments: true,
        paidAmountSat: 1,
        expiresAt: now.add(const Duration(hours: 1)),
      );

      expect(invoice.isPayable(now), isFalse);
      expect(invoice.isCancellable, isFalse);
    });

    test('historical partially paid invoice is not collectible', () {
      expect(
        _invoice(
          status: InvoiceStatus.partiallyPaid,
          expiresAt: now.add(const Duration(hours: 1)),
        ).isPayable(now),
        isFalse,
      );
    });
  });

  group('InvoiceStatusSnapshot actions', () {
    test('is cancellable only for unpaid', () {
      for (final status in InvoiceStatus.values) {
        expect(snapshot(status).isCancellable, status == InvoiceStatus.unpaid);
      }
    });

    test('unsupported is not terminal and not cancellable', () {
      final unsupported = snapshot(InvoiceStatus.unsupported);

      expect(unsupported.isTerminal, isFalse);
      expect(unsupported.isCancellable, isFalse);
    });
  });

  group('timeUntilExpiry', () {
    test('positive before expiry', () {
      final invoice = _invoice(
        status: InvoiceStatus.unpaid,
        expiresAt: now.add(const Duration(hours: 2)),
      );
      expect(invoice.timeUntilExpiry(now), const Duration(hours: 2));
    });

    test('zero when already expired', () {
      final invoice = _invoice(
        status: InvoiceStatus.unpaid,
        expiresAt: now.subtract(const Duration(hours: 2)),
      );
      expect(invoice.timeUntilExpiry(now), Duration.zero);
    });
  });

  group('InvoiceStatus wire', () {
    test('round-trips every value', () {
      for (final status in InvoiceStatus.values) {
        expect(InvoiceStatus.fromWire(status.wire), status);
      }
    });

    test('maps unknown wire to unsupported', () {
      final status = InvoiceStatus.fromWire('brand_new_status');

      expect(status, InvoiceStatus.unsupported);
      expect(status.wire, 'unsupported');
      expect(status.isUnsupported, isTrue);
    });

    test('terminal statuses are the settled set', () {
      expect(InvoiceStatus.paid.isTerminal, isTrue);
      expect(InvoiceStatus.expired.isTerminal, isTrue);
      expect(InvoiceStatus.cancelled.isTerminal, isTrue);
      expect(InvoiceStatus.unpaid.isTerminal, isFalse);
      expect(InvoiceStatus.partiallyPaid.isTerminal, isFalse);
    });
  });

  group('InvoiceStatusSnapshot fiat-priced derivations', () {
    InvoicePaymentEvent payment({
      required InvoicePaymentEventState state,
      int confirmations = 0,
      int amountSat = 7794,
    }) {
      return InvoicePaymentEvent(
        rail: PaymentMethod.btc,
        amountSat: amountSat,
        firstSeenAt: now,
        lastSeenAt: now,
        state: state,
        confirmations: confirmations,
        isLate: false,
      );
    }

    InvoiceStatusSnapshot snapshot({
      required InvoiceStatus status,
      required String pricingMode,
      required int amountSat,
      int? fiatAmountMinor,
      String? fiatCurrency,
      int? paidAmountSat,
      List<InvoicePaymentEvent> paymentEvents = const [],
    }) {
      return InvoiceStatusSnapshot(
        status: status,
        pricingMode: pricingMode,
        settlementStatus: 'pending',
        amountSat: amountSat,
        fiatAmountMinor: fiatAmountMinor,
        fiatCurrency: fiatCurrency,
        remainingAmountSat: 0,
        paymentToleranceSat: 0,
        rateLocksUntil: now.add(const Duration(hours: 1)),
        expiresAt: now.add(const Duration(hours: 1)),
        paidAmountSat: paidAmountSat,
        acceptBtc: true,
        acceptLn: true,
        acceptLiquid: true,
        paymentEvents: paymentEvents,
      );
    }

    test('fiat-priced paid invoice never derives overpaid from a zero '
        'sat target', () {
      final fiatPaid = snapshot(
        status: InvoiceStatus.paid,
        pricingMode: 'fiat_fixed',
        amountSat: 0,
        fiatAmountMinor: 500,
        fiatCurrency: 'USD',
        paidAmountSat: 7794,
      );

      expect(fiatPaid.hasSatTarget, isFalse);
      expect(fiatPaid.overpaidAmountSat, isNull);
      expect(fiatPaid.hasFiatFace, isTrue);
    });

    test('sat-priced genuine overpayment is still derived', () {
      final satOverpaid = snapshot(
        status: InvoiceStatus.overpaid,
        pricingMode: 'sat_fixed',
        amountSat: 1000,
        paidAmountSat: 1200,
      );

      expect(satOverpaid.hasSatTarget, isTrue);
      expect(satOverpaid.overpaidAmountSat, 200);
    });

    test('sat-priced exact payment is not overpaid', () {
      final satExact = snapshot(
        status: InvoiceStatus.paid,
        pricingMode: 'sat_fixed',
        amountSat: 1000,
        paidAmountSat: 1000,
      );

      expect(satExact.overpaidAmountSat, isNull);
    });

    test('hasFiatFace requires a non-empty currency', () {
      expect(
        snapshot(
          status: InvoiceStatus.unpaid,
          pricingMode: 'fiat_fixed',
          amountSat: 0,
          fiatAmountMinor: 500,
          fiatCurrency: '  ',
        ).hasFiatFace,
        isFalse,
      );
    });

    test('isAwaitingPayer is true only before any payment evidence', () {
      final awaiting = snapshot(
        status: InvoiceStatus.unpaid,
        pricingMode: 'fiat_fixed',
        amountSat: 0,
        fiatAmountMinor: 500,
        fiatCurrency: 'USD',
      );
      final withEvidence = snapshot(
        status: InvoiceStatus.inProgress,
        pricingMode: 'fiat_fixed',
        amountSat: 0,
        fiatAmountMinor: 500,
        fiatCurrency: 'USD',
        paymentEvents: [payment(state: InvoicePaymentEventState.pending)],
      );
      final terminal = snapshot(
        status: InvoiceStatus.paid,
        pricingMode: 'fiat_fixed',
        amountSat: 0,
        fiatAmountMinor: 500,
        fiatCurrency: 'USD',
        paidAmountSat: 7794,
      );

      expect(awaiting.isAwaitingPayer, isTrue);
      expect(withEvidence.isAwaitingPayer, isFalse);
      expect(terminal.isAwaitingPayer, isFalse);
    });

    test('isAwaitingConfirmation surfaces provisional 0-conf evidence', () {
      final zeroConf = snapshot(
        status: InvoiceStatus.inProgress,
        pricingMode: 'fiat_fixed',
        amountSat: 0,
        fiatAmountMinor: 500,
        fiatCurrency: 'USD',
        paymentEvents: [payment(state: InvoicePaymentEventState.pending)],
      );
      final paid = snapshot(
        status: InvoiceStatus.paid,
        pricingMode: 'fiat_fixed',
        amountSat: 0,
        fiatAmountMinor: 500,
        fiatCurrency: 'USD',
        paidAmountSat: 7794,
      );
      final unpaid = snapshot(
        status: InvoiceStatus.unpaid,
        pricingMode: 'fiat_fixed',
        amountSat: 0,
        fiatAmountMinor: 500,
        fiatCurrency: 'USD',
      );

      expect(zeroConf.isAwaitingConfirmation, isTrue);
      // Terminal paid invoices are confirmed, not awaiting confirmation.
      expect(paid.isAwaitingConfirmation, isFalse);
      // No payment evidence yet.
      expect(unpaid.isAwaitingConfirmation, isFalse);
    });
  });
}
