import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/core/widgets/tables/details_table.dart';
import 'package:bb_mobile/core/widgets/tables/details_table_item.dart';
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
                      // Asset is faithfully derived from the (authoritative)
                      // rail — Liquid settles L-BTC, on-chain and Lightning are
                      // BTC. Never a fabricated ticker.
                      DetailsTableItem(
                        label: context.loc.getPaidTransactionsAssetLabel,
                        displayValue: getPaidTransactionAssetText(
                          context,
                          transaction.rail,
                        ),
                      ),
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
      for (final btc in s.bitcoin) {
        rows.add(
          DetailsTableItem(
            label: context.loc.getPaidSettlementBitcoinPortion,
            displayValue: getPaidTransactionAmountText(context, btc.amountSat),
          ),
        );
      }
      rows.addAll(_fiatLegRows(context, s.fiat));
    case GetPaidSettlementKind.fiat:
      rows.addAll(_fiatLegRows(context, s.fiat));
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
    // Currency is always shown (the expected settlement currency); once settled
    // the value carries the final fiat amount alongside the code.
    rows.add(
      DetailsTableItem(
        label: context.loc.getPaidSettlementLabelFiat,
        displayValue: settled
            ? context.loc.getPaidSettlementFiatAmount(
                _formatMinor(leg.amountMinor!),
                leg.currency,
              )
            : leg.currency,
      ),
    );
    if (leg.status == GetPaidSettlementLegStatus.pending) {
      // A still-pending leg names the expected currency and explains that the
      // fiat amount is not final until settlement completes — never a guessed
      // amount.
      rows.add(
        DetailsTableItem(
          label: context.loc.getPaidSettlementStatus,
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
          label: context.loc.getPaidSettlementStatus,
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
