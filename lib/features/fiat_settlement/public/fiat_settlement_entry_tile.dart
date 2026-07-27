import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/entities/fiat_settlement.dart';
import 'package:bb_mobile/features/fiat_settlement/presentation/fiat_settlement_entry_cubit.dart';
import 'package:bb_mobile/features/fiat_settlement/public/fiat_settlement_routes.dart';
import 'package:bb_mobile/features/fiat_settlement/ui/fiat_settlement_copy.dart';
import 'package:bb_mobile/locator.dart';
import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// A self-contained "Fiat conversion" row a product screen can drop in. It is
/// MAINNET-ONLY (renders nothing on testnet), loads the product's current
/// settlement summary, and opens the shared editor, refreshing on return.
///
/// The public wrapper owns the feature Cubit's lifecycle; the view itself only
/// renders state and forwards user intent.
class FiatSettlementEntryTile extends StatelessWidget {
  const FiatSettlementEntryTile({
    super.key,
    required this.product,
    this.onConfigurationChanged,
  });

  final FiatSettlementProduct product;
  final Future<void> Function()? onConfigurationChanged;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<FiatSettlementEntryCubit>(
      create: (_) => locator<FiatSettlementEntryCubit>(param1: product)..load(),
      child: _FiatSettlementEntryView(
        product: product,
        onConfigurationChanged: onConfigurationChanged,
      ),
    );
  }
}

class _FiatSettlementEntryView extends StatelessWidget {
  const _FiatSettlementEntryView({
    required this.product,
    required this.onConfigurationChanged,
  });

  final FiatSettlementProduct product;
  final Future<void> Function()? onConfigurationChanged;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<FiatSettlementEntryCubit>().state;
    if (state.status != FiatSettlementEntryStatus.ready) {
      return const SizedBox.shrink();
    }
    final config = state.config;
    if (!state.unavailable && config == null) {
      return const SizedBox.shrink();
    }

    final colors = context.bull;
    // Honest summary: the confirmed configuration, or an explicit
    // status-unavailable line when the read failed. Never a fabricated
    // Bitcoin-only summary.
    final summary = state.unavailable || config == null
        ? context.loc.getPaidFiatSettlementStatusUnavailable
        : context.fiatSettlementSummary(config);
    return BullBorderedTile(
      key: const ValueKey('fiat-settlement-entry-tile'),
      onTap: () async {
        // Tapping always opens the editor; its own load-error/retry path
        // handles a still-unavailable configuration.
        await context.pushNamed(
          FiatSettlementRoute.fiatSettlementEditor.name,
          pathParameters: {'product': product.pathId},
        );
        if (!context.mounted) return;
        await context.read<FiatSettlementEntryCubit>().refresh();
        await onConfigurationChanged?.call();
      },
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          BullIcon(Icons.currency_exchange, size: 24, color: colors.primary),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.loc.getPaidFiatSettlementSectionTitle,
                  style: context.bullText.bodyMedium,
                ),
                const Gap(2),
                Text(
                  summary,
                  style: context.bullText.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          BullIcon(
            Icons.chevron_right,
            size: 20,
            color: colors.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
