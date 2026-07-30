import 'package:bb_mobile/core/themes/app_theme.dart';
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

  @override
  bool canRequestQuote(InvoiceStatusSnapshot snapshot) =>
      snapshot.acceptsInitialPayment(DateTime.now().toUtc());
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

InvoiceStatusSnapshot _historySnapshot({
  required InvoiceStatus status,
  required InvoiceSettlementState settlementState,
  required InvoicePaymentEvent payment,
  int paidAmountSat = 1000,
  int remainingAmountSat = 0,
  String pricingMode = 'sat_fixed',
  int? creationRateMinorPerBtc,
  InvoiceQuoteRailAvailability? quoteRailAvailability,
}) {
  return InvoiceStatusSnapshot(
    status: status,
    settlementState: settlementState,
    pricingMode: pricingMode,
    settlementStatus: 'ignored-after-domain-mapping',
    amountSat: 1000,
    creationRateMinorPerBtc: creationRateMinorPerBtc,
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

/// A fiat-priced snapshot: the invoice row carries no sat target (`amountSat`
/// is 0); the face value lives in fiat.
InvoiceStatusSnapshot _fiatSnapshot({
  required InvoiceStatus status,
  required InvoiceSettlementState settlementState,
  int fiatAmountMinor = 500,
  String fiatCurrency = 'USD',
  int? creationRateMinorPerBtc,
  int? paidAmountSat,
  List<InvoicePaymentEvent> paymentEvents = const [],
  InvoiceQuoteRailAvailability? quoteRailAvailability,
  DateTime? expiresAt,
}) {
  return InvoiceStatusSnapshot(
    status: status,
    settlementState: settlementState,
    pricingMode: 'fiat_fixed',
    settlementStatus: 'ignored-after-domain-mapping',
    amountSat: 0,
    fiatAmountMinor: fiatAmountMinor,
    fiatCurrency: fiatCurrency,
    creationRateMinorPerBtc: creationRateMinorPerBtc,
    remainingAmountSat: 0,
    paymentToleranceSat: 0,
    rateLocksUntil: DateTime.utc(2030),
    expiresAt: expiresAt ?? DateTime.utc(2030),
    paidVia: paidAmountSat == null ? null : PaymentMethod.btc,
    paidAt: paidAmountSat == null ? null : DateTime.utc(2026, 2),
    paidAmountSat: paidAmountSat,
    acceptBtc: true,
    acceptLn: true,
    acceptLiquid: true,
    quoteRailAvailability: quoteRailAvailability,
    paymentEvents: paymentEvents,
  );
}

InvoiceStatusSnapshot _privateLinkSnapshot(InvoiceStatus status) {
  return InvoiceStatusSnapshot(
    status: status,
    pricingMode: 'sat',
    settlementStatus: 'pending',
    amountSat: 1000,
    remainingAmountSat: 1000,
    paymentToleranceSat: 0,
    rateLocksUntil: DateTime.utc(2030),
    expiresAt: DateTime.utc(2030),
    lightningPr: 'lnbc1000',
    liquidAddress: 'lq1qaddress',
    bitcoinAddress: 'bc1qaddress',
    acceptBtc: true,
    acceptLn: true,
    acceptLiquid: true,
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
  final cubit = _StubDetailCubit(state);
  addTearDown(cubit.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.themeData(AppThemeType.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: BlocProvider<InvoiceDetailCubit>.value(
        value: cubit,
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
        snapshot: _historySnapshot(
          status: InvoiceStatus.paid,
          settlementState: InvoiceSettlementState.pending,
          payment: _bitcoinPayment(
            state: InvoicePaymentEventState.pending,
            isLate: false,
          ),
        ),
        privateLinkLookupComplete: true,
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
        snapshot: _historySnapshot(
          status: InvoiceStatus.overpaid,
          settlementState: InvoiceSettlementState.problem,
          paidAmountSat: 1200,
          payment: _bitcoinPayment(
            state: InvoicePaymentEventState.problem,
            isLate: true,
            problem: InvoicePaymentProblem.reorged,
          ),
        ),
        privateLinkLookupComplete: true,
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
        snapshot: _historySnapshot(
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
        privateLinkLookupComplete: true,
      ),
    );

    expect(find.text('Partially paid'), findsOneWidget);
    expect(find.text('Received'), findsNWidgets(2));
    expect(find.text('Difference from requested'), findsOneWidget);
    expect(find.text('1 confirmation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'authenticated summary shows repeated-payment facts without top-up',
    (tester) async {
      final summary = InvoicePaymentSummary(
        observedAmountSat: 2400,
        creditedAmountSat: 2000,
        remainingAmountSat: 0,
        excessAmountSat: 1400,
        logicalPaymentCount: 2,
        multiplePayments: true,
        latePaymentCount: 1,
        hasLatePayment: true,
        firstPaymentAt: DateTime.utc(2026, 2),
        lastPaymentAt: DateTime.utc(2026, 2, 2),
        acceptingPayments: false,
        topUpAllowed: false,
        requiresMerchantAction: true,
        attentionReasons: const ['multiple_payments', 'late_payment'],
        fiat: null,
      );
      final invoice = Invoice(
        id: InvoiceId('inv-1'),
        status: InvoiceStatus.overpaid,
        amountSat: 1000,
        remainingAmountSat: 0,
        acceptingPayments: false,
        paymentSummary: summary,
        acceptBtc: true,
        acceptLn: true,
        acceptLiquid: true,
        createdAt: DateTime.utc(2026),
        expiresAt: DateTime.utc(2030),
      );

      await _pump(
        tester,
        InvoiceDetailState(
          status: InvoiceDetailStatus.loaded,
          invoice: invoice,
          snapshot: _historySnapshot(
            status: InvoiceStatus.overpaid,
            settlementState: InvoiceSettlementState.settled,
            paidAmountSat: 2400,
            payment: _bitcoinPayment(
              state: InvoicePaymentEventState.settled,
              isLate: true,
              amountSat: 2400,
            ),
          ),
          privateLinkLookupComplete: true,
        ),
      );

      expect(find.text('Observed'), findsOneWidget);
      expect(find.text('Credited'), findsOneWidget);
      expect(find.text('Payments observed'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Private payment link'), findsNothing);
      expect(find.text('Cancel invoice'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'retained authenticated evidence marks accounting stale when public lags',
    (tester) async {
      final invoice = Invoice(
        id: InvoiceId('inv-1'),
        status: InvoiceStatus.paid,
        amountSat: 1000,
        remainingAmountSat: 0,
        acceptingPayments: false,
        paymentSummary: InvoicePaymentSummary(
          observedAmountSat: 1000,
          creditedAmountSat: 1000,
          remainingAmountSat: 0,
          excessAmountSat: 0,
          logicalPaymentCount: 1,
          multiplePayments: false,
          latePaymentCount: 0,
          hasLatePayment: false,
          firstPaymentAt: DateTime.utc(2026, 2),
          lastPaymentAt: DateTime.utc(2026, 2),
          acceptingPayments: false,
          topUpAllowed: false,
          requiresMerchantAction: false,
          attentionReasons: const [],
          fiat: null,
        ),
        acceptBtc: true,
        acceptLn: true,
        acceptLiquid: true,
        createdAt: DateTime.utc(2026),
        expiresAt: DateTime.utc(2030),
      );

      await _pump(
        tester,
        InvoiceDetailState(
          status: InvoiceDetailStatus.loaded,
          invoice: invoice,
          snapshot: _privateLinkSnapshot(InvoiceStatus.unpaid),
          authenticatedInvoiceFailure: const InvoicesFailure.network(),
          authenticatedPaymentEvidenceSeen: true,
          privateLinkLookupComplete: true,
        ),
      );

      expect(
        find.text(
          'Payment totals could not be refreshed. '
          'Showing the last verified values.',
        ),
        findsOneWidget,
      );
      expect(find.text('Private payment link'), findsNothing);
      expect(find.text('Cancel invoice'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('initial read failure offers an explicit retry', (tester) async {
    await _pump(
      tester,
      const InvoiceDetailState(
        status: InvoiceDetailStatus.error,
        failure: InvoicesFailure.network(),
      ),
    );

    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cached details disclose a failed refresh', (tester) async {
    await _pump(
      tester,
      InvoiceDetailState(
        status: InvoiceDetailStatus.loaded,
        snapshot: _privateLinkSnapshot(InvoiceStatus.unpaid),
        failure: const InvoicesFailure.network(),
        privateLinkLookupComplete: true,
      ),
    );

    expect(
      find.text('Refresh failed. Showing the last verified invoice details.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsupported status hides payment and private-link actions', (
    tester,
  ) async {
    await _pump(
      tester,
      InvoiceDetailState(
        status: InvoiceDetailStatus.loaded,
        snapshot: _privateLinkSnapshot(InvoiceStatus.unsupported),
        privateLinkLookupComplete: true,
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
    expect(find.text('Private payment link'), findsNothing);
    expect(find.text('Lightning invoice'), findsNothing);
    expect(find.text('Liquid address'), findsNothing);
    expect(find.text('Bitcoin address'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retained private link is available only before evidence', (
    tester,
  ) async {
    final invoiceId = InvoiceId('inv-1');
    final link = PrivateInvoiceLink.fromServer(
      invoiceUrl: 'https://pay2.bull-wallet.com/invoice/inv-1',
      expectedInvoiceId: invoiceId,
      viewingKey: 'A' * 43,
      expectedOrigin: Uri.parse('https://pay2.bull-wallet.com'),
      expectedNym: null,
    );
    await _pump(
      tester,
      InvoiceDetailState(
        status: InvoiceDetailStatus.loaded,
        snapshot: _privateLinkSnapshot(InvoiceStatus.unpaid),
        privateLink: link,
        privateLinkLookupComplete: true,
      ),
    );

    expect(find.text('Private payment link'), findsOneWidget);
    expect(find.text('Copy private link'), findsOneWidget);
    expect(find.text('Share private link'), findsOneWidget);
    expect(find.text('Open link'), findsOneWidget);
    expect(find.text('Lightning invoice'), findsNothing);
    expect(find.text('Liquid address'), findsNothing);
    expect(find.text('Bitcoin address'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('payment evidence hides retained private-link actions', (
    tester,
  ) async {
    await _pump(
      tester,
      InvoiceDetailState(
        status: InvoiceDetailStatus.loaded,
        snapshot: _privateLinkSnapshot(InvoiceStatus.paid),
        privateLinkLookupComplete: true,
      ),
    );

    expect(find.text('Private payment link'), findsNothing);
    expect(find.text('Private link unavailable on this device'), findsNothing);
    expect(find.text('Copy private link'), findsNothing);
    expect(find.text('Share private link'), findsNothing);
    expect(find.text('Open link'), findsNothing);
    expect(find.text('Lightning invoice'), findsNothing);
    expect(find.text('Liquid address'), findsNothing);
    expect(find.text('Bitcoin address'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows one atomic fiat quote without a sharing payload', (
    tester,
  ) async {
    final quote = _activeQuote();
    await _pump(
      tester,
      InvoiceDetailState(
        status: InvoiceDetailStatus.loaded,
        snapshot: _fiatSnapshot(
          status: InvoiceStatus.unpaid,
          settlementState: InvoiceSettlementState.none,
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
    expect(find.text(quote.instruction.copyPayload), findsNothing);
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
        snapshot: _fiatSnapshot(
          status: InvoiceStatus.unpaid,
          settlementState: InvoiceSettlementState.none,
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

  testWidgets('an expired unpaid fiat invoice exposes no payer quote', (
    tester,
  ) async {
    await _pump(
      tester,
      InvoiceDetailState(
        status: InvoiceDetailStatus.loaded,
        snapshot: _fiatSnapshot(
          status: InvoiceStatus.unpaid,
          settlementState: InvoiceSettlementState.none,
          expiresAt: DateTime.utc(2020),
          quoteRailAvailability: const InvoiceQuoteRailAvailability(
            lightning: true,
            liquid: true,
            bitcoin: true,
          ),
        ),
        selectedQuoteRail: PaymentMethod.btc,
        quote: _activeQuote(),
      ),
    );

    expect(find.text('Payer quote'), findsNothing);
    expect(find.text('Payer quote is temporarily unavailable'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fiat-priced paid invoice headlines fiat, no false overpaid, '
      'no quote banner', (tester) async {
    await _pump(
      tester,
      InvoiceDetailState(
        status: InvoiceDetailStatus.loaded,
        snapshot: _fiatSnapshot(
          status: InvoiceStatus.paid,
          settlementState: InvoiceSettlementState.settled,
          fiatAmountMinor: 500,
          fiatCurrency: 'USD',
          paidAmountSat: 7794,
          paymentEvents: [
            _bitcoinPayment(
              state: InvoicePaymentEventState.settled,
              isLate: false,
              confirmations: 1,
              amountSat: 7794,
            ),
          ],
          quoteRailAvailability: const InvoiceQuoteRailAvailability(
            lightning: false,
            liquid: false,
            bitcoin: false,
          ),
        ),
        privateLinkLookupComplete: true,
      ),
    );

    expect(find.text('Paid'), findsOneWidget);
    // Fiat face value headlined, never "0 sats".
    expect(find.text('5.00 USD'), findsOneWidget);
    expect(find.text('0 sats'), findsNothing);
    // Actual paid sats shown alongside.
    expect(find.text('7794 sats'), findsWidgets);
    // No false overpaid row (fiat invoice has no positive sat target).
    expect(find.text('Overpaid by'), findsNothing);
    // Quote is irrelevant once terminal / paid.
    expect(find.text('Payer quote'), findsNothing);
    expect(find.text('Payer quote is temporarily unavailable'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fiat-priced 0-conf shows awaiting-confirmation, not a quote '
      'banner', (tester) async {
    await _pump(
      tester,
      InvoiceDetailState(
        status: InvoiceDetailStatus.loaded,
        snapshot: _fiatSnapshot(
          status: InvoiceStatus.inProgress,
          settlementState: InvoiceSettlementState.pending,
          fiatAmountMinor: 500,
          fiatCurrency: 'USD',
          paymentEvents: [
            _bitcoinPayment(
              state: InvoicePaymentEventState.pending,
              isLate: false,
              amountSat: 7794,
            ),
          ],
          // TTL-expired availability must not surface a banner once payment
          // evidence exists.
          quoteRailAvailability: const InvoiceQuoteRailAvailability(
            lightning: false,
            liquid: false,
            bitcoin: false,
          ),
        ),
        privateLinkLookupComplete: true,
      ),
    );

    expect(
      find.text('Payment detected — waiting for confirmation'),
      findsOneWidget,
    );
    expect(find.text('5.00 USD'), findsOneWidget);
    expect(find.text('0 sats'), findsNothing);
    expect(find.text('Overpaid by'), findsNothing);
    expect(find.text('Payer quote'), findsNothing);
    expect(find.text('Payer quote is temporarily unavailable'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a fiat-priced invoice with a creation rate shows the Rate at creation row',
    (tester) async {
      await _pump(
        tester,
        InvoiceDetailState(
          status: InvoiceDetailStatus.loaded,
          snapshot: _fiatSnapshot(
            status: InvoiceStatus.unpaid,
            settlementState: InvoiceSettlementState.none,
            fiatAmountMinor: 500,
            fiatCurrency: 'USD',
            creationRateMinorPerBtc: 6416000,
          ),
          privateLinkLookupComplete: true,
        ),
      );
      expect(find.text('Rate at creation'), findsOneWidget);
      // Rendered in the invoice's own fiat currency (USD), marked ≈.
      expect(find.text('≈ 64,160.00 USD / BTC'), findsOneWidget);
    },
  );

  testWidgets('a fiat-priced invoice without a creation rate shows no row', (
    tester,
  ) async {
    await _pump(
      tester,
      InvoiceDetailState(
        status: InvoiceDetailStatus.loaded,
        snapshot: _fiatSnapshot(
          status: InvoiceStatus.unpaid,
          settlementState: InvoiceSettlementState.none,
        ),
        privateLinkLookupComplete: true,
      ),
    );
    expect(find.text('Rate at creation'), findsNothing);
  });

  testWidgets('a sat-priced invoice never shows the Rate at creation row', (
    tester,
  ) async {
    // Even with a stray creation rate, a sat-priced invoice has no fiat face,
    // so the merchant reference-rate row must not render.
    await _pump(
      tester,
      InvoiceDetailState(
        status: InvoiceDetailStatus.loaded,
        snapshot: _historySnapshot(
          status: InvoiceStatus.paid,
          settlementState: InvoiceSettlementState.none,
          payment: _bitcoinPayment(
            state: InvoicePaymentEventState.settled,
            isLate: false,
          ),
          creationRateMinorPerBtc: 6416000,
        ),
        privateLinkLookupComplete: true,
      ),
    );
    expect(find.text('Rate at creation'), findsNothing);
  });
}
