import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/core/widgets/tables/details_table.dart';
import 'package:bb_mobile/core/widgets/tables/details_table_item.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_creation_rate.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_settlement.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_transaction.dart';
import 'package:bb_mobile/features/get_paid/ui/screens/get_paid_transaction_history_screen.dart';
import 'package:bb_mobile/features/invoices/public/invoices_routes.dart';
import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class GetPaidTransactionDetailScreen extends StatelessWidget {
  final GetPaidTransaction transaction;

  const GetPaidTransactionDetailScreen({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
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
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    getPaidTransactionAmountText(
                      context,
                      transaction.amountSat,
                    ),
                    textAlign: TextAlign.center,
                    style: context.bullText.headlineLarge,
                  ),
                  const Gap(24),
                  DetailsTable(
                    items: [
                      DetailsTableItem(
                        label: context.loc.getPaidTransactionsSourceLabel,
                        displayValue: getPaidTransactionSourceText(
                          context,
                          transaction.source,
                        ),
                      ),
                      DetailsTableItem(
                        label: context.loc.getPaidTransactionsReceivedLabel,
                        displayValue: getPaidTransactionDateText(
                          context,
                          transaction.receivedAt,
                        ),
                      ),
                      DetailsTableItem(
                        label: context.loc.getPaidTransactionsRailLabel,
                        displayValue: getPaidTransactionRailText(
                          context,
                          transaction.rail,
                        ),
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
                            style: context.bullText.bodyLarge?.copyWith(
                              color: colors.warning,
                            ),
                          ),
                        ),
                      // Invoice-sourced payments expose a copyable invoice id
                      // (same copy idiom as the order-id row); Lightning Address
                      // payments have none and show no row.
                      if (transaction.invoiceId case final invoiceId?)
                        DetailsTableItem(
                          key: const ValueKey(
                            'get-paid-transaction-invoice-id',
                          ),
                          label: context.loc.getPaidTransactionsInvoiceIdLabel,
                          displayValue: invoiceId,
                          copyValue: invoiceId,
                        ),
                      // The private, merchant-only fiat settlement breakdown
                      // shares the same table: no rows for a plain Bitcoin
                      // payment, the override explanation when kept in Bitcoin,
                      // and an explicit "unavailable" row for anything
                      // uninterpretable — never a misleading Bitcoin-only view.
                      ..._settlementRows(context, transaction.settlement),
                      if (transaction.comment case final comment?)
                        DetailsTableItem(
                          key: const ValueKey('get-paid-transaction-comment'),
                          label: context.loc.getPaidTransactionsCommentLabel,
                          displayValue: comment,
                        ),
                    ],
                  ),
                  if (transaction.invoiceId case final invoiceId?) ...[
                    const Gap(32),
                    BullButton.big(
                      label: context.loc.getPaidTransactionsViewInvoice,
                      iconData: Icons.receipt_long,
                      iconFirst: true,
                      onPressed: () => context.pushNamed(
                        InvoicesRoute.detail.name,
                        pathParameters: {'id': invoiceId},
                      ),
                      bgColor: colors.primary,
                      textColor: colors.onPrimary,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Settlement rows for the single details table. Empty for a no-data row or an
/// ordinary Bitcoin settlement with no override to explain.
List<DetailsTableItem> _settlementRows(
  BuildContext context,
  GetPaidSettlement? settlement,
) {
  final s = settlement;
  if (s == null ||
      (s.kind == GetPaidSettlementKind.bitcoin && s.overrideReason == null)) {
    return const [];
  }
  final colors = context.bull;
  final rows = <DetailsTableItem>[];
  switch (s.kind) {
    case GetPaidSettlementKind.unavailable:
      rows.add(
        DetailsTableItem(
          label: context.loc.getPaidFiatSettlementSectionTitle,
          displayValue: context.loc.getPaidSettlementDetailsUnavailable,
        ),
      );
    case GetPaidSettlementKind.bitcoin:
      rows.add(
        DetailsTableItem(
          label: context.loc.getPaidFiatSettlementSectionTitle,
          displayWidget: Text(
            _overrideText(context, s.overrideReason),
            textAlign: TextAlign.end,
            style: context.bullText.bodyMedium?.copyWith(color: colors.warning),
          ),
        ),
      );
    case GetPaidSettlementKind.mixed:
      // A mixed settlement is shown per-leg in the one table: the captured
      // split (when present), the invoice-creation reference rate (R1, when
      // present), then the bitcoin (L-BTC) leg's amount and its own status,
      // then the fiat leg's amount and status.
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
      _addSplitRow(context, rows, s.fiatPercentage);
      _addRateAtCreationRow(context, rows, s);
      rows.addAll(_fiatLegRows(context, s.fiat));
  }
  return rows;
}

/// The R1 "Rate at creation" row, rendered directly after the Split row for a
/// fiat-priced invoice. Shown only when BOTH the reference rate and its face
/// currency are known; a rate without a currency has no denomination to render,
/// so the row is omitted rather than guessed. The value is approximate (it is a
/// reference index, not an executed rate) and always carries the ≈ prefix.
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
        context.loc.getPaidSettlementFiatAmount(_formatMinor(rate), currency),
      ),
    ),
  );
}

/// The captured fiat/Bitcoin split row, rendered directly above the leg rows.
/// Absent for a legacy row (null percentage). Worded like the dashboard badge:
/// `100` → "100% fiat"; `40` → "60% Bitcoin · 40% fiat".
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

/// The bitcoin (L-BTC) leg rows of a mixed settlement: the on-Liquid amount and
/// the leg's own lifecycle. The bitcoin leg uses pending/settled/problem, and a
/// `problem` reuses the history list's needs-attention wording — this per-leg
/// status is distinct from the top payment-lifecycle Status row.
List<DetailsTableItem> _bitcoinLegRows(
  BuildContext context,
  List<GetPaidBitcoinSettlementLeg> legs, {
  int? creationRateMinorPerBtc,
  String? creationRateCurrency,
}) {
  final colors = context.bull;
  final rows = <DetailsTableItem>[];
  for (final leg in legs) {
    // When the invoice-creation rate (R1) and its face currency are both known,
    // the L-BTC amount carries a muted ≈ sub-line estimating this leg's fiat
    // worth at that rate (sats × R1). It is an estimate at a reference moment,
    // never an executed value, so it always wears ≈ and never mixes with the
    // fiat leg's own currency.
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
                    _formatMinor(estimateMinor),
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
    rows.add(
      DetailsTableItem(
        label: context.loc.getPaidSettlementLbtcStatusLabel,
        displayValue: _legStatusText(context, leg.status),
      ),
    );
  }
  return rows;
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
    // A still-pending leg that carries a locked quote shows it, labelled as a
    // quote — it can reprice for a late payment, so it must not read as final.
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
                  _formatMinor(leg.amountMinor!),
                  leg.currency,
                ),
                textAlign: TextAlign.end,
                style: context.bullText.bodyLarge,
              ),
              const Gap(4),
              Text(
                context.loc.getPaidSettlementExecutionRateValue(
                  context.loc.getPaidSettlementFiatAmount(
                    _formatMinor(leg.executionRateMinorPerBtc!),
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
                  _formatMinor(leg.amountMinor!),
                  leg.currency,
                )
              : quotedPending
              ? context.loc.getPaidSettlementFiatAmount(
                  _formatMinor(leg.quotedAmountMinor!),
                  leg.currency,
                )
              : leg.currency,
        ),
      );
    }
    if (leg.status == GetPaidSettlementLegStatus.pending) {
      // A still-pending leg names the expected currency and explains that the
      // fiat amount is not final until settlement completes — never a guessed
      // amount.
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
          displayValue: leg.orderId,
          copyValue: leg.orderId,
        ),
      );
    }
  }
  return rows;
}

/// Concise, per-reason explanation for a Bitcoin-only override. An unrecognized
/// reason falls back to the generic override copy.
String _overrideText(BuildContext context, GetPaidFiatOverrideReason? reason) {
  switch (reason) {
    case GetPaidFiatOverrideReason.belowMinimum:
      return context.loc.getPaidSettlementOverriddenBelowMinimum;
    case GetPaidFiatOverrideReason.invalidSplit:
      return context.loc.getPaidSettlementOverriddenInvalidSplit;
    case GetPaidFiatOverrideReason.conversionUnavailable:
      return context.loc.getPaidSettlementOverriddenConversionUnavailable;
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
      // The bitcoin (L-BTC) leg's `problem` reuses the history list's
      // needs-attention wording.
      return context.loc.getPaidTransactionsStateProblem;
    case GetPaidSettlementLegStatus.unavailable:
      return context.loc.getPaidSettlementDetailsUnavailable;
  }
}

// Fiat minor units → major.minor with integer arithmetic (never floating
// point). The seven supported currencies are all 2-decimal.
String _formatMinor(int minor) {
  final major = minor ~/ 100;
  final cents = (minor % 100).toString().padLeft(2, '0');
  return '$major.$cents';
}
