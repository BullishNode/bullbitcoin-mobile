import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/core/utils/amount_formatting.dart';
import 'package:bb_mobile/core/utils/string_formatting.dart';
import 'package:bb_mobile/core/widgets/tables/details_table.dart';
import 'package:bb_mobile/core/widgets/tables/details_table_item.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_creation_rate.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_invoice_facts.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_settlement.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_transaction.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_invoice_facts_cubit.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_invoice_facts_state.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_transaction_detail_cubit.dart';
import 'package:bb_mobile/features/get_paid/ui/screens/get_paid_transaction_history_screen.dart';
import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// The detail screen for a Get Paid receipt. Invoice-backed receipts merge the available invoice state and history into this card; Lightning Address receipts have no invoice section. The screen never links out to a second invoice screen.
///
/// Organised, not redundant: each fact appears exactly once in the section it belongs to.
class GetPaidTransactionDetailScreen extends StatelessWidget {
  const GetPaidTransactionDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final detail = context.watch<GetPaidTransactionDetailCubit>().state;
    final transaction = detail.transaction;
    final invoiceFacts = context.watch<GetPaidInvoiceFactsCubit>().state;
    final invoice = invoiceFacts is GetPaidInvoiceFactsData
        ? invoiceFacts.invoice
        : null;
    return BullScaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            BullTopBar(
              title: context.loc.getPaidTransactionDetailTitle,
              onBack: context.pop,
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await Future.wait([
                    context.read<GetPaidTransactionDetailCubit>().refresh(),
                    context.read<GetPaidInvoiceFactsCubit>().retry(),
                  ]);
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (detail.refreshFailed)
                      _refreshNotice(
                        context,
                        key: const ValueKey('get-paid-receipt-refresh-failed'),
                        text: context.loc.invoicePaymentSummaryStale,
                      ),
                    if (invoiceFacts is GetPaidInvoiceFactsData &&
                        invoiceFacts.refreshFailed)
                      _refreshNotice(
                        context,
                        key: const ValueKey('get-paid-invoice-refresh-failed'),
                        text: context.loc.invoiceDetailRefreshFailed,
                      ),
                    Text(
                      getPaidTransactionAmountText(
                        context,
                        transaction.amountSat,
                      ),
                      textAlign: TextAlign.center,
                      style: context.bullText.headlineLarge,
                    ),
                    // The entry's own facts.
                    ..._section(
                      context,
                      title: context.loc.getPaidCardDetailsSectionTitle,
                      sectionKey: const ValueKey('get-paid-core-facts-section'),
                      rows: _coreFactRows(context, transaction),
                    ),
                    // The private, merchant-only settlement breakdown.
                    ..._section(
                      context,
                      title: context.loc.getPaidCardSettlementSectionTitle,
                      sectionKey: const ValueKey('get-paid-settlement-section'),
                      rows: _settlementRows(context, transaction.settlement),
                    ),
                    // The invoice's own state, merged into this card rather than hidden behind a second screen. A failed read states itself in the section's own place, mirroring how an uninterpretable settlement says so.
                    ..._section(
                      context,
                      title: context.loc.invoiceDetailTitle,
                      sectionKey: const ValueKey('get-paid-invoice-section'),
                      rows: invoice == null
                          ? _invoiceStatusRows(
                              context,
                              invoiceFacts,
                              transaction.invoiceId,
                            )
                          : _invoiceRows(context, invoice, transaction),
                    ),
                    if (invoice != null &&
                        invoice.shouldShowPaymentSummaryUnavailable)
                      Padding(
                        key: const ValueKey(
                          'get-paid-payment-summary-unavailable',
                        ),
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          context.loc.invoicePaymentSummaryUnavailable,
                          style: context.bullText.bodyMedium?.copyWith(
                            color: context.bull.textMuted,
                          ),
                        ),
                      ),
                    // Everything that happened, one compact row per observation.
                    ..._section(
                      context,
                      title: context.loc.invoicePaymentHistoryTitle,
                      sectionKey: const ValueKey(
                        'get-paid-invoice-payment-events',
                      ),
                      rows: invoice == null
                          ? const []
                          : _paymentEventRows(context, invoice.paymentEvents),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _refreshNotice(
  BuildContext context, {
  required Key key,
  required String text,
}) {
  return Padding(
    key: key,
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 18, color: context.bull.textMuted),
        const Gap(8),
        Expanded(
          child: Text(
            text,
            style: context.bullText.bodySmall?.copyWith(
              color: context.bull.textMuted,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The invoice section without a snapshot. An entry without an invoice stays absent, while an in-flight or failed authenticated read remains visible and retryable instead of making the invoice-backed card look incomplete.
List<DetailsTableItem> _invoiceStatusRows(
  BuildContext context,
  GetPaidInvoiceFactsState state,
  String? invoiceId,
) {
  return switch (state) {
    GetPaidInvoiceFactsLoading() => [
      DetailsTableItem(
        label: context.loc.invoiceDetailTitle,
        displayWidget: Semantics(
          liveRegion: true,
          label: context.loc.getPaidCardInvoiceDetailsLoading,
          child: const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    ],
    GetPaidInvoiceFactsFailure() when invoiceId != null => [
      DetailsTableItem(
        label: context.loc.invoiceDetailTitle,
        displayWidget: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              context.loc.getPaidCardInvoiceDetailsUnavailable,
              textAlign: TextAlign.end,
            ),
            TextButton(
              onPressed: context.read<GetPaidInvoiceFactsCubit>().retry,
              child: Text(context.loc.retry),
            ),
          ],
        ),
      ),
    ],
    _ => const [],
  };
}

/// A titled section of the card: a muted title above its own details table. A section with no rows renders nothing at all — never a header over nothing.
List<Widget> _section(
  BuildContext context, {
  required String title,
  required Key sectionKey,
  required List<DetailsTableItem> rows,
}) {
  if (rows.isEmpty) return const [];
  return [
    const Gap(24),
    Text(
      title,
      style: context.bullText.titleMedium?.copyWith(
        color: context.bull.textMuted,
      ),
    ),
    const Gap(8),
    DetailsTable(key: sectionKey, items: rows),
  ];
}

/// The entry's own facts, in merchant-reading order. The two long identifiers are truncated in place and copied in full.
List<DetailsTableItem> _coreFactRows(
  BuildContext context,
  GetPaidTransaction transaction,
) {
  final colors = context.bull;
  return [
    DetailsTableItem(
      label: context.loc.getPaidTransactionsSourceLabel,
      displayValue: getPaidTransactionSourceText(context, transaction.source),
    ),
    DetailsTableItem(
      label: context.loc.getPaidTransactionsReceivedLabel,
      displayValue: getPaidTransactionDateText(context, transaction.receivedAt),
    ),
    DetailsTableItem(
      label: context.loc.getPaidTransactionsRailLabel,
      displayValue: getPaidTransactionRailText(context, transaction.rail),
    ),
    DetailsTableItem(
      label: context.loc.getPaidTransactionsStatusLabel,
      displayValue: getPaidSettlementStateText(
        context,
        transaction.settlementState,
      ),
    ),
    if (transaction.late)
      DetailsTableItem(
        label: context.loc.getPaidTransactionsTimingLabel,
        displayWidget: Text(
          context.loc.getPaidTransactionsLate,
          textAlign: TextAlign.end,
          style: context.bullText.bodyLarge?.copyWith(color: colors.warning),
        ),
      ),
    // The server's own identifier for this entry — the Bull Bitcoin receipt id, labelled as such because it is never a chain transaction id.
    DetailsTableItem(
      key: const ValueKey('get-paid-transaction-id'),
      label: context.loc.getPaidTransactionsReceiptIdLabel,
      displayValue: StringFormatting.truncateMiddle(transaction.transactionId),
      copyValue: transaction.transactionId,
    ),
    // Invoice-sourced entries expose a copyable invoice id; Lightning Address receipts have none and show no row.
    if (transaction.invoiceId case final invoiceId?)
      DetailsTableItem(
        key: const ValueKey('get-paid-transaction-invoice-id'),
        label: context.loc.getPaidTransactionsInvoiceIdLabel,
        displayValue: StringFormatting.truncateMiddle(invoiceId),
        copyValue: invoiceId,
      ),
    if (transaction.comment case final comment?)
      DetailsTableItem(
        key: const ValueKey('get-paid-transaction-comment'),
        label: context.loc.getPaidTransactionsCommentLabel,
        displayValue: comment,
      ),
  ];
}

/// The invoice's own merchant-facing state, reusing the invoice screen's wording and formatters. Nothing here repeats a fact the sections above already carry: the invoice id stays in the core facts, R1 stays in the settlement section when that section prints it, the face amount is omitted when it is the same sat number as the headline, and the paid amount only appears when it differs from the headline (a partial or over payment).
List<DetailsTableItem> _invoiceRows(
  BuildContext context,
  GetPaidInvoiceFacts invoice,
  GetPaidTransaction transaction,
) {
  final rows = <DetailsTableItem>[];
  // The settlement supervision state is already the core "Status" row; the invoice's own settlement line is shown only when it DISAGREES with it (then it adds information). Same rule for the late marker.
  final settlementText =
      _settlementStateMatches(invoice.settlementState, transaction)
      ? null
      : _invoiceSettlementSupportingText(context, invoice.settlementState);
  rows.add(
    _row(
      context,
      key: const ValueKey('get-paid-invoice-status'),
      label: context.loc.invoiceStatusLabel,
      value: _invoiceStatusText(context, invoice.status),
      subLines: [
        if (invoice.isAwaitingConfirmation)
          context.loc.invoiceAwaitingConfirmation,
        ?settlementText,
        if (invoice.hasLatePayment && !transaction.late)
          context.loc.invoiceLatePayment,
      ],
    ),
  );
  // The face value in the invoice screen's own wording, except that a sat face uses this card's separator-formatted sats. A sat face equal to the headline is the same number twice, so it is omitted.
  final satFace = !invoice.hasFiatFace && invoice.hasSatTarget;
  if (!satFace || invoice.amountSat != transaction.amountSat) {
    rows.add(
      _row(
        context,
        label: context.loc.invoiceAmountLabel,
        value: satFace
            ? getPaidTransactionAmountText(context, invoice.amountSat)
            : _invoiceFaceAmountText(context, invoice),
      ),
    );
  }
  rows.add(
    _row(
      context,
      label: context.loc.getPaidInvoicePricingLabel,
      value: _pricingText(context, invoice.pricingMode),
    ),
  );
  // The headline already states what was received; a paid amount that equals it adds nothing. A differing one is the partial/over payment fact.
  final summary = invoice.paymentSummary;
  final paidAmount =
      summary?.observedAmountSat ??
      (invoice.hasPublicPaymentEvidence ? invoice.paidAmountSat : null);
  if (paidAmount case final paidAmountSat?) {
    if (paidAmountSat != transaction.amountSat) {
      rows.add(
        _row(
          context,
          // NOT the invoice screen's "Received": the core facts already use that label for WHEN the payment arrived, so this states the amount.
          label: context.loc.getPaidInvoicePaidAmountLabel,
          value: getPaidTransactionAmountText(context, paidAmountSat),
        ),
      );
    }
  }
  final remainingAmount =
      summary?.remainingAmountSat ??
      (invoice.hasPublicPaymentEvidence ? invoice.remainingAmountSat : 0);
  if (remainingAmount > 0) {
    rows.add(
      _row(
        context,
        label: context.loc.invoicePaymentDifferenceLabel,
        value: getPaidTransactionAmountText(context, remainingAmount),
      ),
    );
  }
  final overpaidAmount =
      summary?.excessAmountSat ??
      (invoice.hasPublicPaymentEvidence ? invoice.overpaidAmountSat : null);
  if (overpaidAmount case final overpaidAmountSat?) {
    rows.add(
      _row(
        context,
        label: context.loc.invoicePaymentOverpaidByLabel,
        value: getPaidTransactionAmountText(context, overpaidAmountSat),
      ),
    );
  }
  if (summary != null && summary.logicalPaymentCount > 1) {
    rows.add(
      _row(
        context,
        label: context.loc.invoicePaymentCountLabel,
        value: '${summary.logicalPaymentCount}',
      ),
    );
  }
  // A zero tolerance is "no tolerance": there is nothing to state.
  if (invoice.paymentToleranceSat > 0) {
    rows.add(
      _row(
        context,
        label: context.loc.getPaidInvoiceToleranceLabel,
        value: getPaidTransactionAmountText(
          context,
          invoice.paymentToleranceSat,
        ),
      ),
    );
  }
  // R1 belongs to the settlement section. It appears here only when that section did not print it at all, so the rate is on the card exactly once.
  if (invoice.creationRateMinorPerBtc case final creationRate?) {
    if (invoice.hasFiatFace &&
        !_settlementShowsCreationRate(transaction.settlement)) {
      rows.add(
        _row(
          context,
          key: const ValueKey('get-paid-invoice-rate-at-creation'),
          label: context.loc.getPaidSettlementRateAtCreationLabel,
          value: context.loc.getPaidSettlementRateAtCreationValue(
            context.loc.getPaidSettlementFiatAmount(
              _formatMinor(creationRate, invoice.fiatCurrency!),
              invoice.fiatCurrency!,
            ),
          ),
        ),
      );
    }
  }
  // A rate lock exists only for a fiat-priced invoice; a sat-priced invoice has no rate to lock, so the row would be meaningless.
  if (invoice.isFiatFixed) {
    rows.add(
      _row(
        context,
        label: context.loc.getPaidInvoiceRateLockedUntilLabel,
        value: getPaidTransactionDateText(context, invoice.rateLocksUntil),
      ),
    );
  }
  rows.add(
    _row(
      context,
      label: context.loc.getPaidInvoiceExpiresAtLabel,
      value: getPaidTransactionDateText(context, invoice.expiresAt),
    ),
  );
  if (invoice.paidVia case final paidVia?) {
    rows.add(
      _row(
        context,
        label: context.loc.getPaidInvoicePaidViaLabel,
        value: _invoiceRailName(context, paidVia),
      ),
    );
  }
  if (invoice.paidAt case final paidAt?) {
    rows.add(
      _row(
        context,
        label: context.loc.getPaidInvoicePaidAtLabel,
        value: getPaidTransactionDateText(context, paidAt),
      ),
    );
  }
  final accepted = <String>[
    if (invoice.acceptLn) context.loc.invoiceAcceptLn,
    if (invoice.acceptLiquid) context.loc.invoiceAcceptLiquid,
    if (invoice.acceptBtc) context.loc.invoiceAcceptBtc,
  ];
  if (accepted.isNotEmpty) {
    rows.add(
      _row(
        context,
        label: context.loc.invoiceRailsLabel,
        value: accepted.join(' · '),
      ),
    );
  }
  return rows;
}

/// One compact row per durable payment observation: the amount, its state as a muted sub-line, and every remaining per-event fact behind the row's expand affordance. Per-event rows carry no [ValueKey] — several observations share one table and duplicate sibling keys are illegal.
List<DetailsTableItem> _paymentEventRows(
  BuildContext context,
  List<GetPaidInvoicePaymentEvent> events,
) {
  final rows = <DetailsTableItem>[];
  for (final event in events) {
    final transactionId = event.transactionId;
    rows.add(
      _row(
        context,
        label: _invoicePaymentRailTitle(context, event.rail),
        value: getPaidTransactionAmountText(context, event.amountSat),
        subLines: [_invoicePaymentEventStateText(context, event)],
        copyValue: transactionId,
        expandableChild: _facts(context, [
          (
            label: context.loc.getPaidInvoiceEventFirstSeenLabel,
            value: getPaidTransactionDateText(context, event.firstSeenAt),
          ),
          (
            label: context.loc.getPaidInvoiceEventLastSeenLabel,
            value: getPaidTransactionDateText(context, event.lastSeenAt),
          ),
          if (transactionId != null)
            (
              label: context.loc.invoicePaymentTransactionLabel,
              value: StringFormatting.truncateMiddle(transactionId),
            ),
          if (event.outputIndex case final outputIndex?)
            (
              label: context.loc.getPaidInvoiceEventOutputIndexLabel,
              value: '$outputIndex',
            ),
          if (event.isLate)
            (
              label: context.loc.getPaidTransactionsTimingLabel,
              value: context.loc.invoiceLatePayment,
            ),
        ]),
      ),
    );
  }
  return rows;
}

/// The muted label/value lines shown inside a row's expand affordance.
Widget _facts(
  BuildContext context,
  List<({String label, String value})> facts,
) {
  final colors = context.bull;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final fact in facts)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  fact.label,
                  style: context.bullText.bodySmall?.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ),
              Text(
                fact.value,
                textAlign: TextAlign.end,
                style: context.bullText.bodySmall?.copyWith(
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

String _invoiceStatusText(BuildContext context, GetPaidInvoiceStatus status) =>
    switch (status) {
      GetPaidInvoiceStatus.unpaid => context.loc.invoiceStatusUnpaid,
      GetPaidInvoiceStatus.inProgress => context.loc.invoiceStatusInProgress,
      GetPaidInvoiceStatus.partiallyPaid =>
        context.loc.invoiceStatusPartiallyPaid,
      GetPaidInvoiceStatus.paid => context.loc.invoiceStatusPaid,
      GetPaidInvoiceStatus.underpaid => context.loc.invoiceStatusUnderpaid,
      GetPaidInvoiceStatus.overpaid => context.loc.invoiceStatusOverpaid,
      GetPaidInvoiceStatus.expired => context.loc.invoiceStatusExpired,
      GetPaidInvoiceStatus.cancelled => context.loc.invoiceStatusCancelled,
      GetPaidInvoiceStatus.unsupported => context.loc.invoiceStatusUnsupported,
    };

String? _invoiceSettlementSupportingText(
  BuildContext context,
  GetPaidInvoiceSettlementState state,
) => switch (state) {
  GetPaidInvoiceSettlementState.none => null,
  GetPaidInvoiceSettlementState.pending => context.loc.invoiceSettlementPending,
  GetPaidInvoiceSettlementState.settled =>
    context.loc.invoiceSettlementComplete,
  GetPaidInvoiceSettlementState.problem => context.loc.invoiceSettlementProblem,
};

String _invoiceFaceAmountText(
  BuildContext context,
  GetPaidInvoiceFacts invoice,
) {
  if (invoice.hasFiatFace) {
    return FormatAmount.fiatMinor(
      invoice.fiatAmountMinor!,
      invoice.fiatCurrency!,
    );
  }
  if (invoice.amountSat > 0) {
    return context.loc.invoiceAmountSats(invoice.amountSat);
  }
  return context.loc.invoiceAmountUnavailable;
}

String _invoicePaymentRailTitle(
  BuildContext context,
  GetPaidInvoiceRail rail,
) => switch (rail) {
  GetPaidInvoiceRail.bitcoin => context.loc.invoicePaymentEventBitcoinTitle,
  GetPaidInvoiceRail.lightning => context.loc.invoicePaymentEventLightningTitle,
  GetPaidInvoiceRail.liquid => context.loc.invoicePaymentEventLiquidTitle,
};

String _invoiceRailName(BuildContext context, GetPaidInvoiceRail rail) =>
    switch (rail) {
      GetPaidInvoiceRail.bitcoin => context.loc.invoiceAcceptBtc,
      GetPaidInvoiceRail.lightning => context.loc.invoiceAcceptLn,
      GetPaidInvoiceRail.liquid => context.loc.invoiceAcceptLiquid,
    };

String _invoicePaymentEventStateText(
  BuildContext context,
  GetPaidInvoicePaymentEvent payment,
) {
  if (payment.state == GetPaidInvoicePaymentEventState.problem) {
    return switch (payment.problem) {
      GetPaidInvoicePaymentProblem.evicted =>
        context.loc.invoicePaymentProblemEvicted,
      GetPaidInvoicePaymentProblem.reorged =>
        context.loc.invoicePaymentProblemReorged,
      GetPaidInvoicePaymentProblem.conflicted =>
        context.loc.invoicePaymentProblemConflicted,
      GetPaidInvoicePaymentProblem.replaced =>
        context.loc.invoicePaymentProblemReplaced,
      GetPaidInvoicePaymentProblem.unknown ||
      null => context.loc.invoicePaymentProblemUnknown,
    };
  }
  return switch (payment.state) {
    GetPaidInvoicePaymentEventState.pending =>
      payment.rail == GetPaidInvoiceRail.bitcoin
          ? context.loc.invoicePaymentSeenMempool
          : context.loc.invoiceSettlementPending,
    GetPaidInvoicePaymentEventState.confirming =>
      context.loc.invoicePaymentConfirmations(payment.confirmations),
    GetPaidInvoicePaymentEventState.settled =>
      context.loc.invoiceSettlementComplete,
    GetPaidInvoicePaymentEventState.problem =>
      context.loc.invoicePaymentProblemUnknown,
  };
}

/// True when the invoice's settlement supervision says the same thing as the entry's own Status row, in which case repeating it adds nothing.
bool _settlementStateMatches(
  GetPaidInvoiceSettlementState state,
  GetPaidTransaction transaction,
) {
  return switch (state) {
    GetPaidInvoiceSettlementState.none => true,
    GetPaidInvoiceSettlementState.pending =>
      transaction.settlementState == GetPaidSettlementState.pending,
    GetPaidInvoiceSettlementState.settled =>
      transaction.settlementState == GetPaidSettlementState.settled,
    GetPaidInvoiceSettlementState.problem =>
      transaction.settlementState == GetPaidSettlementState.problem,
  };
}

/// True when the settlement section prints a rate-at-creation row of its own, so the invoice section must not print one too.
bool _settlementShowsCreationRate(GetPaidSettlement? settlement) {
  final s = settlement;
  if (s == null) return false;
  // Only the fiat and mixed sections render a rate-at-creation row at all.
  if (s.kind != GetPaidSettlementKind.fiat &&
      s.kind != GetPaidSettlementKind.mixed) {
    return false;
  }
  return s.creationRateMinorPerBtc != null && s.creationRateCurrency != null;
}

/// The invoice pricing mode in the wording the invoice form already uses. An unknown mode (outside the two contract values) is shown verbatim rather than mislabelled as one of the known ones.
String _pricingText(BuildContext context, String pricingMode) {
  return switch (pricingMode) {
    'fiat_fixed' => context.loc.invoiceAmountModeFiat,
    'sat_fixed' => context.loc.invoiceAmountModeSats,
    _ => pricingMode,
  };
}

/// A details row whose value optionally carries muted sub-lines beneath it (the sub-line idiom the settlement rows already use) and optionally hides its remaining facts behind the table's expand affordance.
DetailsTableItem _row(
  BuildContext context, {
  required String label,
  required String value,
  Key? key,
  String? copyValue,
  List<String> subLines = const [],
  Widget? expandableChild,
}) {
  if (subLines.isEmpty) {
    return DetailsTableItem(
      key: key,
      label: label,
      displayValue: value,
      copyValue: copyValue,
      expandableChild: expandableChild,
    );
  }
  final colors = context.bull;
  return DetailsTableItem(
    key: key,
    label: label,
    displayValue: value,
    copyValue: copyValue,
    expandableChild: expandableChild,
    displayWidget: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          textAlign: TextAlign.end,
          style: context.bullText.bodyLarge,
        ),
        for (final subLine in subLines) ...[
          const Gap(4),
          Text(
            subLine,
            textAlign: TextAlign.end,
            style: context.bullText.bodySmall?.copyWith(
              color: colors.textMuted,
            ),
          ),
        ],
      ],
    ),
  );
}

/// The settlement section's rows. Empty only for a no-data row (no server classification at all) — absence is never presented as Bitcoin.
List<DetailsTableItem> _settlementRows(
  BuildContext context,
  GetPaidSettlement? settlement,
) {
  final s = settlement;
  if (s == null) return const [];
  final colors = context.bull;
  final rows = <DetailsTableItem>[];
  switch (s.kind) {
    case GetPaidSettlementKind.unavailable:
      // Uninterpretable evidence states exactly that; it claims no kind.
      rows.add(
        DetailsTableItem(
          label: context.loc.getPaidFiatSettlementSectionTitle,
          displayValue: context.loc.getPaidSettlementDetailsUnavailable,
        ),
      );
    case GetPaidSettlementKind.bitcoin:
      _addKindRow(context, rows, s.kind);
      // A Bitcoin settlement that overrode a configured fiat conversion explains itself; an ordinary one has nothing to explain.
      if (s.overrideReason != null) {
        rows.add(
          DetailsTableItem(
            label: context.loc.getPaidFiatSettlementSectionTitle,
            displayWidget: Text(
              _overrideText(context, s.overrideReason),
              textAlign: TextAlign.end,
              style: context.bullText.bodyMedium?.copyWith(
                color: colors.warning,
              ),
            ),
          ),
        );
      }
    case GetPaidSettlementKind.mixed:
      // A mixed settlement is shown per-leg: the kind, the captured split (when present), the invoice-creation reference rate (R1, when present), then the bitcoin (L-BTC) leg's amount, network and its own status, then the fiat leg's amount and status.
      _addKindRow(context, rows, s.kind);
      _addSplitRow(context, rows, s.fiatPercentage);
      _addRateAtCreationRow(context, rows, s);
      rows.addAll(
        _bitcoinLegRows(
          context,
          s.bitcoin,
          creationRateMinorPerBtc: s.creationRateMinorPerBtc,
          creationRateCurrency: s.creationRateCurrency,
        ),
      );
      rows.addAll(_fiatLegRows(context, s.fiat));
    case GetPaidSettlementKind.fiat:
      _addKindRow(context, rows, s.kind);
      _addSplitRow(context, rows, s.fiatPercentage);
      _addRateAtCreationRow(context, rows, s);
      rows.addAll(_fiatLegRows(context, s.fiat));
  }
  return rows;
}

/// The server's own settlement classification, stated once at the top of the section. It reuses the history list's kind labels, so an ordinary Bitcoin settlement now says so instead of being conveyed by an absent section.
void _addKindRow(
  BuildContext context,
  List<DetailsTableItem> rows,
  GetPaidSettlementKind kind,
) {
  rows.add(
    DetailsTableItem(
      key: const ValueKey('get-paid-settlement-kind'),
      label: context.loc.getPaidCardSettlementKindLabel,
      displayValue: switch (kind) {
        GetPaidSettlementKind.mixed => context.loc.getPaidSettlementKindMixed,
        GetPaidSettlementKind.fiat => context.loc.getPaidSettlementLabelFiat,
        GetPaidSettlementKind.bitcoin || GetPaidSettlementKind.unavailable =>
          context.loc.getPaidSettlementLabelBitcoin,
      },
    ),
  );
}

/// The R1 "Rate at creation" row, rendered directly after the Split row for a fiat-priced invoice. Shown only when BOTH the reference rate and its face currency are known; a rate without a currency has no denomination to render, so the row is omitted rather than guessed. The value is approximate (it is a reference index, not an executed rate) and always carries the ≈ prefix.
void _addRateAtCreationRow(
  BuildContext context,
  List<DetailsTableItem> rows,
  GetPaidSettlement s,
) {
  final rate = s.creationRateMinorPerBtc;
  final currency = s.creationRateCurrency;
  if (rate == null || currency == null) return;
  rows.add(
    DetailsTableItem(
      key: const ValueKey('get-paid-settlement-rate-at-creation'),
      label: context.loc.getPaidSettlementRateAtCreationLabel,
      displayValue: context.loc.getPaidSettlementRateAtCreationValue(
        context.loc.getPaidSettlementFiatAmount(
          _formatMinor(rate, currency),
          currency,
        ),
      ),
    ),
  );
}

/// The captured fiat/Bitcoin split row, rendered directly above the leg rows. Absent for a legacy row (null percentage). Worded like the dashboard badge: `100` → "100% fiat"; `40` → "60% Bitcoin · 40% fiat".
void _addSplitRow(
  BuildContext context,
  List<DetailsTableItem> rows,
  int? fiatPercentage,
) {
  if (fiatPercentage == null) return;
  final value = fiatPercentage >= 100
      ? context.loc.getPaidSettlementSplitFiatOnly
      : context.loc.getPaidSettlementSplitMixed(
          100 - fiatPercentage,
          fiatPercentage,
        );
  rows.add(
    DetailsTableItem(
      key: const ValueKey('get-paid-settlement-split'),
      label: context.loc.getPaidSettlementSplitLabel,
      displayValue: value,
    ),
  );
}

/// The bitcoin (L-BTC) leg rows of a mixed settlement: the on-Liquid amount and the leg's own lifecycle. The bitcoin leg uses pending/settled/problem, and a `problem` reuses the history list's needs-attention wording — this per-leg status is distinct from the top payment-lifecycle Status row.
List<DetailsTableItem> _bitcoinLegRows(
  BuildContext context,
  List<GetPaidBitcoinSettlementLeg> legs, {
  int? creationRateMinorPerBtc,
  String? creationRateCurrency,
}) {
  final colors = context.bull;
  final rows = <DetailsTableItem>[];
  for (final leg in legs) {
    // When the invoice-creation rate (R1) and its face currency are both known, the L-BTC amount carries a muted ≈ sub-line estimating this leg's fiat worth at that rate (sats × R1). It is an estimate at a reference moment, never an executed value, so it always wears ≈ and never mixes with the fiat leg's own currency.
    final estimateMinor = (creationRateMinorPerBtc != null)
        ? getPaidBitcoinLegValueMinorAtCreationRate(
            leg.amountSat,
            creationRateMinorPerBtc,
          )
        : null;
    if (estimateMinor != null && creationRateCurrency != null) {
      rows.add(
        DetailsTableItem(
          label: context.loc.getPaidSettlementLbtcAmountLabel,
          displayWidget: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                getPaidTransactionAmountText(context, leg.amountSat),
                textAlign: TextAlign.end,
                style: context.bullText.bodyLarge,
              ),
              const Gap(4),
              Text(
                context.loc.getPaidSettlementCreationValueSubline(
                  context.loc.getPaidSettlementFiatAmount(
                    _formatMinor(estimateMinor, creationRateCurrency),
                    creationRateCurrency,
                  ),
                ),
                textAlign: TextAlign.end,
                style: context.bullText.bodySmall?.copyWith(
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      rows.add(
        DetailsTableItem(
          label: context.loc.getPaidSettlementLbtcAmountLabel,
          displayValue: getPaidTransactionAmountText(context, leg.amountSat),
        ),
      );
    }
    // The network the server settled this leg on, named as the server names it.
    rows.add(
      DetailsTableItem(
        label: context.loc.getPaidSettlementNetworkLabel,
        displayValue: _networkText(context, leg.network),
      ),
    );
    rows.add(
      DetailsTableItem(
        label: context.loc.getPaidSettlementLbtcStatusLabel,
        displayValue: _legStatusText(context, leg.status),
      ),
    );
  }
  return rows;
}

/// The settlement network of a bitcoin leg. Version one settles Bitcoin legs on Liquid only, so `liquid` reuses the existing Liquid rail label; any other server value (which the strict parser does not currently admit as a definite leg) is shown verbatim rather than guessed at.
String _networkText(BuildContext context, String network) {
  return network == 'liquid'
      ? context.loc.getPaidTransactionsRailLiquid
      : network;
}

List<DetailsTableItem> _fiatLegRows(
  BuildContext context,
  List<GetPaidFiatSettlementLeg> legs,
) {
  final colors = context.bull;
  final rows = <DetailsTableItem>[];
  for (final leg in legs) {
    final settled =
        leg.status == GetPaidSettlementLegStatus.settled &&
        leg.amountMinor != null;
    // A still-pending leg that carries a locked quote shows it, labelled as a quote — it can reprice for a late payment, so it must not read as final.
    final quotedPending =
        leg.status == GetPaidSettlementLegStatus.pending &&
        leg.quotedAmountMinor != null;
    // Once settled the value carries the final credited fiat amount; a pending
    // leg with a quote shows the quoted amount; otherwise the expected
    // settlement currency only (v1 server / legacy row).
    // A settled leg that carries Bull Bitcoin's real execution rate (R2) shows
    // it as a muted sub-line under the exact credited amount. R2 is exact and
    // in the leg's own currency, so it carries no ≈; a pending leg keeps its
    // quoted/awaiting sub-line (rendered under the status row below) instead.
    final showExecutionRate = settled && leg.executionRateMinorPerBtc != null;
    if (showExecutionRate) {
      rows.add(
        DetailsTableItem(
          label: context.loc.getPaidSettlementFiatAmountLabel,
          displayWidget: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                context.loc.getPaidSettlementFiatAmount(
                  _formatMinor(leg.amountMinor!, leg.currency),
                  leg.currency,
                ),
                textAlign: TextAlign.end,
                style: context.bullText.bodyLarge,
              ),
              const Gap(4),
              Text(
                context.loc.getPaidSettlementExecutionRateValue(
                  context.loc.getPaidSettlementFiatAmount(
                    _formatMinor(leg.executionRateMinorPerBtc!, leg.currency),
                    leg.currency,
                  ),
                ),
                textAlign: TextAlign.end,
                style: context.bullText.bodySmall?.copyWith(
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      rows.add(
        DetailsTableItem(
          label: quotedPending
              ? context.loc.getPaidSettlementFiatAmountQuotedLabel
              : context.loc.getPaidSettlementFiatAmountLabel,
          displayValue: settled
              ? context.loc.getPaidSettlementFiatAmount(
                  _formatMinor(leg.amountMinor!, leg.currency),
                  leg.currency,
                )
              : quotedPending
              ? context.loc.getPaidSettlementFiatAmount(
                  _formatMinor(leg.quotedAmountMinor!, leg.currency),
                  leg.currency,
                )
              : leg.currency,
        ),
      );
    }
    if (leg.status == GetPaidSettlementLegStatus.pending) {
      // A still-pending leg names the expected currency and explains that the fiat amount is not final until settlement completes — never a guessed amount.
      rows.add(
        DetailsTableItem(
          label: context.loc.getPaidSettlementFiatStatusLabel,
          displayWidget: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _legStatusText(context, leg.status),
                textAlign: TextAlign.end,
                style: context.bullText.bodyLarge,
              ),
              const Gap(4),
              Text(
                context.loc.getPaidSettlementAwaitingExplainer(leg.currency),
                textAlign: TextAlign.end,
                style: context.bullText.bodySmall?.copyWith(
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      rows.add(
        DetailsTableItem(
          label: context.loc.getPaidSettlementFiatStatusLabel,
          displayValue: _legStatusText(context, leg.status),
        ),
      );
    }
    if (leg.orderId.isNotEmpty) {
      rows.add(
        DetailsTableItem(
          label: context.loc.getPaidSettlementOrderId,
          displayValue: StringFormatting.truncateMiddle(leg.orderId),
          copyValue: leg.orderId,
        ),
      );
    }
  }
  return rows;
}

/// Concise, per-reason explanation for a Bitcoin-only override. An unrecognized reason falls back to the generic override copy.
String _overrideText(BuildContext context, GetPaidFiatOverrideReason? reason) {
  switch (reason) {
    case GetPaidFiatOverrideReason.belowMinimum:
      return context.loc.getPaidSettlementOverriddenBelowMinimum;
    case GetPaidFiatOverrideReason.invalidSplit:
      return context.loc.getPaidSettlementOverriddenInvalidSplit;
    case GetPaidFiatOverrideReason.conversionUnavailable:
      return context.loc.getPaidSettlementOverriddenConversionUnavailable;
    case GetPaidFiatOverrideReason.ambiguousCreate:
      return context.loc.getPaidSettlementOverriddenAmbiguousCreate;
    case GetPaidFiatOverrideReason.unknown:
    case null:
      return context.loc.getPaidSettlementOverridden;
  }
}

String _legStatusText(BuildContext context, GetPaidSettlementLegStatus status) {
  switch (status) {
    case GetPaidSettlementLegStatus.pending:
      return context.loc.getPaidSettlementStatusPending;
    case GetPaidSettlementLegStatus.settled:
      return context.loc.getPaidSettlementStatusSettled;
    case GetPaidSettlementLegStatus.problem:
      // The bitcoin (L-BTC) leg's `problem` reuses the history list's needs-attention wording.
      return context.loc.getPaidTransactionsStateProblem;
    case GetPaidSettlementLegStatus.unavailable:
      return context.loc.getPaidSettlementDetailsUnavailable;
  }
}

String _formatMinor(int minor, String currency) =>
    FormatAmount.fiatMinorValue(minor, currency);
