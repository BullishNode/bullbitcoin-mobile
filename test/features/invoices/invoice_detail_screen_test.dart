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

  @override
  Future<void> selectQuoteRail(PaymentMethod rail) async {}

  @override
  Future<void> refreshQuote(PaymentMethod rail) async {}

  @override
  void quoteExpired() {}
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
  String pricingMode = 'sat_fixed',
  InvoiceQuoteRailAvailability? quoteRailAvailability,
}) {
  return InvoiceStatusSnapshot(
    status: status,
    settlementState: settlementState,
    pricingMode: pricingMode,
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
    quoteRailAvailability: quoteRailAvailability,
    paymentEvents: [payment],
  );
}

InvoiceQuote _activeQuote() {
  final createdAt = DateTime.now().toUtc();
  return InvoiceQuote(
    invoiceId: InvoiceId('inv-1'),
    versionId: 'quote-1',
    versionNumber: 1,
    fiatFaceAmountMinor: 5000,
    fiatTargetAmountMinor: 5000,
    fiatCurrency: 'CAD',
    rateMinorPerBtc: 5000000,
    rateSource: 'test-rate',
    rateObservedAt: createdAt.subtract(const Duration(seconds: 2)),
    rateFetchedAt: createdAt.subtract(const Duration(seconds: 1)),
    rateFreshUntil: createdAt.add(const Duration(minutes: 1)),
    createdAt: createdAt,
    expiresAt: createdAt.add(InvoiceQuote.lifetime),
    instruction: InvoiceBitcoinQuoteInstruction(
      quoteOfferId: 'offer-1',
      address: 'bc1qquote',
      bip21: 'bitcoin:bc1qquote?amount=0.00105000',
      amount: InvoicePayerAmount(
        rail: PaymentMethod.btc,
        merchantTargetAmountSat: 100000,
        payerAmountSat: 105000,
      ),
    ),
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

  testWidgets('unsupported status requires update and hides pay actions', (
    tester,
  ) async {
    await _pump(
      tester,
      InvoiceDetailState(
        status: InvoiceDetailStatus.loaded,
        snapshot: InvoiceStatusSnapshot(
          status: InvoiceStatus.unsupported,
          settlementState: InvoiceSettlementState.none,
          pricingMode: 'sat',
          settlementStatus: 'pending',
          amountSat: 1000,
          remainingAmountSat: 1000,
          paymentToleranceSat: 0,
          rateLocksUntil: DateTime.utc(2026, 1),
          expiresAt: DateTime.utc(2026, 1, 31),
          lightningPr: 'lnbc1000',
          liquidAddress: 'lq1qaddress',
          bitcoinAddress: 'bc1qaddress',
          acceptBtc: true,
          acceptLn: true,
          acceptLiquid: true,
        ),
      ),
    );

    expect(find.text('Update required'), findsOneWidget);
    expect(
      find.text(
        'Update the app, then refresh this invoice. Payment reconciliation '
        'may still be in progress.',
      ),
      findsOneWidget,
    );
    expect(find.text('Cancel invoice'), findsNothing);
    expect(find.text('Lightning invoice'), findsNothing);
    expect(find.text('Liquid address'), findsNothing);
    expect(find.text('Bitcoin address'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows one atomic fiat quote with a calm countdown', (
    tester,
  ) async {
    final quote = _activeQuote();
    await _pump(
      tester,
      InvoiceDetailState(
        status: InvoiceDetailStatus.loaded,
        snapshot: _snapshot(
          status: InvoiceStatus.unpaid,
          settlementState: InvoiceSettlementState.none,
          payment: _bitcoinPayment(
            state: InvoicePaymentEventState.pending,
            isLate: false,
          ),
          pricingMode: 'fiat_fixed',
          quoteRailAvailability: const InvoiceQuoteRailAvailability(
            lightning: true,
            liquid: true,
            bitcoin: true,
          ),
        ),
        selectedQuoteRail: PaymentMethod.btc,
        quote: quote,
      ),
    );

    expect(find.text('Payer quote'), findsOneWidget);
    expect(find.text('Quote refreshes in'), findsOneWidget);
    expect(find.text('Merchant amount'), findsOneWidget);
    expect(find.text('Payer sends'), findsOneWidget);
    expect(find.text('Checkout costs'), findsOneWidget);
    expect(find.text(quote.instruction.copyPayload), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh state never exposes the retired copy payload', (
    tester,
  ) async {
    final quote = _activeQuote();
    await _pump(
      tester,
      InvoiceDetailState(
        status: InvoiceDetailStatus.loaded,
        snapshot: _snapshot(
          status: InvoiceStatus.unpaid,
          settlementState: InvoiceSettlementState.none,
          payment: _bitcoinPayment(
            state: InvoicePaymentEventState.pending,
            isLate: false,
          ),
          pricingMode: 'fiat_fixed',
          quoteRailAvailability: const InvoiceQuoteRailAvailability(
            lightning: false,
            liquid: false,
            bitcoin: true,
          ),
        ),
        selectedQuoteRail: PaymentMethod.btc,
        quote: quote,
        quoteRefreshing: true,
      ),
    );

    expect(find.text('Refreshing payer quote…'), findsOneWidget);
    expect(find.text(quote.instruction.copyPayload), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
