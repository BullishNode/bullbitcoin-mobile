import 'dart:async';

import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_failure.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_invoice_facts.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/look_up_get_paid_invoice_facts_usecase.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_invoice_facts_cubit.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_invoice_facts_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no invoice id performs no read and remains initial', () async {
    final lookup = _FakeLookUpInvoiceFacts();
    final cubit = GetPaidInvoiceFactsCubit(lookUpInvoiceFacts: lookup);

    await cubit.load(invoiceId: null);

    expect(cubit.state, isA<GetPaidInvoiceFactsInitial>());
    expect(lookup.calls, isEmpty);
    await cubit.close();
  });

  test('emits loading then the invoice facts', () async {
    final lookup = _FakeLookUpInvoiceFacts(result: Ok(_snapshot()));
    final cubit = GetPaidInvoiceFactsCubit(lookUpInvoiceFacts: lookup);
    final states = <GetPaidInvoiceFactsState>[];
    final subscription = cubit.stream.listen(states.add);

    await cubit.load(invoiceId: 'inv-1');
    await Future<void>.delayed(Duration.zero);

    expect(states, [
      isA<GetPaidInvoiceFactsLoading>(),
      isA<GetPaidInvoiceFactsData>(),
    ]);
    await subscription.cancel();
    await cubit.close();
  });

  test(
    'states a failed read instead of pretending no invoice exists',
    () async {
      final lookup = _FakeLookUpInvoiceFacts(
        result: const Err(GetPaidFailure.unavailable()),
      );
      final cubit = GetPaidInvoiceFactsCubit(lookUpInvoiceFacts: lookup);

      await cubit.load(invoiceId: 'inv-1');

      expect(cubit.state, isA<GetPaidInvoiceFactsFailure>());
      await cubit.close();
    },
  );

  test('an older read cannot overwrite a newer refreshed summary', () async {
    final lookup = _ControlledLookUpInvoiceFacts();
    final cubit = GetPaidInvoiceFactsCubit(lookUpInvoiceFacts: lookup);

    final older = cubit.load(invoiceId: 'inv-1');
    final newer = cubit.retry();

    lookup.pending[1].complete(
      Ok(_snapshot(status: GetPaidInvoiceStatus.paid)),
    );
    await newer;
    expect(
      (cubit.state as GetPaidInvoiceFactsData).invoice.status,
      GetPaidInvoiceStatus.paid,
    );

    lookup.pending[0].complete(Ok(_snapshot()));
    await older;
    expect(
      (cubit.state as GetPaidInvoiceFactsData).invoice.status,
      GetPaidInvoiceStatus.paid,
    );
    await cubit.close();
  });

  test(
    'a refresh failure retains verified invoice facts and marks them stale',
    () async {
      final lookup = _SequencedLookUpInvoiceFacts([
        Ok(_snapshot(status: GetPaidInvoiceStatus.paid)),
        const Err(GetPaidFailure.unavailable()),
      ]);
      final cubit = GetPaidInvoiceFactsCubit(lookUpInvoiceFacts: lookup);

      await cubit.load(invoiceId: 'inv-1');
      await cubit.retry();

      final state = cubit.state as GetPaidInvoiceFactsData;
      expect(state.invoice.status, GetPaidInvoiceStatus.paid);
      expect(state.isRefreshing, isFalse);
      expect(state.refreshFailed, isTrue);
      await cubit.close();
    },
  );
}

GetPaidInvoiceFacts _snapshot({
  GetPaidInvoiceStatus status = GetPaidInvoiceStatus.unpaid,
}) => GetPaidInvoiceFacts(
  status: status,
  settlementState: GetPaidInvoiceSettlementState.none,
  pricingMode: 'sat',
  amountSat: 1000,
  fiatAmountMinor: null,
  fiatCurrency: null,
  remainingAmountSat: 1000,
  paymentSummary: null,
  paymentSummaryUnavailable: false,
  paymentToleranceSat: 0,
  creationRateMinorPerBtc: null,
  rateLocksUntil: DateTime.utc(2030),
  expiresAt: DateTime.utc(2030),
  paidVia: null,
  paidAt: null,
  paidAmountSat: null,
  acceptBtc: true,
  acceptLn: true,
  acceptLiquid: true,
  paymentEvents: const [],
  presentationMarksLatePayment: false,
);

class _FakeLookUpInvoiceFacts implements LookUpGetPaidInvoiceFactsUsecase {
  final Result<GetPaidInvoiceFacts, GetPaidFailure> result;
  final List<String> calls = [];

  _FakeLookUpInvoiceFacts({
    this.result = const Err(GetPaidFailure.unavailable()),
  });

  @override
  Future<Result<GetPaidInvoiceFacts, GetPaidFailure>> execute({
    required String invoiceId,
  }) async {
    calls.add(invoiceId);
    return result;
  }
}

class _ControlledLookUpInvoiceFacts
    implements LookUpGetPaidInvoiceFactsUsecase {
  final List<Completer<Result<GetPaidInvoiceFacts, GetPaidFailure>>> pending =
      [];

  @override
  Future<Result<GetPaidInvoiceFacts, GetPaidFailure>> execute({
    required String invoiceId,
  }) {
    final completer = Completer<Result<GetPaidInvoiceFacts, GetPaidFailure>>();
    pending.add(completer);
    return completer.future;
  }
}

class _SequencedLookUpInvoiceFacts implements LookUpGetPaidInvoiceFactsUsecase {
  final List<Result<GetPaidInvoiceFacts, GetPaidFailure>> _results;

  _SequencedLookUpInvoiceFacts(this._results);

  @override
  Future<Result<GetPaidInvoiceFacts, GetPaidFailure>> execute({
    required String invoiceId,
  }) async => _results.removeAt(0);
}
