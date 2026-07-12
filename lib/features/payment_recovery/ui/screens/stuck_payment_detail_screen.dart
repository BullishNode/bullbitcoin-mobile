import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/features/payment_recovery/domain/entities/stuck_payment.dart';
import 'package:bb_mobile/features/payment_recovery/domain/primitives/recovery_state.dart';
import 'package:bb_mobile/features/payment_recovery/presentation/stuck_payment_detail_cubit.dart';
import 'package:bb_mobile/features/payment_recovery/presentation/stuck_payment_detail_state.dart';
import 'package:bb_mobile/features/payment_recovery/ui/widgets/recover_confirm_sheet.dart';
import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_bloc/flutter_bloc.dart';

/// One stuck payment: explains it, and (when the server recover flag is on)
/// offers the single "Recover to my wallet" action behind a confirm sheet that
/// carries the out-of-band "settle at the till" notice. Read-only + "contact
/// support" when recovery isn't available. (Copy inline pending l10n.)
class StuckPaymentDetailScreen extends StatelessWidget {
  const StuckPaymentDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.loc.stuckPaymentDetailTitle)),
      body: SafeArea(
        child: BlocBuilder<StuckPaymentDetailCubit, StuckPaymentDetailState>(
          builder: (context, state) {
            final p = state.payment;
            if (p == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Explainer(payment: p),
                  const Gap(24),
                  if (p.state == RecoveryState.recovered)
                    _RecoveredPanel(payment: p)
                  else
                    _ActionArea(state: state, payment: p),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Explainer extends StatelessWidget {
  final StuckPayment payment;
  const _Explainer({required this.payment});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          amountLabel(payment),
          style: context.bullText.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.text,
          ),
        ),
        const Gap(8),
        Text(
          context.loc.stuckPaymentDetailExplainer,
          style: context.bullText.bodyMedium?.copyWith(color: colors.textMuted),
        ),
      ],
    );
  }
}

class _ActionArea extends StatelessWidget {
  final StuckPaymentDetailState state;
  final StuckPayment payment;
  const _ActionArea({required this.state, required this.payment});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;

    if (payment.state == RecoveryState.recovering || state.isBusy) {
      return Column(
        children: [
          const CircularProgressIndicator(),
          const Gap(12),
          Text(
            context.loc.stuckPaymentRecoveringInline,
            style: context.bullText.bodySmall?.copyWith(color: colors.textMuted),
          ),
        ],
      );
    }

    if (!state.recoveryActionEnabled || state.hasMore) {
      return BullBorderedTile(
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
      );
    }

    return BullButton.big(
      label: context.loc.stuckPaymentRecoverButton,
      onPressed: () => _confirm(context),
      bgColor: colors.primary,
      textColor: colors.onPrimary,
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final cubit = context.read<StuckPaymentDetailCubit>();
    final confirmed = await showRecoverConfirmSheet(
      context,
      amountLabel: amountLabel(payment),
    );
    if (confirmed == true) await cubit.recover();
  }
}

class _RecoveredPanel extends StatelessWidget {
  final StuckPayment payment;
  const _RecoveredPanel({required this.payment});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            BullIcon(Icons.check_circle, size: 20, color: colors.success),
            const Gap(8),
            Text(
              context.loc.stuckPaymentRecoveredTitle,
              style: context.bullText.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.text,
              ),
            ),
          ],
        ),
        const Gap(12),
        if (payment.refundTxid != null)
          BullBorderedTile(
            onTap: () => Clipboard.setData(
              ClipboardData(text: payment.refundTxid!),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    payment.refundTxid!,
                    style: context.bullText.bodySmall?.copyWith(
                      color: colors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Gap(8),
                BullIcon(Icons.copy, size: 16, color: colors.textMuted),
              ],
            ),
          ),
        const Gap(16),
        // The honesty requirement: recovery ≠ the customer being made whole.
        BullBorderedTile(
          backgroundColor: colors.warningContainer,
          child: Text(
            context.loc.stuckPaymentOutOfBandNotice,
            style: context.bullText.bodySmall?.copyWith(color: colors.text),
          ),
        ),
        const Gap(16),
        if (!payment.acknowledged)
          BullButton.big(
            label: context.loc.stuckPaymentAcknowledge,
            onPressed: () =>
                context.read<StuckPaymentDetailCubit>().acknowledge(),
            bgColor: colors.transparent,
            textColor: colors.text,
            outlined: true,
          ),
      ],
    );
  }
}

String amountLabel(StuckPayment p) {
  if (p.fiatCurrency != null && p.fiatAmountMinor != null) {
    final major = (p.fiatAmountMinor! / 100).toStringAsFixed(2);
    return '$major ${p.fiatCurrency}';
  }
  if (p.amountSat != null) return '${p.amountSat} sats';
  return 'Payment';
}
