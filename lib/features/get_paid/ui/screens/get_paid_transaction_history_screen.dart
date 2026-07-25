import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/core/widgets/snackbar_utils.dart';
import 'package:bb_mobile/features/bitcoin_price/ui/currency_text.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_settlement.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_transaction.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_export_cubit.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_export_state.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_transaction_history_cubit.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_transaction_history_state.dart';
import 'package:bb_mobile/features/get_paid/public/get_paid_routes.dart';
import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;

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
        child: BlocListener<GetPaidExportCubit, GetPaidExportState>(
          listenWhen: (previous, current) => previous.status != current.status,
          listener: (context, state) {
            switch (state.status) {
              case GetPaidExportStatus.loading:
                SnackBarUtils.showSnackBar(
                  context,
                  context.loc.getPaidTransactionsExportStarted,
                );
              case GetPaidExportStatus.success:
                SnackBarUtils.showSnackBar(
                  context,
                  context.loc.getPaidTransactionsExportSuccess,
                );
              case GetPaidExportStatus.empty:
                SnackBarUtils.showSnackBar(
                  context,
                  context.loc.getPaidTransactionsExportEmpty,
                );
              case GetPaidExportStatus.failure:
                SnackBarUtils.showSnackBar(
                  context,
                  context.loc.getPaidTransactionsExportError,
                );
              case GetPaidExportStatus.initial:
                break;
            }
          },
          child: Column(
            children: [
              BullTopBar(
                title: context.loc.getPaidTransactionsTitle,
                onBack: context.pop,
                actionIcon: Icons.file_download_outlined,
                onAction: () =>
                    context.read<GetPaidExportCubit>().exportCsv(),
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

/// One Get Paid receipt, sharing the wallet transaction list's visual grammar
/// (bordered icon, amount, source chip, network pill, timeago) without reusing
/// the wallet Transaction widgets. Every Get Paid row is a receive, so the
/// leading glyph is always a down-arrow. Settled rows stay quiet, like a
/// confirmed wallet row; only a payment that needs action carries a chip.
class _TransactionRow extends StatelessWidget {
  final GetPaidTransaction transaction;
  final VoidCallback onTap;

  const _TransactionRow({required this.transaction, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final needsAttention =
        transaction.settlementState == GetPaidSettlementState.problem;
    final pill = getPaidSettlementPill(context, transaction);
    return InkWell(
      key: ValueKey('get-paid-transaction-${transaction.stableKey}'),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8.0),
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: context.appColors.surface,
          borderRadius: BorderRadius.circular(2.0),
          boxShadow: const [],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: context.appColors.surface,
                border: Border.all(color: context.appColors.border),
                borderRadius: BorderRadius.circular(2.0),
              ),
              child: Icon(
                Icons.arrow_downward,
                color: context.appColors.onSurface,
              ),
            ),
            const Gap(16.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CurrencyText(
                    transaction.amountSat,
                    showFiat: false,
                    style: context.font.bodyLarge,
                  ),
                  const Gap(4.0),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 4.0,
                    children: [
                      _RowChip(
                        text: getPaidTransactionSourceText(
                          context,
                          transaction.source,
                        ),
                      ),
                      if (needsAttention)
                        _RowChip(
                          text: context.loc.getPaidTransactionsStateProblem,
                          accent: context.appColors.error,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4.0,
                    vertical: 2.0,
                  ),
                  decoration: BoxDecoration(
                    color: pill.color,
                    borderRadius: BorderRadius.circular(2.0),
                  ),
                  child: Text(
                    pill.text,
                    style: context.font.labelSmall?.copyWith(
                      color: context.appColors.onSurface,
                    ),
                  ),
                ),
                const Gap(4.0),
                Text(
                  timeago.format(transaction.receivedAt.toLocal()),
                  style: context.font.labelSmall?.copyWith(
                    color: context.appColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Small pill mirroring the wallet list's label chips. [accent] tints the
/// border and text for a chip that needs to stand out (needs-attention).
class _RowChip extends StatelessWidget {
  final String text;
  final Color? accent;

  const _RowChip({required this.text, this.accent});

  @override
  Widget build(BuildContext context) {
    final foreground = accent ?? context.appColors.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
      decoration: BoxDecoration(
        color: context.appColors.onSecondary,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(
          color: accent ?? context.appColors.secondaryFixedDim,
        ),
      ),
      child: Text(
        text,
        style: context.font.labelSmall?.copyWith(color: foreground),
      ),
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

/// The settlement-kind pill for a history row. Precedence:
/// A trustworthy server-provided settlement kind wins. Missing or unavailable
/// historical evidence remains unclassified and falls back to the captured
/// payment rail; current product settings must never relabel an old payment.
({String text, Color color}) getPaidSettlementPill(
  BuildContext context,
  GetPaidTransaction transaction,
) {
  final kind = transaction.settlement?.kind;
  if (kind != null && kind != GetPaidSettlementKind.unavailable) {
    return _settlementKindPill(context, kind);
  }
  return (
    text: getPaidTransactionRailText(context, transaction.rail),
    color: transaction.rail == GetPaidTransactionRail.liquid
        ? context.appColors.tertiary
        : context.appColors.onTertiary,
  );
}

/// Kind pills reuse the rail pill's two container colors — the accent fill for a
/// fiat-touching settlement (fiat / mixed), the plain fill for Bitcoin — so no
/// new color system is introduced. `unavailable` never reaches here (the caller
/// resolves it via the expected-kind map or the rail fallback first); it is
/// grouped with Bitcoin only to keep the switch exhaustive.
({String text, Color color}) _settlementKindPill(
  BuildContext context,
  GetPaidSettlementKind kind,
) {
  final fiatTouching =
      kind == GetPaidSettlementKind.fiat || kind == GetPaidSettlementKind.mixed;
  final text = switch (kind) {
    GetPaidSettlementKind.mixed => context.loc.getPaidSettlementKindMixed,
    GetPaidSettlementKind.fiat => context.loc.getPaidSettlementLabelFiat,
    GetPaidSettlementKind.bitcoin || GetPaidSettlementKind.unavailable =>
      context.loc.getPaidSettlementLabelBitcoin,
  };
  return (
    text: text,
    color: fiatTouching
        ? context.appColors.tertiary
        : context.appColors.onTertiary,
  );
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
