import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/core/widgets/navbar/top_bar.dart';
import 'package:bb_mobile/core/widgets/settings_entry_item.dart';
import 'package:bb_mobile/core/widgets/text/text.dart';
import 'package:bb_mobile/features/external_receive_wallets/public/external_receive_wallets.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_settings_cubit.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_settings_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

class GetPaidSettingsScreen extends StatelessWidget {
  final VoidCallback? onExternalReceiveSettingsChanged;
  final VoidCallback? onExternalReceiveWalletsCreated;

  const GetPaidSettingsScreen({
    super.key,
    this.onExternalReceiveSettingsChanged,
    this.onExternalReceiveWalletsCreated,
  });

  @override
  Widget build(BuildContext context) {
    return BlocSelector<
      GetPaidSettingsCubit,
      GetPaidSettingsState,
      ({bool blocksNavigation, bool isRecovering})
    >(
      selector: (state) => (
        blocksNavigation: state.blocksNavigation,
        isRecovering: state.isRestoringWallets,
      ),
      builder: (context, blockedBackState) {
        final blocksNavigation = blockedBackState.blocksNavigation;
        return PopScope(
          canPop: !blocksNavigation,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop || !blocksNavigation) return;
            _showOperationInProgress(
              context,
              isRecovering: blockedBackState.isRecovering,
            );
          },
          child: Scaffold(
            appBar: AppBar(
              forceMaterialTransparency: true,
              automaticallyImplyLeading: false,
              flexibleSpace: TopBar(
                title: context.loc.getPaidSettingsTitle,
                onBack: blocksNavigation
                    ? () => _showOperationInProgress(
                        context,
                        isRecovering: blockedBackState.isRecovering,
                      )
                    : () => context.pop(),
              ),
            ),
            body: SafeArea(
              child: BlocBuilder<GetPaidSettingsCubit, GetPaidSettingsState>(
                builder: (context, state) {
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (state.isLoadingSettings) ...[
                        const Center(child: CircularProgressIndicator()),
                        const Gap(16),
                      ],
                      if (state.loadFailed) ...[
                        Text(
                          context.loc.getPaidSettingsLoadError,
                          style: context.font.bodySmall?.copyWith(
                            color: context.appColors.error,
                          ),
                        ),
                        TextButton(
                          onPressed: state.operationInProgress
                              ? null
                              : context.read<GetPaidSettingsCubit>().load,
                          child: Text(context.loc.getPaidSettingsRetry),
                        ),
                        const Gap(12),
                      ],
                      if (!state.isLoadingSettings && !state.loadFailed) ...[
                        _WalletSettingsSection(
                          title: context.loc.lightningAddressTitle,
                          autoSweepValue: state.lightningAddressLiquidAutoSweep,
                          hideWalletValue:
                              state.lightningAddressLiquidHideWallet,
                          enabled: !state.operationInProgress,
                          onAutoSweepChanged: context
                              .read<GetPaidSettingsCubit>()
                              .setLightningAddressAutoSweep,
                          onHideWalletChanged: (value) async {
                            final saved = await context
                                .read<GetPaidSettingsCubit>()
                                .setLightningAddressHideWallet(value);
                            if (saved && context.mounted) {
                              onExternalReceiveSettingsChanged?.call();
                            }
                          },
                        ),
                        const Gap(20),
                        _WalletSettingsSection(
                          title: context.loc.getPaidSettingsPaymentPage,
                          autoSweepValue: state.paymentPageAutoSweep,
                          hideWalletValue: state.paymentPageHideWallet,
                          enabled: !state.operationInProgress,
                          onAutoSweepChanged: context
                              .read<GetPaidSettingsCubit>()
                              .setPaymentPageAutoSweep,
                          onHideWalletChanged: (value) async {
                            final saved = await context
                                .read<GetPaidSettingsCubit>()
                                .setPaymentPageHideWallet(value);
                            if (saved && context.mounted) {
                              onExternalReceiveSettingsChanged?.call();
                            }
                          },
                        ),
                        const Gap(20),
                        _WalletSettingsSection(
                          title: '${context.loc.getPaidSettingsBTCPay} Liquid',
                          autoSweepValue: state.btcpayLiquidAutoSweep,
                          hideWalletValue: state.btcpayLiquidHideWallet,
                          enabled: !state.operationInProgress,
                          onAutoSweepChanged: context
                              .read<GetPaidSettingsCubit>()
                              .setBtcpayLiquidAutoSweep,
                          onHideWalletChanged: (value) async {
                            final saved = await context
                                .read<GetPaidSettingsCubit>()
                                .setBtcpayLiquidHideWallet(value);
                            if (saved && context.mounted) {
                              onExternalReceiveSettingsChanged?.call();
                            }
                          },
                        ),
                        const Gap(20),
                        _WalletSettingsSection(
                          title: '${context.loc.getPaidSettingsBTCPay} Bitcoin',
                          autoSweepValue: state.btcpayBitcoinAutoSweep,
                          hideWalletValue: state.btcpayBitcoinHideWallet,
                          enabled: !state.operationInProgress,
                          onAutoSweepChanged: context
                              .read<GetPaidSettingsCubit>()
                              .setBtcpayBitcoinAutoSweep,
                          onHideWalletChanged: (value) async {
                            final saved = await context
                                .read<GetPaidSettingsCubit>()
                                .setBtcpayBitcoinHideWallet(value);
                            if (saved && context.mounted) {
                              onExternalReceiveSettingsChanged?.call();
                            }
                          },
                        ),
                        if (state.saveFailed) ...[
                          const Gap(8),
                          Text(
                            context.loc.getPaidSettingsSaveError,
                            style: context.font.bodySmall?.copyWith(
                              color: context.appColors.error,
                            ),
                          ),
                        ],
                      ],
                      const Gap(24),
                      SettingsEntryItem(
                        icon: Icons.restore,
                        title: context.loc.getPaidSettingsRecoverWallets,
                        onTap: state.operationInProgress
                            ? null
                            : () => _confirmRestoreGetPaidWallets(
                                context,
                                onExternalReceiveWalletsCreated:
                                    onExternalReceiveWalletsCreated,
                              ),
                        trailing: state.isRestoringWallets
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: BBText(
                          context.loc.getPaidSettingsRecoverWalletsDescription,
                          style: context.font.bodySmall?.copyWith(
                            color: context.appColors.textMuted,
                          ),
                        ),
                      ),
                      const Gap(12),
                      if (state.restoreFailed) const _ErrorMessage(),
                      if (state.restoreOutcomes != null)
                        _RestoreResultCard(outcomes: state.restoreOutcomes!),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

void _showOperationInProgress(
  BuildContext context, {
  required bool isRecovering,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        isRecovering
            ? context.loc.getPaidSettingsRecoverOperationInProgress
            : context.loc.getPaidSettingsOperationInProgress,
      ),
    ),
  );
}

void _showBottomSheet(BuildContext context, String title, String content) {
  showModalBottomSheet(
    context: context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(ctx).textTheme.titleMedium),
          const Gap(16),
          Text(content),
          const Gap(24),
        ],
      ),
    ),
  );
}

class _WalletSettingsSection extends StatelessWidget {
  final String title;
  final bool? autoSweepValue;
  final bool hideWalletValue;
  final bool enabled;
  final ValueChanged<bool>? onAutoSweepChanged;
  final ValueChanged<bool> onHideWalletChanged;

  const _WalletSettingsSection({
    required this.title,
    this.autoSweepValue,
    required this.hideWalletValue,
    required this.enabled,
    this.onAutoSweepChanged,
    required this.onHideWalletChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: context.font.titleSmall),
        const Gap(8),
        if (autoSweepValue != null && onAutoSweepChanged != null) ...[
          _SettingsSwitchTile(
            title: context.loc.getPaidSettingsAutoSweep,
            subtitle: context.loc.getPaidSettingsAutoSweepSub,
            value: autoSweepValue!,
            enabled: enabled,
            onChanged: onAutoSweepChanged!,
            onInfoTap: () => _showBottomSheet(
              context,
              context.loc.getPaidSettingsAutoSweep,
              context.loc.getPaidSettingsAutoSweepInfo,
            ),
            tooltip: context.loc.getPaidSettingsAutoSweep,
          ),
          const Gap(12),
        ],
        _SettingsSwitchTile(
          title: context.loc.getPaidSettingsHideWallet,
          subtitle: context.loc.getPaidSettingsHideWalletSub,
          value: hideWalletValue,
          enabled: enabled,
          onChanged: onHideWalletChanged,
          onInfoTap: () => _showBottomSheet(
            context,
            context.loc.getPaidSettingsHideWallet,
            context.loc.getPaidSettingsHideWalletInfo,
          ),
          tooltip: context.loc.getPaidSettingsHideWallet,
        ),
      ],
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final VoidCallback onInfoTap;
  final String tooltip;

  const _SettingsSwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.onInfoTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: Text(title, maxLines: 2)),
            IconButton(
              icon: const Icon(Icons.info_outline, size: 20),
              onPressed: onInfoTap,
              tooltip: tooltip,
            ),
            Switch(value: value, onChanged: enabled ? onChanged : null),
          ],
        ),
        subtitle: Text(subtitle),
      ),
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage();

  @override
  Widget build(BuildContext context) {
    return Text(
      context.loc.getPaidSettingsRecoverError,
      style: context.font.bodyMedium?.copyWith(color: context.appColors.error),
    );
  }
}

class _RestoreResultCard extends StatelessWidget {
  final List<ExternalReceiveWalletRestoreOutcome> outcomes;

  const _RestoreResultCard({required this.outcomes});

  @override
  Widget build(BuildContext context) {
    final hasAttention = outcomes.any(
      (outcome) =>
          outcome.status == ExternalReceiveWalletRestoreOutcomeStatus.failed,
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: context.appColors.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasAttention
                ? context.loc.getPaidSettingsWalletRecoveryNeedsAttention
                : context.loc.getPaidSettingsWalletRecoveryComplete,
            style: context.font.titleSmall,
          ),
          const Gap(12),
          for (final outcome in outcomes) ...[
            _RestoreOutcomeRow(outcome: outcome),
            if (outcome != outcomes.last) const Gap(8),
          ],
        ],
      ),
    );
  }
}

class _RestoreOutcomeRow extends StatelessWidget {
  final ExternalReceiveWalletRestoreOutcome outcome;

  const _RestoreOutcomeRow({required this.outcome});

  @override
  Widget build(BuildContext context) {
    final isFailure =
        outcome.status == ExternalReceiveWalletRestoreOutcomeStatus.failed;
    final iconColor = isFailure
        ? context.appColors.error
        : context.appColors.success;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isFailure ? Icons.error_outline : Icons.check_circle_outline,
          color: iconColor,
          size: 20,
        ),
        const Gap(8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _walletLabel(context, outcome),
                style: context.font.bodyMedium,
              ),
              const Gap(2),
              Text(
                _statusLabel(context, outcome),
                style: context.font.bodySmall?.copyWith(
                  color: isFailure ? iconColor : context.appColors.secondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _walletLabel(
  BuildContext context,
  ExternalReceiveWalletRestoreOutcome outcome,
) {
  final network = outcome.accountKey.network.isLiquid
      ? context.loc.receiveLiquid
      : context.loc.receiveBitcoin;
  final purpose = switch (outcome.accountKey.purpose) {
    ExternalReceiveWalletPurpose.lightningAddress =>
      context.loc.lightningAddressTitle,
    ExternalReceiveWalletPurpose.paymentPage =>
      context.loc.getPaidSettingsPaymentPage,
    ExternalReceiveWalletPurpose.btcpay => context.loc.getPaidSettingsBTCPay,
  };
  return '$purpose $network';
}

String _statusLabel(
  BuildContext context,
  ExternalReceiveWalletRestoreOutcome outcome,
) {
  switch (outcome.status) {
    case ExternalReceiveWalletRestoreOutcomeStatus.existing:
      return context.loc.getPaidSettingsStatusAlreadyPresent;
    case ExternalReceiveWalletRestoreOutcomeStatus.repaired:
      return context.loc.getPaidSettingsStatusRefreshed;
    case ExternalReceiveWalletRestoreOutcomeStatus.created:
      return context.loc.getPaidSettingsStatusAdded;
    case ExternalReceiveWalletRestoreOutcomeStatus.failed:
      return _failureLabel(context, outcome);
  }
}

String _failureLabel(
  BuildContext context,
  ExternalReceiveWalletRestoreOutcome outcome,
) {
  return switch (outcome.failureReason) {
    ExternalReceiveWalletRestoreFailureReason.noDefaultWallet =>
      context.loc.getPaidSettingsFailureNoDefaultWallet,
    ExternalReceiveWalletRestoreFailureReason.alreadyExistsRace =>
      context.loc.getPaidSettingsFailureAlreadyExistsRace,
    ExternalReceiveWalletRestoreFailureReason.metadataUpdateFailed =>
      context.loc.getPaidSettingsFailureMetadataUpdateFailed,
    ExternalReceiveWalletRestoreFailureReason.walletCreationFailed =>
      context.loc.getPaidSettingsFailureWalletCreationFailed,
    null => context.loc.getPaidSettingsFailureUnknown,
  };
}

Future<void> _confirmRestoreGetPaidWallets(
  BuildContext context, {
  VoidCallback? onExternalReceiveWalletsCreated,
}) async {
  final cubit = context.read<GetPaidSettingsCubit>();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: dialogContext.appColors.surface,
      title: Text(
        dialogContext.loc.getPaidSettingsRecoverConfirmTitle,
        style: dialogContext.font.headlineSmall?.copyWith(
          color: dialogContext.appColors.onSurface,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Text(
        dialogContext.loc.getPaidSettingsRecoverConfirmDescription,
        style: dialogContext.font.bodyMedium?.copyWith(
          color: dialogContext.appColors.onSurface,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(dialogContext.loc.getPaidSettingsRecoverConfirmCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(
            dialogContext.loc.getPaidSettingsRecoverConfirmAction,
            style: dialogContext.font.bodyMedium?.copyWith(
              color: dialogContext.appColors.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await cubit.restoreGetPaidWallets();
  if (!context.mounted) return;
  final outcomes = cubit.state.restoreOutcomes;
  if (outcomes == null || !_restoreChangedWallets(outcomes)) return;
  onExternalReceiveWalletsCreated?.call();
}

bool _restoreChangedWallets(
  List<ExternalReceiveWalletRestoreOutcome> outcomes,
) {
  return outcomes.any(
    (outcome) =>
        outcome.status == ExternalReceiveWalletRestoreOutcomeStatus.created ||
        outcome.status == ExternalReceiveWalletRestoreOutcomeStatus.repaired,
  );
}
