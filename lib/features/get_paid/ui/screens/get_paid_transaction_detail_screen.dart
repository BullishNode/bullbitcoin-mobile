import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/core/widgets/inputs/copy_input.dart';
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
                    ],
                  ),
                  _SettlementSection(settlement: transaction.settlement),
                  if (transaction.comment case final comment?) ...[
                    const Gap(24),
                    Text(
                      context.loc.getPaidTransactionsCommentLabel,
                      style: context.bullText.labelMedium?.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                    const Gap(6),
                    Text(
                      comment,
                      key: const ValueKey('get-paid-transaction-comment'),
                      style: context.bullText.bodyLarge,
                    ),
                  ],
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

/// Private, merchant-only fiat settlement breakdown. Renders nothing for a
/// plain Bitcoin payment; shows the override explanation when kept in Bitcoin;
/// and "Settlement details unavailable" for anything uninterpretable — never a
/// misleading Bitcoin-only view.
class _SettlementSection extends StatelessWidget {
  final GetPaidSettlement? settlement;

  const _SettlementSection({required this.settlement});

  @override
  Widget build(BuildContext context) {
    final s = settlement;
    // No section for a no-data row, or an ordinary Bitcoin settlement with no
    // override to explain.
    if (s == null ||
        (s.kind == GetPaidSettlementKind.bitcoin && s.overrideReason == null)) {
      return const SizedBox.shrink();
    }
    final colors = context.bull;
    final rows = <Widget>[];
    switch (s.kind) {
      case GetPaidSettlementKind.unavailable:
        rows.add(
          _DetailRow(
            label: context.loc.getPaidFiatSettlementSectionTitle,
            value: context.loc.getPaidSettlementDetailsUnavailable,
          ),
        );
      case GetPaidSettlementKind.bitcoin:
        rows.add(
          Text(
            _overrideText(context, s.overrideReason),
            style: context.bullText.bodyMedium?.copyWith(color: colors.warning),
          ),
        );
      case GetPaidSettlementKind.mixed:
        for (final btc in s.bitcoin) {
          rows.add(
            _DetailRow(
              label: context.loc.getPaidSettlementBitcoinPortion,
              value: getPaidTransactionAmountText(context, btc.amountSat),
            ),
          );
        }
        rows.addAll(_fiatLegRows(context, s.fiat));
      case GetPaidSettlementKind.fiat:
        rows.addAll(_fiatLegRows(context, s.fiat));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Gap(24),
        Text(
          context.loc.getPaidFiatSettlementSectionTitle,
          style: context.bullText.labelMedium?.copyWith(
            color: colors.textMuted,
          ),
        ),
        const Gap(6),
        ...rows,
      ],
    );
  }

  /// Concise, per-reason explanation for a Bitcoin-only override. An
  /// unrecognized reason falls back to the generic override copy.
  String _overrideText(
    BuildContext context,
    GetPaidFiatOverrideReason? reason,
  ) {
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

  List<Widget> _fiatLegRows(
    BuildContext context,
    List<GetPaidFiatSettlementLeg> legs,
  ) {
    final colors = context.bull;
    final rows = <Widget>[];
    for (final leg in legs) {
      final settled =
          leg.status == GetPaidSettlementLegStatus.settled &&
          leg.amountMinor != null;
      // Currency is always shown (the expected settlement currency); once
      // settled the value carries the final fiat amount alongside the code.
      rows.add(
        _DetailRow(
          label: context.loc.getPaidSettlementLabelFiat,
          value: settled
              ? context.loc.getPaidSettlementFiatAmount(
                  _formatMinor(leg.amountMinor!),
                  leg.currency,
                )
              : leg.currency,
        ),
      );
      rows.add(
        _DetailRow(
          label: context.loc.getPaidSettlementStatus,
          value: _legStatusText(context, leg.status),
        ),
      );
      // Richer pending presentation (Q24b): a still-pending leg names the
      // expected currency and explains that the fiat amount is not final until
      // settlement completes — never a guessed amount.
      if (leg.status == GetPaidSettlementLegStatus.pending) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              context.loc.getPaidSettlementAwaitingExplainer(leg.currency),
              style: context.bullText.bodySmall?.copyWith(
                color: colors.textMuted,
              ),
            ),
          ),
        );
      }
      if (leg.orderId.isNotEmpty) {
        rows.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.loc.getPaidSettlementOrderId,
                  style: context.bullText.bodyMedium?.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                const Gap(6),
                CopyInput(text: leg.orderId),
              ],
            ),
          ),
        );
      }
    }
    return rows;
  }

  String _legStatusText(
    BuildContext context,
    GetPaidSettlementLegStatus status,
  ) {
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
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: context.bullText.bodyMedium?.copyWith(
                color: colors.textMuted,
              ),
            ),
          ),
          const Gap(16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: context.bullText.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}
