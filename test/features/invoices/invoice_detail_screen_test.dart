import 'package:bb_mobile/features/invoices/presentation/invoice_detail_cubit.dart';
import 'package:bb_mobile/features/invoices/presentation/invoice_detail_state.dart';
import 'package:bb_mobile/features/invoices/public/invoices_facade.dart';
import 'package:bb_mobile/features/invoices/ui/screens/invoice_detail_screen.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubDetailCubit extends Cubit<InvoiceDetailState>
    implements InvoiceDetailCubit {
  _StubDetailCubit(super.initialState);

  @override
  Future<void> load() async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<void> cancel() async {}
}

InvoicePaymentEvent _bitcoinPayment({
  required InvoicePaymentEventState state,
  required bool isLate,
  int confirmations = 0,
  int amountSat = 1200,
  InvoicePaymentProblem? problem,
}) {
  return InvoicePaymentEvent(
    rail: PaymentMethod.btc,
    amountSat: amountSat,
    firstSeenAt: DateTime.utc(2026, 2),
    lastSeenAt: DateTime.utc(2026, 2, 1, 0, 1),
    state: state,
    confirmations: confirmations,
    transactionId: 'ab' * 32,
    outputIndex: 1,
    isLate: isLate,
    problem: problem,
  );
}

InvoiceStatusSnapshot _snapshot({
  required InvoiceStatus status,
  required InvoiceSettlementState settlementState,
  required InvoicePaymentEvent payment,
  int paidAmountSat = 1000,
  int remainingAmountSat = 0,
}) {
  return InvoiceStatusSnapshot(
    status: status,
    settlementState: settlementState,
    pricingMode: 'sat',
    settlementStatus: 'ignored-after-domain-mapping',
    amountSat: 1000,
    remainingAmountSat: remainingAmountSat,
    paymentToleranceSat: 0,
    rateLocksUntil: DateTime.utc(2026, 1),
    expiresAt: DateTime.utc(2026, 1, 31),
    paidVia: PaymentMethod.btc,
    paidAt: DateTime.utc(2026, 2),
    paidAmountSat: paidAmountSat,
    acceptBtc: true,
    acceptLn: false,
    acceptLiquid: false,
    paymentEvents: [payment],
  );
}

Future<void> _pump(WidgetTester tester, InvoiceDetailState state) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: BlocProvider<InvoiceDetailCubit>.value(
        value: _StubDetailCubit(state),
        child: const InvoiceDetailScreen(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows paid as provisional and attributes fallback to history', (
    tester,
  ) async {
    await _pump(
      tester,
      InvoiceDetailState(
        status: InvoiceDetailStatus.loaded,
        snapshot: _snapshot(
          status: InvoiceStatus.paid,
          settlementState: InvoiceSettlementState.pending,
          payment: _bitcoinPayment(
            state: InvoicePaymentEventState.pending,
            isLate: false,
          ),
        ),
        fallbackSupervisions: [
          InvoiceFallbackSupervision(
            invoiceId: InvoiceId('inv-1'),
            nym: 'merchant',
            state: InvoiceFallbackState.confirming,
            payerAmountSat: 1050,
            invoiceSwapAmountSat: 1000,
            lockupAddress: 'bc1plockup',
            fallbackAddress: 'bc1qmerchant',
            transactionId: 'cd' * 32,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026, 1, 2),
          ),
        ],
      ),
    );

    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('Settlement pending'), findsOneWidget);
    expect(find.text('Payment history'), findsOneWidget);
    expect(find.text('Bitcoin payment'), findsOneWidget);
    expect(
      find.text('Payment received; awaiting confirmation'),
      findsOneWidget,
    );
    expect(find.text('Automatic Bitcoin fallback'), findsOneWidget);
    expect(find.textContaining('Recover'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows overpayment, late attribution and reorg evidence', (
    tester,
  ) async {
    await _pump(
      tester,
      InvoiceDetailState(
        status: InvoiceDetailStatus.loaded,
        snapshot: _snapshot(
          status: InvoiceStatus.overpaid,
          settlementState: InvoiceSettlementState.problem,
          paidAmountSat: 1200,
          payment: _bitcoinPayment(
            state: InvoicePaymentEventState.problem,
            isLate: true,
            problem: InvoicePaymentProblem.reorged,
          ),
        ),
      ),
    );

    expect(find.text('Overpaid'), findsOneWidget);
    expect(find.text('Settlement problem'), findsOneWidget);
    expect(find.text('Overpaid by'), findsOneWidget);
    expect(find.text('Late payment'), findsNWidgets(2));
    expect(
      find.text('Payment confirmation was reversed by a chain reorganization'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows partial received and remaining amounts', (tester) async {
    await _pump(
      tester,
      InvoiceDetailState(
        status: InvoiceDetailStatus.loaded,
        snapshot: _snapshot(
          status: InvoiceStatus.partiallyPaid,
          settlementState: InvoiceSettlementState.pending,
          paidAmountSat: 400,
          remainingAmountSat: 600,
          payment: _bitcoinPayment(
            state: InvoicePaymentEventState.confirming,
            isLate: false,
            confirmations: 1,
            amountSat: 400,
          ),
        ),
      ),
    );

    expect(find.text('Partially paid'), findsOneWidget);
    expect(find.text('Received'), findsNWidgets(2));
    expect(find.text('Remaining'), findsOneWidget);
    expect(find.text('1 confirmation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
