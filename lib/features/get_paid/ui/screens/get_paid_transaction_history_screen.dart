import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_settlement.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_transaction.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_transaction_history_cubit.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_transaction_history_state.dart';
import 'package:bb_mobile/features/get_paid/public/get_paid_routes.dart';
import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class GetPaidTransactionHistoryScreen extends StatefulWidget {
  const GetPaidTransactionHistoryScreen({super.key});

  @override
  State<GetPaidTransactionHistoryScreen> createState() =>
      _GetPaidTransactionHistoryScreenState();
}

class _GetPaidTransactionHistoryScreenState
    extends State<GetPaidTransactionHistoryScreen> {
  @override
  void initState() {
    super.initState();
    context.read<GetPaidTransactionHistoryCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    return BullScaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            BullTopBar(
              title: context.loc.getPaidTransactionsTitle,
              onBack: context.pop,
            ),
            Expanded(
              child:
                  BlocBuilder<
                    GetPaidTransactionHistoryCubit,
                    GetPaidTransactionHistoryState
                  >(
                    builder: (context, state) => switch (state.status) {
                      GetPaidTransactionHistoryStatus.initial ||
                      GetPaidTransactionHistoryStatus.loading =>
                        const _LoadingHistory(),
                      GetPaidTransactionHistoryStatus.failure =>
                        _FailureHistory(
                          onRetry: context
                              .read<GetPaidTransactionHistoryCubit>()
                              .refresh,
                        ),
                      GetPaidTransactionHistoryStatus.loaded
                          when state.isEmpty =>
                        _EmptyHistory(
                          onRefresh: context
                              .read<GetPaidTransactionHistoryCubit>()
                              .refresh,
                        ),
                      GetPaidTransactionHistoryStatus.loaded => _HistoryList(
                        state: state,
                      ),
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  final GetPaidTransactionHistoryState state;

  const _HistoryList({required this.state});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GetPaidTransactionHistoryCubit>();
    // Full wallet-history look: rows grouped under day headers (Today /
    // Yesterday / date). Get Paid keeps its own entities, pagination and
    // routing — this is a presentation shell over the Get Paid transactions,
    // never a conversion into wallet Transaction objects.
    final groups = _groupByDay(state.transactions);
    return RefreshIndicator(
      onRefresh: cubit.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final group in groups) ...[
            _DayHeader(day: group.day),
            for (final transaction in group.transactions)
              _TransactionRow(
                transaction: transaction,
                onTap: () => context.pushNamed(
                  GetPaidDashboardRoute.getPaidTransactionDetail.name,
                  extra: transaction,
                ),
              ),
          ],
          if (state.hasMore || state.loadMoreFailed)
            _LoadMoreFooter(state: state, onLoadMore: cubit.loadMore),
        ],
      ),
    );
  }
}

/// One day's worth of Get Paid transactions under a shared date header.
class _TransactionDayGroup {
  final DateTime day;
  final List<GetPaidTransaction> transactions;

  const _TransactionDayGroup({required this.day, required this.transactions});
}

/// Groups the (already newest-first) transactions by local calendar day,
/// preserving order.
List<_TransactionDayGroup> _groupByDay(List<GetPaidTransaction> transactions) {
  final groups = <_TransactionDayGroup>[];
  DateTime? currentDay;
  var bucket = <GetPaidTransaction>[];
  for (final transaction in transactions) {
    final local = transaction.receivedAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    if (currentDay == null || !day.isAtSameMomentAs(currentDay)) {
      if (bucket.isNotEmpty) {
        groups.add(
          _TransactionDayGroup(day: currentDay!, transactions: bucket),
        );
      }
      currentDay = day;
      bucket = <GetPaidTransaction>[];
    }
    bucket.add(transaction);
  }
  if (bucket.isNotEmpty && currentDay != null) {
    groups.add(_TransactionDayGroup(day: currentDay, transactions: bucket));
  }
  return groups;
}

class _DayHeader extends StatelessWidget {
  final DateTime day;

  const _DayHeader({required this.day});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        getPaidDayGroupLabel(context, day),
        style: context.bullText.titleSmall?.copyWith(
          color: context.bull.textMuted,
        ),
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final GetPaidTransaction transaction;
  final VoidCallback onTap;

  const _TransactionRow({required this.transaction, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    return ListTile(
      key: ValueKey('get-paid-transaction-${transaction.stableKey}'),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: BullIcon(
        getPaidTransactionSourceIcon(transaction.source),
        color: colors.primary,
      ),
      title: Text(
        getPaidTransactionAmountText(context, transaction.amountSat),
        style: context.bullText.titleMedium,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(getPaidTransactionSourceText(context, transaction.source)),
            const SizedBox(height: 2),
            Text(
              '${getPaidTransactionRailText(context, transaction.rail)} · '
              '${getPaidSettlementStateText(context, transaction.settlementState)}',
            ),
            // Render the classification label ONLY from an explicit
            // server-provided settlement kind. A no-data row (null) omits the
            // label — it is never printed as Bitcoin without evidence.
            if (transaction.settlement case final settlement?) ...[
              const SizedBox(height: 2),
              Builder(
                builder: (context) {
                  final inlineFiat = getPaidSettledFiatInline(
                    context,
                    settlement,
                  );
                  final kindLabel = getPaidSettlementKindLabel(
                    context,
                    settlement.kind,
                  );
                  return Text(
                    inlineFiat == null ? kindLabel : '$kindLabel · $inlineFiat',
                  );
                },
              ),
            ],
            const SizedBox(height: 2),
            Text(
              getPaidTransactionDateText(context, transaction.receivedAt),
              style: context.bullText.bodySmall?.copyWith(
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ),
      trailing: const BullIcon(Icons.chevron_right),
    );
  }
}

class _LoadMoreFooter extends StatelessWidget {
  final GetPaidTransactionHistoryState state;
  final VoidCallback onLoadMore;

  const _LoadMoreFooter({required this.state, required this.onLoadMore});

  @override
  Widget build(BuildContext context) {
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final colors = context.bull;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: BullButton.big(
        label: state.loadMoreFailed
            ? context.loc.getPaidTransactionsRetry
            : context.loc.getPaidTransactionsLoadMore,
        iconData: state.loadMoreFailed ? Icons.refresh : Icons.expand_more,
        iconFirst: true,
        onPressed: onLoadMore,
        outlined: true,
        bgColor: colors.background,
        textColor: colors.text,
        borderColor: colors.border,
      ),
    );
  }
}

class _LoadingHistory extends StatelessWidget {
  const _LoadingHistory();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var index = 0; index < 5; index++)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BullShimmerLine(
                  width: 130,
                  height: 16,
                  padding: EdgeInsets.zero,
                ),
                SizedBox(height: 8),
                BullShimmerLine(
                  width: 180,
                  height: 12,
                  padding: EdgeInsets.zero,
                ),
                SizedBox(height: 6),
                BullShimmerLine(
                  width: 110,
                  height: 12,
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FailureHistory extends StatelessWidget {
  final VoidCallback onRetry;

  const _FailureHistory({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BullIcon(Icons.error_outline, size: 48, color: colors.error),
            const Gap(16),
            Text(
              context.loc.getPaidTransactionsUnavailable,
              textAlign: TextAlign.center,
            ),
            const Gap(24),
            BullButton.small(
              label: context.loc.getPaidTransactionsRetry,
              iconData: Icons.refresh,
              iconFirst: true,
              onPressed: onRetry,
              bgColor: colors.secondary,
              textColor: colors.onSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  final Future<void> Function() onRefresh;

  const _EmptyHistory({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          const Gap(64),
          BullIcon(Icons.payments_outlined, size: 56, color: colors.textMuted),
          const Gap(16),
          Text(
            context.loc.getPaidTransactionsEmptyTitle,
            textAlign: TextAlign.center,
            style: context.bullText.titleLarge,
          ),
          const Gap(8),
          Text(
            context.loc.getPaidTransactionsEmptyBody,
            textAlign: TextAlign.center,
            style: context.bullText.bodyMedium?.copyWith(
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

IconData getPaidTransactionSourceIcon(GetPaidTransactionSource source) {
  return switch (source) {
    GetPaidTransactionSource.lightningAddress => Icons.alternate_email,
    GetPaidTransactionSource.invoice => Icons.receipt_long,
    GetPaidTransactionSource.paymentPage => Icons.storefront,
    GetPaidTransactionSource.pointOfSale => Icons.point_of_sale,
  };
}

String getPaidTransactionSourceText(
  BuildContext context,
  GetPaidTransactionSource source,
) {
  return switch (source) {
    GetPaidTransactionSource.lightningAddress =>
      context.loc.getPaidTransactionsSourceLightningAddress,
    GetPaidTransactionSource.invoice =>
      context.loc.getPaidTransactionsSourceInvoice,
    GetPaidTransactionSource.paymentPage =>
      context.loc.getPaidTransactionsSourcePaymentPage,
    GetPaidTransactionSource.pointOfSale =>
      context.loc.getPaidTransactionsSourcePointOfSale,
  };
}

/// The asset received, derived faithfully from the authoritative rail: Liquid
/// settles L-BTC; on-chain and Lightning are BTC. Never a fabricated ticker.
String getPaidTransactionAssetText(
  BuildContext context,
  GetPaidTransactionRail rail,
) {
  return switch (rail) {
    GetPaidTransactionRail.liquid => context.loc.getPaidTransactionsAssetLiquid,
    GetPaidTransactionRail.lightning || GetPaidTransactionRail.bitcoin =>
      context.loc.getPaidTransactionsAssetBitcoin,
  };
}

String getPaidTransactionRailText(
  BuildContext context,
  GetPaidTransactionRail rail,
) {
  return switch (rail) {
    GetPaidTransactionRail.lightning =>
      context.loc.getPaidTransactionsRailLightning,
    GetPaidTransactionRail.liquid => context.loc.getPaidTransactionsRailLiquid,
    GetPaidTransactionRail.bitcoin =>
      context.loc.getPaidTransactionsRailBitcoin,
  };
}

/// Coarse settlement classification label for the history list. `unavailable`
/// (uninterpretable) shows the explicit unavailable string — never silently a
/// Bitcoin label. The no-data case is handled by the caller omitting the label.
String getPaidSettlementKindLabel(
  BuildContext context,
  GetPaidSettlementKind kind,
) {
  return switch (kind) {
    GetPaidSettlementKind.bitcoin => context.loc.getPaidSettlementLabelBitcoin,
    GetPaidSettlementKind.fiat => context.loc.getPaidSettlementLabelFiat,
    GetPaidSettlementKind.mixed => context.loc.getPaidSettlementLabelMixed,
    GetPaidSettlementKind.unavailable =>
      context.loc.getPaidSettlementDetailsUnavailable,
  };
}

String getPaidSettlementStateText(
  BuildContext context,
  GetPaidSettlementState state,
) {
  return switch (state) {
    GetPaidSettlementState.pending =>
      context.loc.getPaidTransactionsStatePending,
    GetPaidSettlementState.settled =>
      context.loc.getPaidTransactionsStateSettled,
    GetPaidSettlementState.problem =>
      context.loc.getPaidTransactionsStateProblem,
  };
}

String getPaidTransactionAmountText(BuildContext context, int amountSat) {
  final formatted = NumberFormat.decimalPattern(
    Localizations.localeOf(context).toLanguageTag(),
  ).format(amountSat);
  return context.loc.getPaidTransactionsAmountSats(formatted);
}

String getPaidTransactionDateText(BuildContext context, DateTime receivedAt) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  return DateFormat.yMMMd(locale).add_jm().format(receivedAt.toLocal());
}

/// Day-group header label matching the wallet-history vocabulary: Today /
/// Yesterday for the two most recent local days, otherwise a formatted date
/// (month + day within this year, month + day + year before that).
String getPaidDayGroupLabel(BuildContext context, DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  if (day.isAtSameMomentAs(today)) {
    return context.loc.getPaidTransactionsDayToday;
  }
  if (day.isAtSameMomentAs(yesterday)) {
    return context.loc.getPaidTransactionsDayYesterday;
  }
  final locale = Localizations.localeOf(context).toLanguageTag();
  return day.year == now.year
      ? DateFormat.MMMMd(locale).format(day)
      : DateFormat.yMMMMd(locale).format(day);
}

/// The settled fiat amount for a fiat/mixed settlement, shown inline on a list
/// row once a fiat leg has settled (Q24a). Null when there is no settled fiat
/// leg yet — the row never shows a guessed or pending amount.
String? getPaidSettledFiatInline(
  BuildContext context,
  GetPaidSettlement? settlement,
) {
  if (settlement == null) return null;
  if (settlement.kind != GetPaidSettlementKind.fiat &&
      settlement.kind != GetPaidSettlementKind.mixed) {
    return null;
  }
  for (final leg in settlement.fiat) {
    if (leg.status == GetPaidSettlementLegStatus.settled &&
        leg.amountMinor != null) {
      final minor = leg.amountMinor!;
      final major = minor ~/ 100;
      final cents = (minor % 100).toString().padLeft(2, '0');
      return context.loc.getPaidSettlementFiatAmount(
        '$major.$cents',
        leg.currency,
      );
    }
  }
  return null;
}
