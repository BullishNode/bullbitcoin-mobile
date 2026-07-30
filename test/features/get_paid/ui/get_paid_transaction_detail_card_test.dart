import 'dart:async';

import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/utils/string_formatting.dart';
import 'package:bb_mobile/core/widgets/tables/details_table.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_settlement.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_transaction.dart';
import 'package:bb_mobile/features/get_paid/domain/look_up_get_paid_invoice_facts_usecase.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_invoice_facts_cubit.dart';
import 'package:bb_mobile/features/get_paid/ui/screens/get_paid_transaction_detail_screen.dart';
import 'package:bb_mobile/features/invoices/public/invoices_facade.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
  bool? acceptingPayments,
  DateTime? expiresAt,
}) => InvoiceStatusSnapshot(
  status: status,
  settlementState: settlementState,
  pricingMode: pricingMode,
  settlementStatus: 'settled',
  amountSat: amountSat,
  fiatAmountMinor: fiatAmountMinor,
  fiatCurrency: fiatCurrency,
  remainingAmountSat: remainingAmountSat,
  acceptingPayments: acceptingPayments,
  paymentToleranceSat: paymentToleranceSat,
  creationRateMinorPerBtc: creationRateMinorPerBtc,
  rateMinorPerBtc: rateMinorPerBtc,
  rateLocksUntil: DateTime.utc(2026, 7, 18, 12, 5),
  expiresAt: expiresAt ?? DateTime.utc(2026, 7, 25, 12),
  paidVia: paidAmountSat == null ? null : PaymentMethod.lightning,
  paidAt: paidAmountSat == null ? null : DateTime.utc(2026, 7, 18, 11, 59),
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

Invoice _merchantInvoiceWithRepeatPayment() => Invoice(
  id: InvoiceId(_invoiceId),
  status: InvoiceStatus.overpaid,
  amountSat: 5000,
  remainingAmountSat: 0,
  acceptingPayments: false,
  paymentSummary: InvoicePaymentSummary(
    observedAmountSat: 6000,
    creditedAmountSat: 5000,
    remainingAmountSat: 0,
    excessAmountSat: 1000,
    logicalPaymentCount: 2,
    multiplePayments: true,
    latePaymentCount: 0,
    hasLatePayment: false,
    firstPaymentAt: DateTime.utc(2026, 7, 18, 11, 58),
    lastPaymentAt: DateTime.utc(2026, 7, 18, 12),
    acceptingPayments: false,
    topUpAllowed: false,
    requiresMerchantAction: true,
    attentionReasons: const ['excess_payment'],
    fiat: null,
  ),
  acceptBtc: true,
  acceptLn: true,
  acceptLiquid: true,
  createdAt: DateTime.utc(2026, 7, 18),
  expiresAt: DateTime.utc(2026, 7, 25),
);

Widget _app(Widget home) => MaterialApp(
  theme: AppTheme.themeData(AppThemeType.light),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: home,
);

/// The invoices boundary a test opted into, if any. Null means no invoice read
/// is wired at all, so the cubit stays initial — the card then renders exactly as
/// it does for an entry that carries no invoice.
InvoicesFacade? _invoices;

Future<void> _pump(
  WidgetTester tester,
  GetPaidTransaction transaction, {
  bool settle = true,
}) async {
  // A tall surface so every section of the scrolling card is built and findable.
  await tester.binding.setSurfaceSize(const Size(1000, 4000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final invoices = _invoices;
  await tester.pumpWidget(
    _app(
      BlocProvider(
        create: (_) {
          final cubit = GetPaidInvoiceFactsCubit(
            lookUpInvoiceFacts: LookUpGetPaidInvoiceFactsUsecase(
              invoices: invoices ?? _MockInvoicesFacade(),
            ),
          );
          if (invoices != null) {
            cubit.load(
              invoiceId: transaction.invoiceId,
              authenticatedPaymentEvidence: transaction.isInvoiceBacked,
            );
          }
          return cubit;
        },
        child: GetPaidTransactionDetailScreen(transaction: transaction),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

/// Wires a facade whose status read returns [snapshot]. The next [_pump] builds
/// the card's cubit over it through the same constructor production uses.
_MockInvoicesFacade _registerFacade(InvoiceStatusSnapshot snapshot) {
  final facade = _MockInvoicesFacade();
  when(
    () => facade.merchantInvoice(any()),
  ).thenAnswer((_) async => const Ok<Invoice?, InvoicesFailure>(null));
  when(() => facade.status(any())).thenAnswer(
    (_) async => Ok<InvoiceStatusSnapshot, InvoicesFailure>(snapshot),
  );
  _registerInvoiceFacts(facade);
  return facade;
}

void _registerInvoiceFacts(InvoicesFacade facade) => _invoices = facade;

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
  tearDown(() => _invoices = null);

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
      _registerFacade(
        _snapshot(
          status: InvoiceStatus.unpaid,
          settlementState: InvoiceSettlementState.none,
          paidAmountSat: null,
          acceptingPayments: true,
          expiresAt: DateTime.utc(2030),
          lightningPr: _lightningPr,
        ),
      );

      await _pump(tester, _tx(settlement: _mixed()));

      for (final title in const ['Details', 'Settlement']) {
        expect(find.text(title), findsOneWidget);
      }
      // "Invoice" twice: the Source row's value and the invoice section title.
      expect(find.text('Invoice'), findsNWidgets(2));
      expect(find.byType(DetailsTable), findsNWidgets(3));
      expect(find.text('Payer instructions'), findsNothing);
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
      expect(find.text('Difference from requested'), findsOneWidget);
      expect(find.text('1,000 sats'), findsOneWidget);
      // The headline stays this entry's own amount.
      expect(find.text('2,100 sats'), findsOneWidget);
    });

    testWidgets('authenticated repeat-payment accounting is rendered', (
      tester,
    ) async {
      final facade = _registerFacade(
        _snapshot(
          amountSat: 5000,
          fiatAmountMinor: null,
          fiatCurrency: null,
          pricingMode: 'sat_fixed',
          paidAmountSat: 5000,
        ),
      );
      when(() => facade.merchantInvoice(any())).thenAnswer(
        (_) async =>
            Ok<Invoice?, InvoicesFailure>(_merchantInvoiceWithRepeatPayment()),
      );

      await _pump(tester, _tx());

      expect(find.text('Amount paid'), findsOneWidget);
      expect(find.text('6,000 sats'), findsOneWidget);
      expect(find.text('Overpaid by'), findsOneWidget);
      expect(find.text('1,000 sats'), findsOneWidget);
      expect(find.text('Payments observed'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
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

  InvoiceStatusSnapshot withStaleInstructions({int remainingAmountSat = 0}) =>
      _snapshot(
        status: InvoiceStatus.unpaid,
        settlementState: InvoiceSettlementState.none,
        paidAmountSat: null,
        remainingAmountSat: remainingAmountSat,
        acceptingPayments: true,
        expiresAt: DateTime.utc(2030),
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

  group('the payer-instructions section', () {
    testWidgets(
      'an authenticated receipt never revives stale payer instructions',
      (tester) async {
        _registerFacade(withStaleInstructions());

        await _pump(tester, _tx());

        expect(_payerSection, findsNothing);
        expect(find.text('Payer instructions'), findsNothing);
        expect(find.text(_lightningPr), findsNothing);
        expect(find.text('Lightning invoice'), findsNothing);
      },
    );
  });

  group('authenticated accounting availability', () {
    testWidgets(
      'an authenticated error closes stale public admission and stays visible',
      (tester) async {
        final facade = _registerFacade(
          withStaleInstructions(remainingAmountSat: 5000),
        );
        when(() => facade.merchantInvoice(any())).thenAnswer(
          (_) async =>
              const Err<Invoice?, InvoicesFailure>(InvoicesFailure.network()),
        );

        await _pump(tester, _tx());

        expect(
          find.byKey(const ValueKey('get-paid-invoice-section')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('get-paid-payment-summary-unavailable')),
          findsOneWidget,
        );
        expect(
          find.text('Detailed payment accounting is unavailable.'),
          findsOneWidget,
        );
        expect(_payerSection, findsNothing);
        expect(find.text('Lightning invoice'), findsNothing);
        expect(find.text('Difference from requested'), findsNothing);
      },
    );

    testWidgets(
      'a missing authenticated row closes stale admission and is unavailable',
      (tester) async {
        _registerFacade(withStaleInstructions());

        await _pump(tester, _tx());

        expect(
          find.byKey(const ValueKey('get-paid-invoice-section')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('get-paid-payment-summary-unavailable')),
          findsOneWidget,
        );
        expect(_payerSection, findsNothing);
        expect(find.text('Lightning invoice'), findsNothing);
      },
    );
  });

  group('no invoice facts: the card renders exactly as before', () {
    testWidgets('with no invoice read wired at all', (tester) async {
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

    testWidgets('a rejected status read is STATED, not hidden', (tester) async {
      final facade = _MockInvoicesFacade();
      when(
        () => facade.merchantInvoice(any()),
      ).thenAnswer((_) async => const Ok<Invoice?, InvoicesFailure>(null));
      when(() => facade.status(any())).thenAnswer(
        (_) async => const Err<InvoiceStatusSnapshot, InvoicesFailure>(
          InvoicesFailure.notFound(),
        ),
      );
      _registerInvoiceFacts(facade);

      await _pump(tester, _tx());

      // An entry that HAS an invoice must never read as invoice-less: the
      // section stays and says the state could not be read.
      final section = find.byKey(const ValueKey('get-paid-invoice-section'));
      expect(section, findsOneWidget);
      expect(
        _inside(section, find.text('Invoice details unavailable')),
        findsOneWidget,
      );
      expect(_inside(section, find.text('Retry')), findsOneWidget);
      // No half-rendered invoice facts alongside the notice.
      expect(_eventSection, findsNothing);
      expect(_payerSection, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an invoice read shows progress and recovers through Retry', (
      tester,
    ) async {
      final first = Completer<Result<InvoiceStatusSnapshot, InvoicesFailure>>();
      final facade = _MockInvoicesFacade();
      when(
        () => facade.merchantInvoice(any()),
      ).thenAnswer((_) async => const Ok<Invoice?, InvoicesFailure>(null));
      var calls = 0;
      when(() => facade.status(any())).thenAnswer((_) {
        calls++;
        if (calls == 1) return first.future;
        return Future.value(
          Ok<InvoiceStatusSnapshot, InvoicesFailure>(_snapshot()),
        );
      });
      _registerInvoiceFacts(facade);

      await _pump(tester, _tx(), settle: false);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      first.complete(
        const Err<InvoiceStatusSnapshot, InvoicesFailure>(
          InvoicesFailure.network(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Invoice details unavailable'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(find.text('Invoice details unavailable'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a thrown status read is STATED, not hidden', (tester) async {
      final facade = _MockInvoicesFacade();
      // An operational throw (a programming Error stays visible by design).
      when(() => facade.status(any())).thenThrow(Exception('boom'));
      _registerInvoiceFacts(facade);

      await _pump(tester, _tx());

      final section = find.byKey(const ValueKey('get-paid-invoice-section'));
      expect(section, findsOneWidget);
      expect(
        _inside(section, find.text('Invoice details unavailable')),
        findsOneWidget,
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

  testWidgets('a loaded receipt offers read-only pull-to-refresh', (
    tester,
  ) async {
    _registerFacade(_snapshot());

    await _pump(tester, _tx());

    expect(find.byType(RefreshIndicator), findsOneWidget);
  });
}
