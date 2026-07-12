import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/features/payment_recovery/domain/entities/stuck_payment.dart';
import 'package:bb_mobile/features/payment_recovery/domain/primitives/recovery_state.dart';
import 'package:bb_mobile/features/payment_recovery/presentation/stuck_payments_cubit.dart';
import 'package:bb_mobile/features/payment_recovery/presentation/stuck_payments_state.dart';
import 'package:bb_mobile/features/payment_recovery/public/payment_recovery_routes.dart';
import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Read-only list of payments needing recovery (Phase 2). The recover action
/// lands in Phase 3; here the merchant can see stuck payments and, when the
/// server recover flag is off (or too many rows), is told to contact support.
/// (User-facing copy is inline pending l10n keys in Phase 3.)
class StuckPaymentsScreen extends StatelessWidget {
  const StuckPaymentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.loc.stuckPaymentsScreenTitle)),
      body: SafeArea(
        child: BlocBuilder<StuckPaymentsCubit, StuckPaymentsState>(
          builder: (context, state) {
            final rows = state.needsAttention;
            return RefreshIndicator(
              onRefresh: context.read<StuckPaymentsCubit>().refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (!state.recoveryActionEnabled || state.hasMore)
                    const _ContactSupportBanner(),
                  if (rows.isEmpty)
                    const _EmptyState()
                  else
                    ...rows.map((p) => _StuckPaymentTile(payment: p)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        children: [
          BullIcon(Icons.check_circle_outline, size: 40, color: colors.success),
          const Gap(12),
          Text(
            context.loc.stuckPaymentsEmpty,
            style: context.bullText.bodyMedium?.copyWith(color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _ContactSupportBanner extends StatelessWidget {
  const _ContactSupportBanner();

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: BullBorderedTile(
        backgroundColor: colors.surfaceContainer,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BullIcon(Icons.info_outline, size: 20, color: colors.info),
            const Gap(12),
            Expanded(
              child: Text(
                context.loc.stuckPaymentsContactSupport,
                style: context.bullText.bodySmall?.copyWith(color: colors.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StuckPaymentTile extends StatelessWidget {
  final StuckPayment payment;

  const _StuckPaymentTile({required this.payment});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final (chipLabel, chipColor) = _chip(context, payment.state);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: BullBorderedTile(
        padding: const EdgeInsets.all(16),
        onTap: () => context.pushNamed(
          StuckPaymentsRoute.stuckPaymentDetail.name,
          pathParameters: {'id': payment.invoiceId},
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _amount(payment),
                    style: context.bullText.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.text,
                    ),
                  ),
                  const Gap(4),
                  Text(
                    payment.nym,
                    style: context.bullText.bodySmall?.copyWith(
                      color: colors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Gap(8),
            BullBadge(
              label: chipLabel,
              background: chipColor.withValues(alpha: 0.15),
              foreground: chipColor,
            ),
          ],
        ),
      ),
    );
  }

  String _amount(StuckPayment p) {
    if (p.fiatCurrency != null && p.fiatAmountMinor != null) {
      final major = (p.fiatAmountMinor! / 100).toStringAsFixed(2);
      return '$major ${p.fiatCurrency}';
    }
    if (p.amountSat != null) return '${p.amountSat} sats';
    return 'Payment';
  }

  (String, Color) _chip(BuildContext context, RecoveryState state) {
    final colors = context.bull;
    final loc = context.loc;
    return switch (state) {
      RecoveryState.detected ||
      RecoveryState.addressCommitted =>
        (loc.stuckPaymentChipNeedsRecovery, colors.warning),
      RecoveryState.recovering => (loc.stuckPaymentChipRecovering, colors.info),
      RecoveryState.recovered => (loc.stuckPaymentChipRecovered, colors.success),
      RecoveryState.failed => (loc.stuckPaymentChipAttention, colors.error),
      RecoveryState.inFlightUnknown =>
        (loc.stuckPaymentChipProcessing, colors.textMuted),
      RecoveryState.dismissed =>
        (loc.stuckPaymentChipDismissed, colors.textMuted),
    };
  }
}
