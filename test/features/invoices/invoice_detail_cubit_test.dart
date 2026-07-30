import 'dart:async';

import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/invoices/presentation/invoice_detail_cubit.dart';
import 'package:bb_mobile/features/invoices/presentation/invoice_detail_state.dart';
import 'package:bb_mobile/features/invoices/public/invoices_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockFacade extends Mock implements InvoicesFacade {}

InvoiceDetailCubit _buildDetailCubit(
  _MockFacade facade, {
  required InvoiceId invoiceId,
  Invoice? invoice,
  Duration pollInitialDelay = const Duration(seconds: 3),
  Duration pollMaxDelay = const Duration(seconds: 30),
  DateTime Function()? now,
}) => InvoiceDetailCubit(
  getPrivateLink: facade.privateLink,
  getStatus: facade.status,
  getMerchantInvoice: facade.merchantInvoice,
  getFallbackSupervision: facade.fallbackSupervision,
  getQuote: facade.quote,
  cancelInvoice: facade.cancel,
  invoiceId: invoiceId,
  invoice: invoice,
  pollInitialDelay: pollInitialDelay,
  pollMaxDelay: pollMaxDelay,
  now: now,
);

InvoiceStatusSnapshot _snapshot(
  InvoiceStatus status, {
  InvoiceSettlementState settlementState = InvoiceSettlementState.none,
  String pricingMode = 'sat_fixed',
  InvoiceQuoteRailAvailability? quoteRailAvailability,
  DateTime? expiresAt,
  bool? acceptingPayments,
}) => InvoiceStatusSnapshot(
  status: status,
  settlementState: settlementState,
  pricingMode: pricingMode,
  settlementStatus: 'pending',
  amountSat: 1000,
  remainingAmountSat: 1000,
  acceptingPayments: acceptingPayments,
  paymentToleranceSat: 0,
  rateLocksUntil: DateTime.utc(2030),
  expiresAt: expiresAt ?? DateTime.utc(2030),
  acceptBtc: false,
  acceptLn: false,
  acceptLiquid: true,
  quoteRailAvailability: quoteRailAvailability,
);

InvoiceQuote _quote(
  DateTime createdAt, {
  int version = 1,
  String pr = 'lnbc1050n1test',
}) => InvoiceQuote(
  invoiceId: InvoiceId('inv-1'),
  versionId: 'quote-$version',
  versionNumber: version,
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
  instruction: InvoiceLightningQuoteInstruction(
    quoteOfferId: 'offer-$version',
    pr: pr,
    amount: InvoicePayerAmount(
      rail: PaymentMethod.lightning,
      merchantTargetAmountSat: 100000,
      payerAmountSat: 105000,
    ),
  ),
);

InvoiceFallbackSupervision _fallback(InvoiceFallbackState state) =>
    InvoiceFallbackSupervision(
      invoiceId: InvoiceId('inv-1'),
      nym: 'merchant',
      state: state,
      payerAmountSat: 105000,
      invoiceSwapAmountSat: 100000,
      lockupAddress: 'bc1plockup',
      transactionId: 'ab' * 32,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026, 1, 2),
    );

Invoice _merchantInvoice({
  required int observedAmountSat,
  required int logicalPaymentCount,
}) => Invoice(
  id: InvoiceId('inv-1'),
  status: InvoiceStatus.paid,
  amountSat: 1000,
  remainingAmountSat: 0,
  acceptingPayments: false,
  paymentSummary: InvoicePaymentSummary(
    observedAmountSat: observedAmountSat,
    creditedAmountSat: 1000,
    remainingAmountSat: 0,
    excessAmountSat: observedAmountSat - 1000,
    logicalPaymentCount: logicalPaymentCount,
    multiplePayments: logicalPaymentCount > 1,
    latePaymentCount: 0,
    hasLatePayment: false,
    firstPaymentAt: DateTime.utc(2026, 1, 1),
    lastPaymentAt: DateTime.utc(2026, 1, logicalPaymentCount),
    acceptingPayments: false,
    topUpAllowed: false,
    requiresMerchantAction: observedAmountSat > 1000,
    attentionReasons: observedAmountSat > 1000
        ? const ['excess_payment']
        : const [],
    fiat: null,
  ),
  acceptBtc: true,
  acceptLn: true,
  acceptLiquid: true,
  createdAt: DateTime.utc(2026),
  expiresAt: DateTime.utc(2026, 2),
);

Invoice _merchantInvoiceWithoutEvidence() => Invoice(
  id: InvoiceId('inv-1'),
  status: InvoiceStatus.unpaid,
  amountSat: 1000,
  remainingAmountSat: 1000,
  acceptingPayments: true,
  acceptBtc: true,
  acceptLn: true,
  acceptLiquid: true,
  createdAt: DateTime.utc(2026),
  expiresAt: DateTime.utc(2030),
);

void main() {
  setUpAll(() {
    registerFallbackValue(InvoiceId('x'));
    registerFallbackValue(CancelInvoiceCommand(invoiceId: InvoiceId('x')));
    registerFallbackValue(PaymentMethod.lightning);
  });

  late _MockFacade facade;

  setUp(() {
    facade = _MockFacade();
    when(() => facade.privateLink(any())).thenAnswer((_) async => null);
    when(() => facade.merchantInvoice(any())).thenAnswer(
      (_) async =>
          Ok<Invoice?, InvoicesFailure>(_merchantInvoiceWithoutEvidence()),
    );
    when(() => facade.fallbackSupervision()).thenAnswer(
      (_) async => const Ok(InvoiceFallbackOverview(items: [], hasMore: false)),
    );
  });

  InvoiceDetailCubit build({
    Duration initial = const Duration(milliseconds: 5),
    Duration? max,
  }) => _buildDetailCubit(
    facade,
    invoiceId: InvoiceId('inv-1'),
    pollInitialDelay: initial,
    pollMaxDelay:
        max ??
        (initial > const Duration(milliseconds: 20)
            ? initial
            : const Duration(milliseconds: 20)),
  );

  test(
    'load fetches the status; a terminal status starts NO poll loop',
    () async {
      when(
        () => facade.status(any()),
      ).thenAnswer((_) async => Ok(_snapshot(InvoiceStatus.paid)));

      final cubit = build();
      await cubit.load();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(cubit.state.status, InvoiceDetailStatus.loaded);
      expect(cubit.state.isTerminal, isTrue);
      verify(() => facade.status(any())).called(1); // no polling after terminal
      await cubit.close();
    },
  );

  test('polls while non-terminal, then STOPS on a terminal status', () async {
    var call = 0;
    when(() => facade.status(any())).thenAnswer((_) async {
      call++;
      return Ok(
        _snapshot(call == 1 ? InvoiceStatus.unpaid : InvoiceStatus.paid),
      );
    });

    final cubit = build();
    await cubit.load();
    await Future<void>.delayed(const Duration(milliseconds: 60));

    // one initial fetch + one poll that observed the terminal status.
    verify(() => facade.status(any())).called(2);
    expect(cubit.state.isTerminal, isTrue);
    await cubit.close();
  });

  test(
    'retrying an initial failure restores polling and initial quote setup',
    () async {
      final now = DateTime.utc(2026, 1, 1, 12);
      var statusCalls = 0;
      when(() => facade.status(any())).thenAnswer((_) async {
        statusCalls++;
        if (statusCalls == 1) {
          return const Err(InvoicesFailure.network());
        }
        return Ok(
          _snapshot(
            statusCalls == 2 ? InvoiceStatus.unpaid : InvoiceStatus.paid,
            pricingMode: 'fiat_fixed',
            expiresAt: now.add(const Duration(days: 30)),
            quoteRailAvailability: const InvoiceQuoteRailAvailability(
              lightning: true,
              liquid: false,
              bitcoin: false,
            ),
          ),
        );
      });
      when(
        () => facade.quote(
          invoiceId: any(named: 'invoiceId'),
          rail: any(named: 'rail'),
        ),
      ).thenAnswer((_) async => Ok(_quote(now)));

      final cubit = _buildDetailCubit(
        facade,
        invoiceId: InvoiceId('inv-1'),
        pollInitialDelay: const Duration(milliseconds: 5),
        pollMaxDelay: const Duration(milliseconds: 20),
        now: () => now,
      );

      await cubit.load();
      expect(cubit.state.status, InvoiceDetailStatus.error);
      verifyNever(
        () => facade.quote(
          invoiceId: any(named: 'invoiceId'),
          rail: any(named: 'rail'),
        ),
      );

      await cubit.load();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(cubit.state.status, InvoiceDetailStatus.loaded);
      expect(cubit.state.isTerminal, isTrue);
      verify(() => facade.status(any())).called(3);
      verify(
        () => facade.quote(
          invoiceId: InvoiceId('inv-1'),
          rail: PaymentMethod.lightning,
        ),
      ).called(1);
      await cubit.close();
    },
  );

  test(
    'refresh replaces authenticated accounting after a repeat payment',
    () async {
      var merchantCalls = 0;
      when(
        () => facade.status(any()),
      ).thenAnswer((_) async => Ok(_snapshot(InvoiceStatus.paid)));
      when(() => facade.merchantInvoice(any())).thenAnswer((_) async {
        merchantCalls++;
        return Ok(
          _merchantInvoice(
            observedAmountSat: merchantCalls == 1 ? 1000 : 2000,
            logicalPaymentCount: merchantCalls == 1 ? 1 : 2,
          ),
        );
      });

      final cubit = build(initial: const Duration(seconds: 30));
      await cubit.load();
      expect(cubit.state.invoice?.paymentSummary?.observedAmountSat, 1000);
      expect(cubit.state.invoice?.paymentSummary?.logicalPaymentCount, 1);

      await cubit.refresh();

      expect(cubit.state.invoice?.paymentSummary?.observedAmountSat, 2000);
      expect(cubit.state.invoice?.paymentSummary?.excessAmountSat, 1000);
      expect(cubit.state.invoice?.paymentSummary?.logicalPaymentCount, 2);
      expect(
        cubit.state.snapshot?.acceptsInitialPayment(DateTime.utc(2026)),
        isFalse,
      );
      await cubit.close();
    },
  );

  test(
    'authenticated refresh failure preserves totals but marks them stale',
    () async {
      var merchantCalls = 0;
      when(
        () => facade.status(any()),
      ).thenAnswer((_) async => Ok(_snapshot(InvoiceStatus.paid)));
      when(() => facade.merchantInvoice(any())).thenAnswer((_) async {
        merchantCalls++;
        if (merchantCalls > 1) {
          return const Err<Invoice?, InvoicesFailure>(
            InvoicesFailure.network(),
          );
        }
        return Ok(
          _merchantInvoice(observedAmountSat: 1000, logicalPaymentCount: 1),
        );
      });

      final cubit = build(initial: const Duration(seconds: 30));
      await cubit.load();
      await cubit.refresh();

      expect(cubit.state.invoice?.paymentSummary?.observedAmountSat, 1000);
      expect(
        cubit.state.authenticatedInvoiceFailure?.kind,
        InvoicesFailureKind.network,
      );
      await cubit.close();
    },
  );

  test(
    'public refresh failure invalidates stale payer actions and quote',
    () async {
      final now = DateTime.utc(2026, 1, 1, 12);
      var statusCalls = 0;
      when(() => facade.status(any())).thenAnswer((_) async {
        statusCalls++;
        if (statusCalls > 1) {
          return const Err(InvoicesFailure.network());
        }
        return Ok(
          _snapshot(
            InvoiceStatus.unpaid,
            pricingMode: 'fiat_fixed',
            acceptingPayments: true,
            expiresAt: now.add(const Duration(days: 1)),
            quoteRailAvailability: const InvoiceQuoteRailAvailability(
              lightning: true,
              liquid: false,
              bitcoin: false,
            ),
          ),
        );
      });
      when(
        () => facade.quote(
          invoiceId: any(named: 'invoiceId'),
          rail: any(named: 'rail'),
        ),
      ).thenAnswer((_) async => Ok(_quote(now)));

      final cubit = _buildDetailCubit(
        facade,
        invoiceId: InvoiceId('inv-1'),
        pollInitialDelay: const Duration(seconds: 30),
        now: () => now,
      );
      await cubit.load();
      expect(cubit.state.quote, isNotNull);
      expect(cubit.state.canCancel, isTrue);

      await cubit.refresh();

      expect(cubit.state.snapshot?.status, InvoiceStatus.unpaid);
      expect(cubit.state.failure?.kind, InvoicesFailureKind.network);
      expect(cubit.state.quote, isNull);
      expect(cubit.state.quoteRefreshing, isFalse);
      expect(cubit.state.canCancel, isFalse);
      expect(cubit.state.acceptsInitialPayment(now), isFalse);
      expect(cubit.canRequestQuote(cubit.state.snapshot!), isFalse);
      await cubit.close();
    },
  );

  test(
    'authenticated evidence closes every stale public payment action',
    () async {
      final now = DateTime.utc(2026, 1, 1, 12);
      var merchantCalls = 0;
      when(() => facade.status(any())).thenAnswer(
        (_) async => Ok(
          _snapshot(
            InvoiceStatus.unpaid,
            pricingMode: 'fiat_fixed',
            acceptingPayments: true,
            expiresAt: now.add(const Duration(days: 1)),
            quoteRailAvailability: const InvoiceQuoteRailAvailability(
              lightning: true,
              liquid: false,
              bitcoin: false,
            ),
          ),
        ),
      );
      when(() => facade.merchantInvoice(any())).thenAnswer((_) async {
        merchantCalls++;
        return Ok(
          merchantCalls == 1
              ? _merchantInvoiceWithoutEvidence()
              : _merchantInvoice(
                  observedAmountSat: 1000,
                  logicalPaymentCount: 1,
                ),
        );
      });
      when(
        () => facade.quote(
          invoiceId: any(named: 'invoiceId'),
          rail: any(named: 'rail'),
        ),
      ).thenAnswer((_) async => Ok(_quote(now)));

      final cubit = _buildDetailCubit(
        facade,
        invoiceId: InvoiceId('inv-1'),
        pollInitialDelay: const Duration(seconds: 30),
        now: () => now,
      );
      await cubit.load();
      expect(cubit.state.quote, isNotNull);
      expect(cubit.state.canCancel, isTrue);

      await cubit.refresh();

      expect(cubit.state.quote, isNull);
      expect(cubit.state.hasAuthenticatedPaymentEvidence, isTrue);
      expect(cubit.state.canCancel, isFalse);
      expect(cubit.canRequestQuote(cubit.state.snapshot!), isFalse);
      await cubit.close();
    },
  );

  test(
    'public payment evidence closes actions before authentication completes',
    () async {
      final now = DateTime.utc(2026, 1, 1, 12);
      final delayedAuthentication =
          Completer<Result<Invoice?, InvoicesFailure>>();
      var statusCalls = 0;
      var authenticatedCalls = 0;
      when(() => facade.status(any())).thenAnswer((_) async {
        statusCalls++;
        return Ok(
          _snapshot(
            statusCalls == 1 ? InvoiceStatus.unpaid : InvoiceStatus.paid,
            pricingMode: 'fiat_fixed',
            acceptingPayments: statusCalls == 1,
            expiresAt: now.add(const Duration(days: 1)),
            quoteRailAvailability: const InvoiceQuoteRailAvailability(
              lightning: true,
              liquid: false,
              bitcoin: false,
            ),
          ),
        );
      });
      when(() => facade.merchantInvoice(any())).thenAnswer((_) {
        authenticatedCalls++;
        if (authenticatedCalls == 1) {
          return Future.value(
            Ok<Invoice?, InvoicesFailure>(_merchantInvoiceWithoutEvidence()),
          );
        }
        return delayedAuthentication.future;
      });
      when(
        () => facade.quote(
          invoiceId: any(named: 'invoiceId'),
          rail: any(named: 'rail'),
        ),
      ).thenAnswer((_) async => Ok(_quote(now)));

      final cubit = _buildDetailCubit(
        facade,
        invoiceId: InvoiceId('inv-1'),
        pollInitialDelay: const Duration(seconds: 30),
        now: () => now,
      );
      await cubit.load();
      expect(cubit.state.quote, isNotNull);
      expect(cubit.state.canCancel, isTrue);

      final refresh = cubit.refresh();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.snapshot?.status, InvoiceStatus.paid);
      expect(cubit.state.quote, isNull);
      expect(cubit.state.canCancel, isFalse);
      expect(cubit.canRequestQuote(cubit.state.snapshot!), isFalse);

      delayedAuthentication.complete(
        Ok(_merchantInvoice(observedAmountSat: 1000, logicalPaymentCount: 1)),
      );
      await refresh;
      await cubit.close();
    },
  );

  test(
    'authenticated evidence closes actions before public status completes',
    () async {
      final now = DateTime.utc(2026, 1, 1, 12);
      final delayedPublicStatus =
          Completer<Result<InvoiceStatusSnapshot, InvoicesFailure>>();
      var statusCalls = 0;
      var authenticatedCalls = 0;
      final unpaid = _snapshot(
        InvoiceStatus.unpaid,
        pricingMode: 'fiat_fixed',
        acceptingPayments: true,
        expiresAt: now.add(const Duration(days: 1)),
        quoteRailAvailability: const InvoiceQuoteRailAvailability(
          lightning: true,
          liquid: false,
          bitcoin: false,
        ),
      );
      when(() => facade.status(any())).thenAnswer((_) {
        statusCalls++;
        return statusCalls == 1
            ? Future.value(Ok(unpaid))
            : delayedPublicStatus.future;
      });
      when(() => facade.merchantInvoice(any())).thenAnswer((_) async {
        authenticatedCalls++;
        return Ok(
          authenticatedCalls == 1
              ? _merchantInvoiceWithoutEvidence()
              : _merchantInvoice(
                  observedAmountSat: 1000,
                  logicalPaymentCount: 1,
                ),
        );
      });
      when(
        () => facade.quote(
          invoiceId: any(named: 'invoiceId'),
          rail: any(named: 'rail'),
        ),
      ).thenAnswer((_) async => Ok(_quote(now)));

      final cubit = _buildDetailCubit(
        facade,
        invoiceId: InvoiceId('inv-1'),
        pollInitialDelay: const Duration(seconds: 30),
        now: () => now,
      );
      await cubit.load();
      expect(cubit.state.quote, isNotNull);

      final refresh = cubit.refresh();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.hasAuthenticatedPaymentEvidence, isTrue);
      expect(cubit.state.quote, isNull);
      expect(cubit.state.canCancel, isFalse);
      expect(cubit.canRequestQuote(cubit.state.snapshot!), isFalse);

      delayedPublicStatus.complete(Ok(unpaid));
      await refresh;
      expect(cubit.state.quote, isNull);
      expect(cubit.state.canCancel, isFalse);
      await cubit.close();
    },
  );

  test(
    'an older overlapping refresh cannot replace newer accounting',
    () async {
      final statusFirst =
          Completer<Result<InvoiceStatusSnapshot, InvoicesFailure>>();
      final statusSecond =
          Completer<Result<InvoiceStatusSnapshot, InvoicesFailure>>();
      final authFirst = Completer<Result<Invoice?, InvoicesFailure>>();
      final authSecond = Completer<Result<Invoice?, InvoicesFailure>>();
      var statusCalls = 0;
      var authCalls = 0;
      when(() => facade.status(any())).thenAnswer((_) {
        statusCalls++;
        return statusCalls == 1 ? statusFirst.future : statusSecond.future;
      });
      when(() => facade.merchantInvoice(any())).thenAnswer((_) {
        authCalls++;
        return authCalls == 1 ? authFirst.future : authSecond.future;
      });

      final cubit = build(initial: const Duration(seconds: 30));
      final older = cubit.refresh();
      await Future<void>.delayed(Duration.zero);
      final newer = cubit.refresh();
      await Future<void>.delayed(Duration.zero);

      statusSecond.complete(Ok(_snapshot(InvoiceStatus.paid)));
      authSecond.complete(
        Ok(_merchantInvoice(observedAmountSat: 2000, logicalPaymentCount: 2)),
      );
      await newer;
      statusFirst.complete(Ok(_snapshot(InvoiceStatus.paid)));
      authFirst.complete(
        Ok(_merchantInvoice(observedAmountSat: 1000, logicalPaymentCount: 1)),
      );
      await older;

      expect(cubit.state.invoice?.paymentSummary?.observedAmountSat, 2000);
      expect(cubit.state.invoice?.paymentSummary?.logicalPaymentCount, 2);
      await cubit.close();
    },
  );

  test(
    'terminal public state keeps polling until accounting recovers',
    () async {
      var merchantCalls = 0;
      when(
        () => facade.status(any()),
      ).thenAnswer((_) async => Ok(_snapshot(InvoiceStatus.paid)));
      when(() => facade.merchantInvoice(any())).thenAnswer((_) async {
        merchantCalls++;
        if (merchantCalls == 1) {
          return const Err<Invoice?, InvoicesFailure>(
            InvoicesFailure.network(),
          );
        }
        return Ok(
          _merchantInvoice(observedAmountSat: 1000, logicalPaymentCount: 1),
        );
      });

      final cubit = build(initial: const Duration(milliseconds: 5));
      await cubit.load();
      expect(cubit.state.isTerminal, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(merchantCalls, greaterThanOrEqualTo(2));
      expect(cubit.state.authenticatedInvoiceFailure, isNull);
      expect(cubit.state.invoice?.paymentSummary?.observedAmountSat, 1000);
      expect(cubit.state.isTerminal, isTrue);
      await cubit.close();
    },
  );

  test('a paid invoice keeps polling until settlement becomes final', () async {
    var call = 0;
    when(() => facade.status(any())).thenAnswer((_) async {
      call++;
      return Ok(
        _snapshot(
          InvoiceStatus.paid,
          settlementState: call == 1
              ? InvoiceSettlementState.pending
              : InvoiceSettlementState.settled,
        ),
      );
    });

    final cubit = build();
    await cubit.load();
    expect(cubit.state.isTerminal, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    verify(() => facade.status(any())).called(2);
    expect(cubit.state.isTerminal, isTrue);
    await cubit.close();
  });

  test('a settlement problem remains supervised', () async {
    when(() => facade.status(any())).thenAnswer(
      (_) async => Ok(
        _snapshot(
          InvoiceStatus.paid,
          settlementState: InvoiceSettlementState.problem,
        ),
      ),
    );

    final cubit = build(initial: const Duration(seconds: 30));
    await cubit.load();

    expect(cubit.state.isTerminal, isFalse);
    await cubit.close();
  });

  test('a terminal invoice keeps polling while fallback confirms', () async {
    var statusCalls = 0;
    when(() => facade.status(any())).thenAnswer((_) async {
      statusCalls++;
      return Ok(_snapshot(InvoiceStatus.paid));
    });
    when(() => facade.fallbackSupervision()).thenAnswer(
      (_) async => Ok(
        InvoiceFallbackOverview(
          items: [_fallback(InvoiceFallbackState.confirming)],
          hasMore: false,
        ),
      ),
    );

    final cubit = build();
    await cubit.load();
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(cubit.state.isTerminal, isFalse);
    expect(statusCalls, greaterThan(1));
    await cubit.close();
  });

  test(
    'a transient supervision failure keeps terminal polling alive',
    () async {
      when(
        () => facade.status(any()),
      ).thenAnswer((_) async => Ok(_snapshot(InvoiceStatus.paid)));
      when(
        () => facade.fallbackSupervision(),
      ).thenAnswer((_) async => const Err(InvoicesFailure.network()));

      final cubit = build(initial: const Duration(milliseconds: 5));
      await cubit.load();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(cubit.state.status, InvoiceDetailStatus.loaded);
      expect(cubit.state.snapshot, isNotNull);
      expect(
        cubit.state.fallbackSupervisionFailure?.kind,
        InvoicesFailureKind.network,
      );
      expect(cubit.state.isTerminal, isFalse);
      verify(() => facade.status(any())).called(greaterThan(1));
      await cubit.close();
    },
  );

  test(
    'sub-second polling backs off without collapsing to a zero-delay loop',
    () async {
      var statusCalls = 0;
      when(() => facade.status(any())).thenAnswer((_) async {
        statusCalls++;
        return Ok(_snapshot(InvoiceStatus.unpaid));
      });

      final cubit = build();
      await cubit.load();
      await Future<void>.delayed(const Duration(milliseconds: 42));

      expect(statusCalls, inInclusiveRange(3, 5));
      await cubit.close();
    },
  );

  test('dispose stops the poll loop (no post-dispose fetch)', () async {
    when(
      () => facade.status(any()),
    ).thenAnswer((_) async => Ok(_snapshot(InvoiceStatus.unpaid)));

    final cubit = build();
    await cubit.load(); // initial fetch (1), poll scheduled for +5ms
    await cubit.close(); // invalidate before the poll fires
    await Future<void>.delayed(const Duration(milliseconds: 40));

    verify(() => facade.status(any())).called(1);
  });

  test(
    'cancel stores the final status SEPARATELY from the polled snapshot',
    () async {
      when(
        () => facade.status(any()),
      ).thenAnswer((_) async => Ok(_snapshot(InvoiceStatus.unpaid)));
      when(() => facade.cancel(any())).thenAnswer(
        (_) async => Ok(
          CancelInvoiceResult(
            invoiceId: InvoiceId('inv-1'),
            finalStatus: InvoiceStatus.cancelled,
          ),
        ),
      );

      // A long poll delay keeps the loop from interfering with the assertions.
      final cubit = build(initial: const Duration(seconds: 30));
      await cubit.load();
      expect(cubit.state.canCancel, isTrue); // unpaid → cancellable (DG-I5)

      await cubit.cancel();

      expect(cubit.state.cancelFinalStatus, InvoiceStatus.cancelled);
      // The snapshot is NOT overwritten by the cancel result (§3.11)...
      expect(cubit.state.snapshot?.status, InvoiceStatus.unpaid);
      // ...but the effective status reflects the settled cancel.
      expect(cubit.state.effectiveStatus, InvoiceStatus.cancelled);
      expect(cubit.state.canCancel, isFalse);
      await cubit.close();
    },
  );

  test(
    'cancel does not stop settlement polling before status completion',
    () async {
      var statusCalls = 0;
      when(() => facade.status(any())).thenAnswer((_) async {
        statusCalls++;
        return Ok(_snapshot(InvoiceStatus.unpaid));
      });
      when(() => facade.cancel(any())).thenAnswer(
        (_) async => Ok(
          CancelInvoiceResult(
            invoiceId: InvoiceId('inv-1'),
            finalStatus: InvoiceStatus.cancelled,
          ),
        ),
      );

      final cubit = build(initial: const Duration(milliseconds: 5));
      await cubit.load();
      await cubit.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(cubit.state.cancelFinalStatus, InvoiceStatus.cancelled);
      expect(cubit.state.isTerminal, isFalse);
      expect(statusCalls, greaterThan(2));
      await cubit.close();
    },
  );

  test('fiat detail explicitly loads the first available quote rail', () async {
    final now = DateTime.utc(2026, 1, 1, 12);
    when(() => facade.status(any())).thenAnswer(
      (_) async => Ok(
        _snapshot(
          InvoiceStatus.unpaid,
          pricingMode: 'fiat_fixed',
          expiresAt: now.add(const Duration(days: 30)),
          quoteRailAvailability: const InvoiceQuoteRailAvailability(
            lightning: true,
            liquid: true,
            bitcoin: true,
          ),
        ),
      ),
    );
    when(
      () => facade.quote(
        invoiceId: any(named: 'invoiceId'),
        rail: any(named: 'rail'),
      ),
    ).thenAnswer((_) async => Ok(_quote(now)));

    final cubit = _buildDetailCubit(
      facade,
      invoiceId: InvoiceId('inv-1'),
      pollInitialDelay: const Duration(seconds: 30),
      now: () => now,
    );
    await cubit.load();

    expect(cubit.state.selectedQuoteRail, PaymentMethod.lightning);
    expect(cubit.state.quote?.versionId, 'quote-1');
    expect(cubit.state.hasUsableQuote(now), isTrue);
    verify(
      () => facade.quote(
        invoiceId: InvoiceId('inv-1'),
        rail: PaymentMethod.lightning,
      ),
    ).called(1);
    await cubit.close();
  });

  test('expiry clears every old payload before replacement resolves', () async {
    var now = DateTime.utc(2026, 1, 1, 12);
    final first = _quote(now);
    final replacement = Completer<Result<InvoiceQuote, InvoicesFailure>>();
    var quoteCalls = 0;
    when(() => facade.status(any())).thenAnswer(
      (_) async => Ok(
        _snapshot(
          InvoiceStatus.unpaid,
          pricingMode: 'fiat_fixed',
          expiresAt: now.add(const Duration(days: 30)),
          quoteRailAvailability: const InvoiceQuoteRailAvailability(
            lightning: true,
            liquid: false,
            bitcoin: false,
          ),
        ),
      ),
    );
    when(
      () => facade.quote(
        invoiceId: any(named: 'invoiceId'),
        rail: any(named: 'rail'),
      ),
    ).thenAnswer((_) {
      quoteCalls++;
      return quoteCalls == 1 ? Future.value(Ok(first)) : replacement.future;
    });

    final cubit = _buildDetailCubit(
      facade,
      invoiceId: InvoiceId('inv-1'),
      pollInitialDelay: const Duration(seconds: 30),
      now: () => now,
    );
    await cubit.load();
    expect(cubit.state.quote?.instruction.copyPayload, 'lnbc1050n1test');

    now = first.expiresAt;
    cubit.quoteExpired();

    expect(cubit.state.quote, isNull);
    expect(cubit.state.quoteRefreshing, isTrue);
    expect(cubit.state.hasUsableQuote(now), isFalse);

    replacement.complete(Ok(_quote(now, version: 2)));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.quoteRefreshing, isFalse);
    expect(cubit.state.quote?.versionId, 'quote-2');
    expect(cubit.state.hasUsableQuote(now), isTrue);
    await cubit.close();
  });

  test('same quote version cannot change its instruction in place', () async {
    final now = DateTime.utc(2026, 1, 1, 12);
    var quoteCalls = 0;
    when(() => facade.status(any())).thenAnswer(
      (_) async => Ok(
        _snapshot(
          InvoiceStatus.unpaid,
          pricingMode: 'fiat_fixed',
          expiresAt: now.add(const Duration(days: 30)),
          quoteRailAvailability: const InvoiceQuoteRailAvailability(
            lightning: true,
            liquid: false,
            bitcoin: false,
          ),
        ),
      ),
    );
    when(
      () => facade.quote(
        invoiceId: any(named: 'invoiceId'),
        rail: any(named: 'rail'),
      ),
    ).thenAnswer((_) async {
      quoteCalls++;
      return Ok(
        _quote(
          now,
          pr: quoteCalls == 1 ? 'lnbc1050n1test' : 'lnbcchanged1test',
        ),
      );
    });

    final cubit = _buildDetailCubit(
      facade,
      invoiceId: InvoiceId('inv-1'),
      pollInitialDelay: const Duration(seconds: 30),
      now: () => now,
    );
    await cubit.load();
    await cubit.refreshQuote(PaymentMethod.lightning);

    expect(cubit.state.quote, isNull);
    expect(
      cubit.state.quoteFailure?.kind,
      InvoicesFailureKind.invalidServerResponse,
    );
    await cubit.close();
  });

  test('payment evidence invalidates an in-flight payer quote', () async {
    final now = DateTime.utc(2026, 1, 1, 12);
    var statusCalls = 0;
    final quoteResult = Completer<Result<InvoiceQuote, InvoicesFailure>>();
    when(() => facade.status(any())).thenAnswer((_) async {
      statusCalls++;
      return Ok(
        _snapshot(
          statusCalls == 1 ? InvoiceStatus.unpaid : InvoiceStatus.inProgress,
          pricingMode: 'fiat_fixed',
          acceptingPayments: true,
          expiresAt: now.add(const Duration(days: 30)),
          quoteRailAvailability: const InvoiceQuoteRailAvailability(
            lightning: true,
            liquid: false,
            bitcoin: false,
          ),
        ),
      );
    });
    when(
      () => facade.quote(
        invoiceId: any(named: 'invoiceId'),
        rail: any(named: 'rail'),
      ),
    ).thenAnswer((_) => quoteResult.future);

    final cubit = _buildDetailCubit(
      facade,
      invoiceId: InvoiceId('inv-1'),
      pollInitialDelay: const Duration(seconds: 30),
      now: () => now,
    );
    final load = cubit.load();
    await Future<void>.delayed(Duration.zero);
    await cubit.refresh();

    expect(cubit.state.snapshot?.hasPaymentEvidence, isTrue);
    expect(cubit.state.quote, isNull);
    expect(cubit.state.canCancel, isFalse);

    quoteResult.complete(Ok(_quote(now)));
    await load;
    expect(cubit.state.quote, isNull);
    await cubit.close();
  });

  test('cancel is inert once a final status exists', () async {
    when(
      () => facade.status(any()),
    ).thenAnswer((_) async => Ok(_snapshot(InvoiceStatus.unpaid)));
    when(() => facade.cancel(any())).thenAnswer(
      (_) async => Ok(
        CancelInvoiceResult(
          invoiceId: InvoiceId('inv-1'),
          finalStatus: InvoiceStatus.cancelled,
        ),
      ),
    );

    final cubit = build(initial: const Duration(seconds: 30));
    await cubit.load();
    await cubit.cancel();
    await cubit.cancel(); // canCancel is now false → inert

    verify(() => facade.cancel(any())).called(1);
    await cubit.close();
  });
}
