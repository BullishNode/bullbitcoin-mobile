import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/core/widgets/inputs/copy_input.dart';
import 'package:bb_mobile/core/widgets/navbar/top_bar.dart';
import 'package:bb_mobile/core/widgets/settings_entry_item.dart';
import 'package:bb_mobile/core/widgets/text/text.dart';
import 'package:bb_mobile/features/wallet_manifest/presentation/wallet_manifest_settings_cubit.dart';
import 'package:bb_mobile/features/wallet_manifest/presentation/wallet_manifest_settings_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

class WalletManifestSettingsScreen extends StatelessWidget {
  final VoidCallback? onWalletsRestored;

  const WalletManifestSettingsScreen({super.key, this.onWalletsRestored});

  @override
  Widget build(BuildContext context) {
    return BlocSelector<
      WalletManifestSettingsCubit,
      WalletManifestSettingsState,
      bool
    >(
      selector: (state) => state.manifestOperationInProgress,
      builder: (context, operationInProgress) {
        return PopScope(
          canPop: !operationInProgress,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop || !operationInProgress) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.loc.walletManifestSettingsOperationInProgress,
                ),
              ),
            );
          },
          child: Scaffold(
            appBar: AppBar(
              forceMaterialTransparency: true,
              automaticallyImplyLeading: false,
              flexibleSpace: TopBar(
                title: context.loc.walletManifestSettingsScreenTitle,
                onBack: operationInProgress
                    ? () => _showOperationInProgress(context)
                    : () => context.pop(),
              ),
            ),
            body: SafeArea(
              child:
                  BlocBuilder<
                    WalletManifestSettingsCubit,
                    WalletManifestSettingsState
                  >(
                    builder: (context, state) {
                      if (state.loading && state.npub == null) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final npub = state.npub;
                      if (state.failed && npub == null) {
                        return _ErrorState(
                          onRetry: state.loading
                              ? null
                              : () => context
                                    .read<WalletManifestSettingsCubit>()
                                    .load(),
                        );
                      }

                      if (npub == null) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      return ListView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 24,
                        ),
                        children: [
                          BBText(
                            context.loc.walletManifestSettingsDescription,
                            style: context.font.bodyMedium?.copyWith(
                              color: context.appColors.textMuted,
                            ),
                          ),
                          const Gap(16),
                          _LatestOperationStatus(state: state),
                          const Gap(24),
                          BBText(
                            context.loc.walletManifestSettingsNpubLabel,
                            style: context.font.bodyMedium?.copyWith(
                              color: context.appColors.textMuted,
                            ),
                          ),
                          const Gap(4),
                          BBText(
                            context.loc.walletManifestSettingsNpubDescription,
                            style: context.font.bodySmall?.copyWith(
                              color: context.appColors.textMuted,
                            ),
                          ),
                          const Gap(8),
                          CopyInput(
                            text: npub,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            canShowValueModal: true,
                            modalTitle:
                                context.loc.walletManifestSettingsNpubLabel,
                          ),
                          const Gap(24),
                          SettingsEntryItem(
                            icon: Icons.cloud_download_outlined,
                            title:
                                context.loc.walletManifestSettingsCheckRemote,
                            onTap: state.manifestOperationInProgress
                                ? null
                                : context
                                      .read<WalletManifestSettingsCubit>()
                                      .checkRemoteManifest,
                            iconColor:
                                state.manifestOperationInProgress &&
                                    !state.checkingRemote
                                ? context.appColors.textMuted
                                : null,
                            textColor:
                                state.manifestOperationInProgress &&
                                    !state.checkingRemote
                                ? context.appColors.textMuted
                                : null,
                            trailing: state.checkingRemote
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : state.manifestOperationInProgress
                                ? const SizedBox.shrink()
                                : null,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: BBText(
                              context
                                  .loc
                                  .walletManifestSettingsCheckRemoteDescription,
                              style: context.font.bodySmall?.copyWith(
                                color: context.appColors.textMuted,
                              ),
                            ),
                          ),
                          const Gap(16),
                          if (state.remoteCheckStatus ==
                              WalletManifestRemoteCheckStatus.failed)
                            _InlineMessage(
                              text:
                                  context.loc.walletManifestSettingsCheckFailed,
                              color: context.appColors.error,
                            ),
                          if (state.remoteCheckStatus ==
                              WalletManifestRemoteCheckStatus.missing)
                            _InlineMessage(
                              text: context
                                  .loc
                                  .walletManifestSettingsCheckMissing,
                              color: context.appColors.textMuted,
                            ),
                          SettingsEntryItem(
                            icon: Icons.fact_check_outlined,
                            title:
                                context.loc.walletManifestSettingsAuditRemote,
                            onTap: state.manifestOperationInProgress
                                ? null
                                : context
                                      .read<WalletManifestSettingsCubit>()
                                      .auditRemoteManifest,
                            iconColor:
                                state.manifestOperationInProgress &&
                                    !state.auditing
                                ? context.appColors.textMuted
                                : null,
                            textColor:
                                state.manifestOperationInProgress &&
                                    !state.auditing
                                ? context.appColors.textMuted
                                : null,
                            trailing: state.auditing
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : state.manifestOperationInProgress
                                ? const SizedBox.shrink()
                                : null,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: BBText(
                              context
                                  .loc
                                  .walletManifestSettingsAuditRemoteDescription,
                              style: context.font.bodySmall?.copyWith(
                                color: context.appColors.textMuted,
                              ),
                            ),
                          ),
                          const Gap(16),
                          if (state.auditStatus ==
                              WalletManifestAuditStatus.failed)
                            _InlineMessage(
                              text:
                                  context.loc.walletManifestSettingsAuditFailed,
                              color: context.appColors.error,
                            ),
                          if (state.auditStatus ==
                              WalletManifestAuditStatus.missing)
                            _InlineMessage(
                              text: context.loc
                                  .walletManifestSettingsAuditMissing(
                                    state.auditMissingRemoteCount ?? 0,
                                  ),
                              color: context.appColors.textMuted,
                            ),
                          if (state.auditStatus ==
                              WalletManifestAuditStatus.matches)
                            _InlineMessage(
                              text: context.loc
                                  .walletManifestSettingsAuditMatches(
                                    state.auditMatchingCount ?? 0,
                                  ),
                              color: context.appColors.textMuted,
                            ),
                          if (state.auditStatus ==
                              WalletManifestAuditStatus.differs)
                            _InlineMessage(
                              text: context.loc
                                  .walletManifestSettingsAuditDiffers(
                                    state.auditMatchingCount ?? 0,
                                    state.auditMissingLocalCount ?? 0,
                                    state.auditMissingRemoteCount ?? 0,
                                  ),
                              color: context.appColors.error,
                            ),
                          if (state.remoteManifestJson != null) ...[
                            const Gap(16),
                            _RemoteManifestSection(state: state),
                          ],
                          const Gap(16),
                          SettingsEntryItem(
                            icon: Icons.cloud_upload_outlined,
                            title:
                                context.loc.walletManifestSettingsPublishLocal,
                            onTap: state.manifestOperationInProgress
                                ? null
                                : () => _confirmPublishLocalManifest(context),
                            iconColor:
                                state.manifestOperationInProgress &&
                                    !state.publishing
                                ? context.appColors.textMuted
                                : null,
                            textColor:
                                state.manifestOperationInProgress &&
                                    !state.publishing
                                ? context.appColors.textMuted
                                : null,
                            trailing: state.publishing
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : state.manifestOperationInProgress
                                ? const SizedBox.shrink()
                                : null,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: BBText(
                              context
                                  .loc
                                  .walletManifestSettingsPublishLocalDescription,
                              style: context.font.bodySmall?.copyWith(
                                color: context.appColors.textMuted,
                              ),
                            ),
                          ),
                          const Gap(16),
                          if (state.publishStatus ==
                              WalletManifestPublishStatus.failed)
                            _InlineMessage(
                              text: context
                                  .loc
                                  .walletManifestSettingsPublishFailed,
                              color: context.appColors.error,
                            ),
                          if (state.publishStatus ==
                              WalletManifestPublishStatus.succeeded)
                            Column(
                              crossAxisAlignment: .start,
                              children: [
                                _InlineMessage(
                                  text: context.loc
                                      .walletManifestSettingsPublishSucceeded(
                                        state.publishedManifestAccountCount ??
                                            0,
                                      ),
                                  color: context.appColors.textMuted,
                                ),
                                if (state.publishedManifestCreatedAt != null)
                                  _InlineMessage(
                                    text: context.loc
                                        .walletManifestSettingsLatestPublishStatus(
                                          _formatTimestamp(
                                            state.publishedManifestCreatedAt!,
                                          ),
                                        ),
                                    color: context.appColors.textMuted,
                                  ),
                              ],
                            ),
                          SettingsEntryItem(
                            icon: Icons.restore,
                            title:
                                context.loc.walletManifestSettingsRestoreRemote,
                            onTap: state.manifestOperationInProgress
                                ? null
                                : () => _confirmRestoreRemoteManifest(context),
                            iconColor:
                                state.manifestOperationInProgress &&
                                    !state.restoring
                                ? context.appColors.textMuted
                                : null,
                            textColor:
                                state.manifestOperationInProgress &&
                                    !state.restoring
                                ? context.appColors.textMuted
                                : null,
                            trailing: state.restoring
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : state.manifestOperationInProgress
                                ? const SizedBox.shrink()
                                : null,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: BBText(
                              context
                                  .loc
                                  .walletManifestSettingsRestoreRemoteDescription,
                              style: context.font.bodySmall?.copyWith(
                                color: context.appColors.textMuted,
                              ),
                            ),
                          ),
                          const Gap(16),
                          if (state.manualRestoreStatus ==
                              WalletManifestManualRestoreStatus.failed)
                            _InlineMessage(
                              text: context
                                  .loc
                                  .walletManifestSettingsRestoreFailed,
                              color: context.appColors.error,
                            ),
                          if (state.manualRestoreStatus ==
                              WalletManifestManualRestoreStatus.missing)
                            _InlineMessage(
                              text: context
                                  .loc
                                  .walletManifestSettingsRestoreMissing,
                              color: context.appColors.textMuted,
                            ),
                          if (state.manualRestoreStatus ==
                              WalletManifestManualRestoreStatus.completed)
                            _InlineMessage(
                              text: context.loc
                                  .walletManifestSettingsRestoreComplete(
                                    state.manualRestoreRestoredCount ?? 0,
                                    state.manualRestoreAlreadyPresentCount ?? 0,
                                  ),
                              color: context.appColors.textMuted,
                            ),
                          if (state.manualRestoreStatus ==
                              WalletManifestManualRestoreStatus.needsAttention)
                            _InlineMessage(
                              text: context.loc
                                  .walletManifestSettingsRestorePartial(
                                    state.manualRestoreRestoredCount ?? 0,
                                    state.manualRestoreAlreadyPresentCount ?? 0,
                                    state.manualRestoreSkippedCount ?? 0,
                                    state.manualRestoreFailedCount ?? 0,
                                  ),
                              color: context.appColors.error,
                            ),
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

  Future<void> _confirmPublishLocalManifest(BuildContext context) async {
    final cubit = context.read<WalletManifestSettingsCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.appColors.surface,
        title: Text(
          dialogContext.loc.walletManifestSettingsPublishConfirmTitle,
          style: dialogContext.font.headlineSmall?.copyWith(
            color: dialogContext.appColors.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          dialogContext.loc.walletManifestSettingsPublishConfirmDescription,
          style: dialogContext.font.bodyMedium?.copyWith(
            color: dialogContext.appColors.onSurface,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.loc.walletManifestSettingsCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              dialogContext.loc.walletManifestSettingsPublishConfirmAction,
              style: dialogContext.font.bodyMedium?.copyWith(
                color: dialogContext.appColors.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await cubit.publishLocalManifest();
  }

  void _showOperationInProgress(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.loc.walletManifestSettingsOperationInProgress),
      ),
    );
  }

  Future<void> _confirmRestoreRemoteManifest(BuildContext context) async {
    final cubit = context.read<WalletManifestSettingsCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.appColors.surface,
        title: Text(
          dialogContext.loc.walletManifestSettingsRestoreConfirmTitle,
          style: dialogContext.font.headlineSmall?.copyWith(
            color: dialogContext.appColors.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          dialogContext.loc.walletManifestSettingsRestoreConfirmDescription,
          style: dialogContext.font.bodyMedium?.copyWith(
            color: dialogContext.appColors.onSurface,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.loc.walletManifestSettingsCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              dialogContext.loc.walletManifestSettingsRestoreConfirmAction,
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
    await cubit.restoreRemoteManifest();
    if (!context.mounted) return;
    if (cubit.state.manualRestoreWalletStateMayHaveChanged) {
      onWalletsRestored?.call();
    }
  }
}

class _LatestOperationStatus extends StatelessWidget {
  final WalletManifestSettingsState state;

  const _LatestOperationStatus({required this.state});

  @override
  Widget build(BuildContext context) {
    final timestamp = state.latestOperationCompletedAt;
    final operation = state.latestOperation;
    final statusText = timestamp == null || operation == null
        ? context.loc.walletManifestSettingsLatestOperationNone
        : _operationText(context, operation, _formatTimestamp(timestamp));

    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.appColors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            BBText(
              context.loc.walletManifestSettingsLatestOperationTitle,
              style: context.font.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Gap(4),
            BBText(
              statusText,
              style: context.font.bodySmall?.copyWith(
                color: context.appColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _operationText(
    BuildContext context,
    WalletManifestLatestOperation operation,
    String timestamp,
  ) {
    return switch (operation) {
      WalletManifestLatestOperation.checkRemote =>
        context.loc.walletManifestSettingsLatestOperationCheckRemote(timestamp),
      WalletManifestLatestOperation.publishLocal =>
        context.loc.walletManifestSettingsLatestOperationPublishLocal(
          timestamp,
        ),
      WalletManifestLatestOperation.restoreRemote =>
        context.loc.walletManifestSettingsLatestOperationRestoreRemote(
          timestamp,
        ),
      WalletManifestLatestOperation.auditRemote =>
        context.loc.walletManifestSettingsLatestOperationAuditRemote(timestamp),
    };
  }
}

class _RemoteManifestSection extends StatelessWidget {
  final WalletManifestSettingsState state;

  const _RemoteManifestSection({required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .start,
      children: [
        BBText(
          context.loc.walletManifestSettingsRemoteManifestLabel,
          style: context.font.bodyMedium?.copyWith(
            color: context.appColors.textMuted,
          ),
        ),
        const Gap(4),
        BBText(
          context.loc.walletManifestSettingsRemoteManifestSummary(
            state.remoteManifestAccountCount ?? 0,
          ),
          style: context.font.bodySmall?.copyWith(
            color: context.appColors.textMuted,
          ),
        ),
        if (state.remoteManifestCreatedAt != null) ...[
          const Gap(4),
          BBText(
            context.loc.walletManifestSettingsRemoteManifestCreatedAt(
              _formatTimestamp(state.remoteManifestCreatedAt!),
            ),
            style: context.font.bodySmall?.copyWith(
              color: context.appColors.textMuted,
            ),
          ),
        ],
        const Gap(8),
        BBText(
          context.loc.walletManifestSettingsRemoteManifestPrivacy,
          style: context.font.bodySmall?.copyWith(
            color: context.appColors.textMuted,
          ),
        ),
        const Gap(8),
        CopyInput(
          text: state.remoteManifestJson!,
          maxLines: 8,
          overflow: TextOverflow.ellipsis,
          canShowValueModal: true,
          modalTitle: context.loc.walletManifestSettingsRemoteManifestLabel,
        ),
        const Gap(12),
        SettingsEntryItem(
          icon: Icons.save_alt,
          title: context.loc.walletManifestSettingsSaveRemoteManifest,
          onTap: state.saving
              ? null
              : context.read<WalletManifestSettingsCubit>().saveRemoteManifest,
          trailing: state.saving
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: BBText(
            context.loc.walletManifestSettingsSaveRemoteManifestDescription,
            style: context.font.bodySmall?.copyWith(
              color: context.appColors.textMuted,
            ),
          ),
        ),
        const Gap(8),
        if (state.saveStatus == WalletManifestSaveStatus.succeeded)
          _InlineMessage(
            text: context.loc.walletManifestSettingsSaveSucceeded,
            color: context.appColors.textMuted,
          ),
        if (state.saveStatus == WalletManifestSaveStatus.cancelled)
          _InlineMessage(
            text: context.loc.walletManifestSettingsSaveCancelled,
            color: context.appColors.textMuted,
          ),
        if (state.saveStatus == WalletManifestSaveStatus.failed)
          _InlineMessage(
            text: context.loc.walletManifestSettingsSaveFailed,
            color: context.appColors.error,
          ),
      ],
    );
  }
}

String _formatTimestamp(int timestamp) {
  final dateTime = DateTime.fromMillisecondsSinceEpoch(
    timestamp * 1000,
    isUtc: true,
  ).toLocal();
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  final year = dateTime.year.toString().padLeft(4, '0');
  final month = twoDigits(dateTime.month);
  final day = twoDigits(dateTime.day);
  final hour = twoDigits(dateTime.hour);
  final minute = twoDigits(dateTime.minute);
  return '$year-$month-$day $hour:$minute';
}

class _InlineMessage extends StatelessWidget {
  final String text;
  final Color color;

  const _InlineMessage({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: BBText(
        text,
        style: context.font.bodyMedium?.copyWith(color: color),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback? onRetry;

  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: context.appColors.error),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .stretch,
              children: [
                BBText(
                  context.loc.walletManifestSettingsNpubError,
                  style: context.font.titleSmall?.copyWith(
                    color: context.appColors.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Gap(16),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: Text(context.loc.walletManifestSettingsRetry),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
