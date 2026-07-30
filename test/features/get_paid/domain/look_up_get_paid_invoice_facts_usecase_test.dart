import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_failure.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_invoice_facts.dart';
import 'package:bb_mobile/features/get_paid/domain/look_up_get_paid_invoice_facts_usecase.dart';
import 'package:bb_mobile/features/invoices/public/invoices_facade.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeInvoicesFacade invoices;
  late LookUpGetPaidInvoiceFactsUsecase usecase;

  setUp(() {
    invoices = _FakeInvoicesFacade();
    usecase = LookUpGetPaidInvoiceFactsUsecase(invoices: invoices);
  });

  test('returns the invoice snapshot through the Get Paid boundary', () async {
    final snapshot = _snapshot();
    invoices.result = Ok(snapshot);
    invoices.merchantResult = Ok(_merchantInvoice());

    final result = await usecase.execute(
      invoiceId: 'inv-1',
      authenticatedPaymentEvidence: true,
    );

    expect(result, isA<Ok<GetPaidInvoiceFacts, GetPaidFailure>>());
    final facts = (result as Ok<GetPaidInvoiceFacts, GetPaidFailure>).value;
    expect(facts.status, GetPaidInvoiceStatus.unpaid);
    expect(facts.amountSat, 1000);
    expect(facts.acceptingPayments, isTrue);
    expect(facts.topUpAllowed, isFalse);
    expect(facts.authenticatedPaymentEvidence, isTrue);
    expect(facts.paymentSummary?.observedAmountSat, 1200);
    expect(facts.paymentSummary?.creditedAmountSat, 1000);
    expect(facts.paymentSummary?.remainingAmountSat, 0);
    expect(facts.paymentSummary?.excessAmountSat, 200);
    expect(facts.paymentSummary?.logicalPaymentCount, 2);
    expect(facts.paymentSummaryUnavailable, isFalse);
    expect(invoices.requested, InvoiceId('inv-1'));
    expect(invoices.merchantRequested, InvoiceId('inv-1'));
  });

  test('keeps public facts when authenticated accounting is absent', () async {
    invoices.result = Ok(_snapshot());

    final result = await usecase.execute(invoiceId: 'legacy');

    final facts = (result as Ok<GetPaidInvoiceFacts, GetPaidFailure>).value;
    expect(facts.amountSat, 1000);
    expect(facts.paymentSummary, isNull);
    expect(facts.paymentSummaryUnavailable, isTrue);
  });

  test(
    'keeps public facts when authenticated accounting is rejected',
    () async {
      invoices.result = Ok(_snapshot());
      invoices.merchantResult = const Err(InvoicesFailure.network());

      final result = await usecase.execute(invoiceId: 'inv-1');

      final facts = (result as Ok<GetPaidInvoiceFacts, GetPaidFailure>).value;
      expect(facts.paymentSummary, isNull);
      expect(facts.paymentSummaryUnavailable, isTrue);
    },
  );

  test('maps a typed invoices rejection into Get Paid unavailable', () async {
    invoices.result = const Err(InvoicesFailure.notFound());

    final result = await usecase.execute(invoiceId: 'missing');

    expect(result, isA<Err<GetPaidInvoiceFacts, GetPaidFailure>>());
    expect(
      (result as Err<GetPaidInvoiceFacts, GetPaidFailure>).failure,
      isA<GetPaidUnavailableFailure>(),
    );
  });

  test(
    'maps an operational exception but does not catch programming errors',
    () async {
      invoices.thrown = Exception('offline');
      final result = await usecase.execute(invoiceId: 'inv-1');
      expect(result, isA<Err<GetPaidInvoiceFacts, GetPaidFailure>>());
      expect(
        (result as Err<GetPaidInvoiceFacts, GetPaidFailure>).failure,
        isA<GetPaidUnavailableFailure>(),
      );

      invoices.thrown = StateError('programming defect');
      expect(
        () => usecase.execute(invoiceId: 'inv-1'),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'merchant operational failures are explicit but programming errors escape',
    () async {
      invoices.result = Ok(_snapshot());
      invoices.merchantThrown = Exception('offline');

      final result = await usecase.execute(invoiceId: 'inv-1');
      final facts = (result as Ok<GetPaidInvoiceFacts, GetPaidFailure>).value;
      expect(facts.paymentSummaryUnavailable, isTrue);

      invoices.merchantThrown = StateError('programming defect');
      expect(
        () => usecase.execute(invoiceId: 'inv-1'),
        throwsA(isA<StateError>()),
      );
    },
  );
}

InvoiceStatusSnapshot _snapshot() => InvoiceStatusSnapshot(
  status: InvoiceStatus.unpaid,
  pricingMode: 'sat',
  settlementStatus: 'none',
  amountSat: 1000,
  remainingAmountSat: 1000,
  acceptingPayments: true,
  paymentToleranceSat: 0,
  rateLocksUntil: DateTime.utc(2030),
  expiresAt: DateTime.utc(2030),
  acceptBtc: true,
  acceptLn: true,
  acceptLiquid: true,
);

Invoice _merchantInvoice() => Invoice(
  id: InvoiceId('inv-1'),
  status: InvoiceStatus.overpaid,
  amountSat: 1000,
  remainingAmountSat: 0,
  acceptingPayments: false,
  paymentSummary: InvoicePaymentSummary(
    observedAmountSat: 1200,
    creditedAmountSat: 1000,
    remainingAmountSat: 0,
    excessAmountSat: 200,
    logicalPaymentCount: 2,
    multiplePayments: true,
    latePaymentCount: 0,
    hasLatePayment: false,
    firstPaymentAt: DateTime.utc(2026, 7, 29),
    lastPaymentAt: DateTime.utc(2026, 7, 29, 0, 1),
    acceptingPayments: false,
    topUpAllowed: false,
    requiresMerchantAction: true,
    attentionReasons: const ['excess_payment'],
    fiat: null,
  ),
  acceptBtc: true,
  acceptLn: true,
  acceptLiquid: true,
  createdAt: DateTime.utc(2026, 7, 29),
  expiresAt: DateTime.utc(2030),
);

class _FakeInvoicesFacade implements InvoicesFacade {
  Result<InvoiceStatusSnapshot, InvoicesFailure> result = Ok(_snapshot());
  Object? thrown;
  Result<Invoice?, InvoicesFailure> merchantResult =
      const Ok<Invoice?, InvoicesFailure>(null);
  Object? merchantThrown;
  InvoiceId? requested;
  InvoiceId? merchantRequested;

  @override
  Future<Result<InvoiceStatusSnapshot, InvoicesFailure>> status(
    InvoiceId invoiceId,
  ) async {
    requested = invoiceId;
    final error = thrown;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<Result<Invoice?, InvoicesFailure>> merchantInvoice(
    InvoiceId invoiceId,
  ) async {
    merchantRequested = invoiceId;
    final error = merchantThrown;
    if (error != null) throw error;
    return merchantResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
