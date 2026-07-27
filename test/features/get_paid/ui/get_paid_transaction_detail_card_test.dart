import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/utils/string_formatting.dart';
import 'package:bb_mobile/core/widgets/tables/details_table.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_settlement.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_transaction.dart';
import 'package:bb_mobile/features/get_paid/ui/screens/get_paid_transaction_detail_screen.dart';
import 'package:bb_mobile/features/invoices/public/invoices_facade.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockInvoicesFacade extends Mock implements InvoicesFacade {}

const _invoiceId = '50000000-0000-4000-8000-000000000005';
const _transactionId = '10000000-0000-4000-8000-000000000001';
const _lightningPr =
    'lnbc21u1pjqqqqqpp5qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqsp5';
const _liquidAddress =
    'lq1qqw8s0dcyzlrgtzcvptmk9wm2m7wcnfd0e3pzq0m0lsjqk7d0zj9qqqqqqqqq';

/// The in-table rendering of a long value: truncated, copied in full.
String _truncated(String value) => StringFormatting.truncateMiddle(value);

GetPaidTransaction _tx({
  GetPaidSettlement? settlement,
  GetPaidTransactionSource source = GetPaidTransactionSource.invoice,
  String? invoiceId = _invoiceId,
  int amountSat = 2100,
}) => GetPaidTransaction(
  transactionId: _transactionId,
  source: source,
  invoiceId: invoiceId,
  amountSat: amountSat,
  receivedAt: DateTime.utc(2026, 7, 18, 12),
  rail: GetPaidTransactionRail.lightning,
  settlementState: GetPaidSettlementState.settled,
  late: false,
  comment: null,
  settlement: settlement,
);

/// A mixed settlement with both legs and a known R1 (face USD, leg CAD).
GetPaidSettlement _mixed({
  int? creationRateMinorPerBtc = 6416000,
  String? creationRateCurrency = 'USD',
}) => GetPaidSettlement(
  kind: GetPaidSettlementKind.mixed,
  fiatPercentage: 40,
  creationRateMinorPerBtc: creationRateMinorPerBtc,
  creationRateCurrency: creationRateCurrency,
  bitcoin: const [
    GetPaidBitcoinSettlementLeg(
      amountSat: 60000,
      network: 'liquid',
      status: GetPaidSettlementLegStatus.settled,
    ),
  ],
  fiat: const [
    GetPaidFiatSettlementLeg(
      amountMinor: 12345,
      currency: 'CAD',
      orderId: '40000000-0000-4000-8000-000000000009',
      status: GetPaidSettlementLegStatus.settled,
    ),
  ],
);

InvoiceStatusSnapshot _snapshot({
  InvoiceStatus status = InvoiceStatus.overpaid,
  InvoiceSettlementState settlementState = InvoiceSettlementState.settled,
  String pricingMode = 'fiat_fixed',
  int? fiatAmountMinor = 5000,
  String? fiatCurrency = 'USD',
  int amountSat = 0,
  int remainingAmountSat = 0,
  int paymentToleranceSat = 100,
  int? creationRateMinorPerBtc,
  int? rateMinorPerBtc,
  int? paidAmountSat = 2100,
  List<InvoicePaymentEvent> paymentEvents = const [],
  String? lightningPr,
  String? liquidAddress,
  String? bitcoinAddress,
  String? bitcoinChainAddress,
  String? bitcoinChainBip21,
  InvoicePayerAmount? lightningPayerAmount,
  InvoiceQuoteRailAvailability? quoteRailAvailability,
}) => InvoiceStatusSnapshot(
  status: status,
  settlementState: settlementState,
  pricingMode: pricingMode,
  settlementStatus: 'settled',
  amountSat: amountSat,
  fiatAmountMinor: fiatAmountMinor,
  fiatCurrency: fiatCurrency,
  remainingAmountSat: remainingAmountSat,
  paymentToleranceSat: paymentToleranceSat,
  creationRateMinorPerBtc: creationRateMinorPerBtc,
  rateMinorPerBtc: rateMinorPerBtc,
  rateLocksUntil: DateTime.utc(2026, 7, 18, 12, 5),
  expiresAt: DateTime.utc(2026, 7, 25, 12),
  paidVia: PaymentMethod.lightning,
  paidAt: DateTime.utc(2026, 7, 18, 11, 59),
  paidAmountSat: paidAmountSat,
  lightningPr: lightningPr,
  lightningPayerAmount: lightningPayerAmount,
  liquidAddress: liquidAddress,
  bitcoinAddress: bitcoinAddress,
  bitcoinChainAddress: bitcoinChainAddress,
  bitcoinChainBip21: bitcoinChainBip21,
  acceptBtc: true,
  acceptLn: true,
  acceptLiquid: false,
  quoteRailAvailability: quoteRailAvailability,
  paymentEvents: paymentEvents,
);

Widget _app(Widget home) => MaterialApp(
  theme: AppTheme.themeData(AppThemeType.light),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: home,
);

Future<void> _pump(WidgetTester tester, GetPaidTransaction transaction) async {
  // A tall surface so every section of the scrolling card is built and findable.
  await tester.binding.setSurfaceSize(const Size(1000, 4000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _app(GetPaidTransactionDetailScreen(transaction: transaction)),
  );
  await tester.pumpAndSettle();
}

/// Registers a facade whose status read returns [snapshot].
_MockInvoicesFacade _registerFacade(InvoiceStatusSnapshot snapshot) {
  final facade = _MockInvoicesFacade();
  when(() => facade.status(any())).thenAnswer(
    (_) async => Ok<InvoiceStatusSnapshot, InvoicesFailure>(snapshot),
  );
  locator.registerSingleton<InvoicesFacade>(facade);
  return facade;
}

final _payerSection = find.byKey(
  const ValueKey('get-paid-payer-instructions-section'),
);
final _eventSection = find.byKey(
  const ValueKey('get-paid-invoice-payment-events'),
);

Finder _inside(Finder section, Finder matching) =>
    find.descendant(of: section, matching: matching);

void main() {
  setUpAll(() => registerFallbackValue(InvoiceId(_invoiceId)));
  tearDown(() => locator.reset());

  group('the card replaces the invoice screen', () {
    testWidgets('an invoice-backed entry offers no View invoice action', (
      tester,
    ) async {
      await _pump(tester, _tx());

      expect(find.text('View invoice'), findsNothing);
      expect(find.byIcon(Icons.receipt_long), findsNothing);
    });
  });

  group('sections', () {
    testWidgets('each populated section carries its own titled table', (
      tester,
    ) async {
      _registerFacade(_snapshot(lightningPr: _lightningPr));

      await _pump(tester, _tx(settlement: _mixed()));

      for (final title in const [
        'Details',
        'Settlement',
        'Payer instructions',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
      // "Invoice" twice: the Source row's value and the invoice section title.
      expect(find.text('Invoice'), findsNWidgets(2));
      expect(find.byType(DetailsTable), findsNWidgets(4));
      // No payment events ⇒ no Payment history section at all (never a header
      // over nothing).
      expect(find.text('Payment history'), findsNothing);
      expect(_eventSection, findsNothing);
    });
  });

  group('server row fields the card used to drop', () {
    testWidgets('the receipt id renders as a copyable, truncated row', (
      tester,
    ) async {
      await _pump(tester, _tx());

      expect(
        find.byKey(const ValueKey('get-paid-transaction-id')),
        findsOneWidget,
      );
      expect(find.text('Receipt ID'), findsOneWidget);
      expect(find.text(_truncated(_transactionId)), findsOneWidget);
      // Never the full identifier wrapping across table lines.
      expect(find.text(_transactionId), findsNothing);
      // Copy affordance, same idiom as the invoice-id row.
      expect(find.byIcon(Icons.copy_outlined), findsWidgets);
      // Never presented as a chain transaction id.
      expect(find.text('Transaction ID'), findsNothing);
    });

    testWidgets('a bitcoin leg names the network it settled on', (
      tester,
    ) async {
      await _pump(tester, _tx(settlement: _mixed()));

      expect(find.text('Settlement network'), findsOneWidget);
      expect(find.text('Liquid'), findsOneWidget);
    });

    testWidgets('a fiat-conversion override renders its status and reason', (
      tester,
    ) async {
      await _pump(
        tester,
        _tx(
          settlement: const GetPaidSettlement(
            kind: GetPaidSettlementKind.bitcoin,
            overrideReason: GetPaidFiatOverrideReason.belowMinimum,
          ),
        ),
      );

      // The kind is stated, and the override IS the status ("overridden"),
      // explained by its reason.
      expect(find.text('Settled as'), findsOneWidget);
      expect(find.text('Bitcoin'), findsOneWidget);
      expect(find.text('Fiat conversion'), findsOneWidget);
      expect(find.textContaining('below Bull Bitcoin'), findsOneWidget);
    });
  });

  group('the invoice section', () {
    testWidgets('renders the invoice\'s own state', (tester) async {
      _registerFacade(
        _snapshot(
          amountSat: 2000,
          fiatAmountMinor: null,
          fiatCurrency: null,
          pricingMode: 'sat_fixed',
          paidAmountSat: 2100,
        ),
      );

      await _pump(tester, _tx());

      expect(
        find.byKey(const ValueKey('get-paid-invoice-section')),
        findsOneWidget,
      );
      expect(find.text('Overpaid'), findsOneWidget);
      // Sat-priced face amount (differs from the headline), pricing mode,
      // overpayment, tolerance, expiry, paid via / at, accepted rails.
      expect(find.text('2,000 sats'), findsOneWidget);
      expect(find.text('Pricing'), findsOneWidget);
      expect(find.text('Sats'), findsOneWidget);
      expect(find.text('Overpaid by'), findsOneWidget);
      expect(find.text('Payment tolerance'), findsOneWidget);
      expect(find.text('100 sats'), findsNWidgets(2));
      expect(find.text('Expires'), findsOneWidget);
      expect(find.text('Paid via'), findsOneWidget);
      expect(find.text('Paid at'), findsOneWidget);
      expect(find.text('Accepted payment methods'), findsOneWidget);
      expect(find.text('Lightning · On-chain Bitcoin'), findsOneWidget);
      // A sat-priced invoice has no rate to lock.
      expect(find.text('Rate locked until'), findsNothing);
    });

    testWidgets('a fiat-priced invoice shows its face value and rate lock', (
      tester,
    ) async {
      _registerFacade(_snapshot());

      await _pump(tester, _tx());

      expect(find.text('50.00 USD'), findsOneWidget);
      expect(find.text('Fiat'), findsOneWidget);
      expect(find.text('Rate locked until'), findsOneWidget);
    });

    testWidgets('facts the sections above already state are not repeated', (
      tester,
    ) async {
      // A sat face equal to the headline, a paid amount equal to the headline,
      // and a settlement state that agrees with the entry's Status row.
      _registerFacade(
        _snapshot(
          status: InvoiceStatus.paid,
          amountSat: 2100,
          fiatAmountMinor: null,
          fiatCurrency: null,
          pricingMode: 'sat_fixed',
          paidAmountSat: 2100,
        ),
      );

      await _pump(tester, _tx());

      // The headline already says 2,100 sats; neither the face amount nor the
      // paid amount repeats it.
      expect(find.text('2,100 sats'), findsOneWidget);
      expect(find.text('Amount'), findsNothing);
      expect(find.text('Amount paid'), findsNothing);
      // Settled on both sides ⇒ the supporting settlement line adds nothing.
      expect(find.text('Settlement complete'), findsNothing);
      expect(find.text('Settled'), findsOneWidget);
    });

    testWidgets('a paid amount that differs from the headline is shown', (
      tester,
    ) async {
      // A 5,000 sat invoice paid in two parts: this entry received 2,100 while
      // the invoice as a whole has taken in 4,000.
      _registerFacade(
        _snapshot(
          status: InvoiceStatus.partiallyPaid,
          amountSat: 5000,
          fiatAmountMinor: null,
          fiatCurrency: null,
          pricingMode: 'sat_fixed',
          paidAmountSat: 4000,
          remainingAmountSat: 1000,
        ),
      );

      await _pump(tester, _tx());

      // Labelled "Amount paid" — the core facts already use "Received" for the
      // moment the payment arrived.
      expect(find.text('Amount paid'), findsOneWidget);
      expect(find.text('4,000 sats'), findsOneWidget);
      expect(find.text('Remaining'), findsOneWidget);
      expect(find.text('1,000 sats'), findsOneWidget);
      // The headline stays this entry's own amount.
      expect(find.text('2,100 sats'), findsOneWidget);
    });

    testWidgets('the R1 rate is never printed twice', (tester) async {
      // The settlement section already shows this exact R1 (6416000 USD).
      _registerFacade(_snapshot(creationRateMinorPerBtc: 6416000));

      await _pump(tester, _tx(settlement: _mixed()));

      expect(find.text('Rate at creation'), findsOneWidget);
      expect(find.text('≈ 64160.00 USD / BTC'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('get-paid-invoice-rate-at-creation')),
        findsNothing,
      );
    });

    testWidgets('an R1 the settlement section does not show is rendered', (
      tester,
    ) async {
      // No settlement projection at all ⇒ nothing above printed the rate.
      _registerFacade(_snapshot(creationRateMinorPerBtc: 6416000));

      await _pump(tester, _tx());

      expect(
        find.byKey(const ValueKey('get-paid-invoice-rate-at-creation')),
        findsOneWidget,
      );
      expect(find.text('≈ 64160.00 USD / BTC'), findsOneWidget);
    });
  });

  group('the payment history section', () {
    InvoicePaymentEvent event() => InvoicePaymentEvent(
      rail: PaymentMethod.lightning,
      amountSat: 2100,
      firstSeenAt: DateTime.utc(2026, 7, 18, 11, 58),
      lastSeenAt: DateTime.utc(2026, 7, 18, 11, 59),
      state: InvoicePaymentEventState.settled,
      confirmations: 0,
      transactionId: 'abc123',
      outputIndex: 1,
      isLate: false,
    );

    testWidgets('one compact row per event, its detail behind the expander', (
      tester,
    ) async {
      _registerFacade(_snapshot(paymentEvents: [event()]));

      await _pump(tester, _tx());

      expect(_eventSection, findsOneWidget);
      expect(find.text('Payment history'), findsOneWidget);
      // The visible line: the rail, the amount and the state.
      expect(_inside(_eventSection, find.text('Lightning payment')), findsOne);
      expect(_inside(_eventSection, find.text('2,100 sats')), findsOne);
      expect(
        _inside(_eventSection, find.text('Settlement complete')),
        findsOne,
      );
      // The remaining per-event facts stay collapsed until asked for.
      expect(find.text('First seen'), findsNothing);
      expect(find.text('Last seen'), findsNothing);
      expect(find.text('Output index'), findsNothing);

      await tester.tap(_inside(_eventSection, find.byIcon(Icons.expand_more)));
      await tester.pumpAndSettle();

      expect(find.text('First seen'), findsOneWidget);
      expect(find.text('Last seen'), findsOneWidget);
      expect(find.text('Transaction ID'), findsOneWidget);
      expect(find.text('abc123'), findsOneWidget);
      expect(find.text('Output index'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });
  });

  group('the payer-instructions section', () {
    InvoiceStatusSnapshot withInstructions() => _snapshot(
      lightningPr: _lightningPr,
      liquidAddress: _liquidAddress,
      bitcoinAddress: 'bc1qonchainaddressonchainaddressonchain',
      bitcoinChainAddress: 'bc1qchainaddresschainaddresschainaddr',
      bitcoinChainBip21:
          'bitcoin:bc1qchainaddresschainaddresschainaddr?amount=0.000021',
      lightningPayerAmount: InvoicePayerAmount(
        rail: PaymentMethod.lightning,
        merchantTargetAmountSat: 2000,
        payerAmountSat: 2100,
      ),
      quoteRailAvailability: const InvoiceQuoteRailAvailability(
        lightning: true,
        liquid: true,
        bitcoin: false,
      ),
    );

    testWidgets(
      'every payload the snapshot carries renders, last on the card',
      (tester) async {
        _registerFacade(withInstructions());

        await _pump(tester, _tx());

        expect(_payerSection, findsOneWidget);
        for (final label in const [
          'Lightning invoice',
          'Liquid address',
          'Bitcoin address',
          'Bitcoin chain address',
          'Bitcoin payment URI',
        ]) {
          expect(_inside(_payerSection, find.text(label)), findsOne);
        }
        // Long payloads are truncated in place, never wrapped in full.
        expect(find.text(_truncated(_lightningPr)), findsOneWidget);
        expect(find.text(_truncated(_liquidAddress)), findsOneWidget);
        // The per-rail payer amount: what the payer sends, on its own row.
        expect(_inside(_payerSection, find.text('Lightning')), findsOne);
        expect(find.text('Payer sends'), findsOneWidget);
        expect(_inside(_payerSection, find.text('2,100 sats')), findsOne);
        // Quote rail availability, rendered as the rails it was available on.
        expect(find.text('Payer quote rails'), findsOneWidget);
        expect(find.text('Lightning · Liquid'), findsOneWidget);
      },
    );

    testWidgets('a bulky payload is collapsed by default and expands on tap', (
      tester,
    ) async {
      _registerFacade(withInstructions());

      await _pump(tester, _tx());

      // Collapsed: only the truncated form is on screen.
      expect(find.text(_lightningPr), findsNothing);

      await tester.tap(
        _inside(_payerSection, find.byIcon(Icons.expand_more)).first,
      );
      await tester.pumpAndSettle();

      expect(find.text(_lightningPr), findsOneWidget);
    });

    testWidgets('the payer amount detail is behind the expander too', (
      tester,
    ) async {
      _registerFacade(withInstructions());

      await _pump(tester, _tx());

      expect(find.text('Merchant amount'), findsNothing);
      expect(find.text('Checkout costs'), findsNothing);

      await tester.tap(
        _inside(_payerSection, find.byIcon(Icons.expand_more)).last,
      );
      await tester.pumpAndSettle();

      expect(find.text('Merchant amount'), findsOneWidget);
      expect(find.text('Checkout costs'), findsOneWidget);
      expect(find.text('2,000 sats'), findsOneWidget);
    });

    testWidgets('the live payer quote rate is labelled as such, never as R1', (
      tester,
    ) async {
      _registerFacade(
        _snapshot(creationRateMinorPerBtc: 6416000, rateMinorPerBtc: 6390000),
      );

      await _pump(tester, _tx());

      // The quote rate lives in the payer-instructions section, plainly stated —
      // no ≈ (that marks the R1 reference index) and no "executed at" (that
      // marks R2) — under a muted qualifier naming it the quote at fetch time.
      expect(_inside(_payerSection, find.text('Payer quote rate')), findsOne);
      expect(find.text('63900.00 USD / BTC'), findsOneWidget);
      expect(
        find.text('the live quote when this invoice was read'),
        findsOneWidget,
      );
      // R1 is still the invoice section's own row, and stays distinct.
      expect(find.text('Rate at creation'), findsOneWidget);
      expect(find.text('≈ 64160.00 USD / BTC'), findsOneWidget);
      expect(find.textContaining('executed at'), findsNothing);
    });

    testWidgets('absent payloads render no payer-instructions section', (
      tester,
    ) async {
      // The snapshot default carries no payer instructions at all.
      _registerFacade(_snapshot());

      await _pump(tester, _tx());

      expect(_payerSection, findsNothing);
      expect(find.text('Payer instructions'), findsNothing);
      expect(find.text('Lightning invoice'), findsNothing);
      expect(find.text('Payer quote rails'), findsNothing);
      expect(find.text('Payer quote rate'), findsNothing);
    });
  });

  group('no invoice facts: the card renders exactly as before', () {
    testWidgets('with the invoices facade not registered', (tester) async {
      await _pump(tester, _tx());

      // Only the core-facts section (this entry carries no settlement).
      expect(find.byType(DetailsTable), findsOneWidget);
      expect(
        find.byKey(const ValueKey('get-paid-invoice-section')),
        findsNothing,
      );
      expect(_payerSection, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('when the status read fails', (tester) async {
      final facade = _MockInvoicesFacade();
      when(() => facade.status(any())).thenAnswer(
        (_) async => const Err<InvoiceStatusSnapshot, InvoicesFailure>(
          InvoicesFailure.notFound(),
        ),
      );
      locator.registerSingleton<InvoicesFacade>(facade);

      await _pump(tester, _tx());

      expect(
        find.byKey(const ValueKey('get-paid-invoice-section')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('when the status read throws', (tester) async {
      final facade = _MockInvoicesFacade();
      when(() => facade.status(any())).thenThrow(StateError('boom'));
      locator.registerSingleton<InvoicesFacade>(facade);

      await _pump(tester, _tx());

      expect(
        find.byKey(const ValueKey('get-paid-invoice-section')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('when the entry has no invoice id, the facade is never read', (
      tester,
    ) async {
      final facade = _registerFacade(_snapshot());

      await _pump(
        tester,
        _tx(source: GetPaidTransactionSource.lightningAddress, invoiceId: null),
      );

      verifyNever(() => facade.status(any()));
      expect(
        find.byKey(const ValueKey('get-paid-invoice-section')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
