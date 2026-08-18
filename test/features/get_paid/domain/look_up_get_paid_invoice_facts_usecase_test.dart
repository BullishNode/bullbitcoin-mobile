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

    final result = await usecase.execute(invoiceId: 'inv-1');

    expect(result, isA<Ok<GetPaidInvoiceFacts, GetPaidFailure>>());
    final facts = (result as Ok<GetPaidInvoiceFacts, GetPaidFailure>).value;
    expect(facts.status, GetPaidInvoiceStatus.unpaid);
    expect(facts.amountSat, 1000);
    expect(invoices.requested, InvoiceId('inv-1'));
  });

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
}

InvoiceStatusSnapshot _snapshot() => InvoiceStatusSnapshot(
  status: InvoiceStatus.unpaid,
  pricingMode: 'sat',
  settlementStatus: 'none',
  amountSat: 1000,
  remainingAmountSat: 1000,
  paymentToleranceSat: 0,
  rateLocksUntil: DateTime.utc(2030),
  expiresAt: DateTime.utc(2030),
  acceptBtc: true,
  acceptLn: true,
  acceptLiquid: true,
);

class _FakeInvoicesFacade implements InvoicesFacade {
  Result<InvoiceStatusSnapshot, InvoicesFailure> result = Ok(_snapshot());
  Object? thrown;
  InvoiceId? requested;

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
