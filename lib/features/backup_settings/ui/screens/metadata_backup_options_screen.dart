import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/core/widgets/buttons/button.dart';
import 'package:bb_mobile/core/widgets/navbar/top_bar.dart';
import 'package:bb_mobile/core/widgets/snackbar_utils.dart';
import 'package:bb_mobile/features/backup_settings/presentation/backup_settings_failure_l10n.dart';
import 'package:bb_mobile/features/backup_settings/presentation/cubit/wallet_backup_settings_cubit.dart';
import 'package:bb_mobile/features/backup_settings/presentation/cubit/wallet_backup_settings_state.dart';
import 'package:bb_mobile/features/wallet_backup/public/wallet_backup_facade.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// Everything the Get Paid metadata backup can be told to do, on its own
/// surface: the automatic-backup toggle, an immediate write, deletion of the
/// remote copy, the last result, and the recovery retry.
///
/// Laid out like the Backup Settings screen it is opened from — the state stated
/// first as a label/value line with the one fact that matters under it, then any
/// notice that needs an answer, then the actions as full-width buttons. The
/// Backup Settings screen keeps only the one-line summary; every action lives
/// here. Pushed as its own route, so it resolves its own cubit rather than
/// reading the one the parent screen provides.
class MetadataBackupOptionsScreen extends StatelessWidget {
  const MetadataBackupOptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => locator<WalletBackupSettingsCubit>()..load(),
      child: const _Screen(),
    );
  }
}

class _Screen extends StatelessWidget {
  const _Screen();

  @override
  Widget build(BuildContext context) {
    return BlocListener<WalletBackupSettingsCubit, WalletBackupSettingsState>(
      listenWhen: (previous, current) =>
          previous.failureRevision != current.failureRevision,
      listener: (context, state) {
        final failure = state.failure;
        if (failure == null) return;
        SnackBarUtils.showSnackBar(context, failure.toTranslated(context));
      },
      child: Scaffold(
        appBar: AppBar(
          forceMaterialTransparency: true,
          automaticallyImplyLeading: false,
          flexibleSpace: TopBar(
            title: context.loc.backupSettingsMetadataBackup,
            onBack: () => context.pop(),
          ),
        ),
        body: const SafeArea(child: _Body()),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WalletBackupSettingsCubit, WalletBackupSettingsState>(
      builder: (context, state) {
        final backup = state.backup;
        final busy = state.busy;
        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
                Text(
                  context.loc.walletBackupSettingsDescription,
                  style: context.font.bodyMedium?.copyWith(
                    color: context.appColors.textMuted,
                  ),
                ),
                const Gap(24),
                // Nothing is claimed until the first read resolves: an unread
                // backup is neither on nor off.
                if (state.loading && backup == null)
                  const LinearProgressIndicator()
                else ...[
                  _StatusLine(state: state, backup: backup),
                  if (backup?.recoveryBlocked == true) ...[
                    const Gap(24),
                    _RecoveryNotice(
                      recovering:
                          state.operation ==
                          WalletBackupSettingsOperation.recovering,
                      onRetry: state.canRetryRecovery
                          ? context
                                .read<WalletBackupSettingsCubit>()
                                .retryRecovery
                          : null,
                    ),
                  ],
                  const Gap(24),
                  _AutomaticBackupSwitch(backup: backup, busy: busy),
                  const Gap(24),
                  BBButton.big(
                    label: context.loc.walletBackupSettingsBackupNow,
                    iconData: Icons.backup,
                    iconFirst: true,
                    onPressed: () =>
                        context.read<WalletBackupSettingsCubit>().backupNow(),
                    disabled: !_canBackUpNow(backup: backup, busy: busy),
                    bgColor: context.appColors.primary,
                    textColor: context.appColors.onPrimary,
                  ),
                  const Gap(12),
                  BBButton.big(
                    label: context.loc.walletBackupSettingsDelete,
                    iconData: Icons.delete_outline,
                    iconFirst: true,
                    onPressed: () => _confirmDelete(context),
                    disabled: !_canDelete(backup: backup, busy: busy),
                    outlined: true,
                    bgColor: context.appColors.surface,
                    textColor: context.appColors.error,
                    borderColor: context.appColors.error,
                  ),
                  if (busy) ...[const Gap(16), const LinearProgressIndicator()],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// An immediate write only makes sense while automatic backup is on and the
  /// backup is neither blocked on recovery nor written by a newer app version.
  bool _canBackUpNow({
    required WalletBackupState? backup,
    required bool busy,
  }) =>
      backup?.enabled == true &&
      !busy &&
      backup?.recoveryBlocked != true &&
      backup?.unsupportedVersion == null;

  /// The remote copy is only removable once automatic backup is off, so a
  /// deletion cannot race the next scheduled write.
  bool _canDelete({required WalletBackupState? backup, required bool busy}) =>
      backup != null && !backup.enabled && !busy;

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.loc.walletBackupSettingsDeleteTitle),
        content: Text(context.loc.walletBackupSettingsDeleteDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.loc.walletBackupSettingsCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.loc.walletBackupSettingsDeleteConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<WalletBackupSettingsCubit>().deleteRemoteBackup();
  }
}

/// On or off, and the one fact that changes what to do next — the same
/// label / coloured value / muted sub-line shape the Backup Settings status
/// rows use.
class _StatusLine extends StatelessWidget {
  final WalletBackupSettingsState state;
  final WalletBackupState? backup;

  const _StatusLine({required this.state, required this.backup});

  @override
  Widget build(BuildContext context) {
    final isOn = backup?.enabled ?? false;
    return Column(
      crossAxisAlignment: .start,
      children: [
        Row(
          children: [
            Text(
              context.loc.walletBackupSettingsTitle,
              style: context.font.bodyMedium,
            ),
            const Spacer(),
            Text(
              isOn
                  ? context.loc.backupSettingsMetadataTurnedOn
                  : context.loc.backupSettingsMetadataTurnedOff,
              style: context.font.bodyMedium?.copyWith(
                color: isOn
                    ? context.appColors.success
                    : context.appColors.error,
              ),
            ),
          ],
        ),
        const Gap(4),
        Text(
          _statusText(context, backup),
          style: context.font.bodySmall?.copyWith(
            color: context.appColors.textMuted,
          ),
        ),
      ],
    );
  }

  String _statusText(BuildContext context, WalletBackupState? backup) {
    if (backup == null) return context.loc.walletBackupSettingsFailed;
    if (backup.unsupportedVersion != null) {
      return context.loc.walletBackupSettingsUpdateRequired;
    }
    if (backup.recoveryBlocked) {
      return context.loc.walletBackupSettingsRecoveryBlocked;
    }
    if (!backup.enabled) return context.loc.walletBackupSettingsOff;
    if (backup.dirty) return context.loc.walletBackupSettingsPending;
    final succeededAt = backup.lastSucceededAt;
    if (succeededAt == null) {
      return context.loc.walletBackupSettingsNeverBackedUp;
    }
    final date = DateTime.fromMillisecondsSinceEpoch(
      succeededAt * 1000,
      isUtc: true,
    ).toLocal();
    return context.loc.walletBackupSettingsLastBackup(
      DateFormat('MMM d, y HH:mm').format(date),
    );
  }
}

class _AutomaticBackupSwitch extends StatelessWidget {
  final WalletBackupState? backup;
  final bool busy;

  const _AutomaticBackupSwitch({required this.backup, required this.busy});

  @override
  Widget build(BuildContext context) {
    final current = backup;
    // A backup written by a newer app version must not be turned back on from
    // here, but it can always be turned off.
    final locked =
        current == null ||
        busy ||
        (current.unsupportedVersion != null && !current.enabled);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(context.loc.walletBackupSettingsEnabled),
      value: current?.enabled ?? false,
      onChanged: locked
          ? null
          : context.read<WalletBackupSettingsCubit>().setEnabled,
    );
  }
}

/// A recovery that stopped half-way needs an answer before anything else on this
/// screen is worth doing, so it is stated as its own bordered notice with the
/// single action that resolves it.
class _RecoveryNotice extends StatelessWidget {
  final bool recovering;
  final VoidCallback? onRetry;

  const _RecoveryNotice({required this.recovering, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final accent = context.appColors.error;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appColors.surfaceContainer,
        border: Border.all(color: accent, width: 2),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        crossAxisAlignment: .start,
        children: [
          Text(
            context.loc.metadataBackupStateRecoveryIncomplete,
            style: context.font.titleMedium?.copyWith(
              fontWeight: .bold,
              color: accent,
            ),
          ),
          const Gap(8),
          Text(
            context.loc.metadataBackupStateRecoveryIncompleteBody,
            style: context.font.bodyMedium,
          ),
          const Gap(16),
          BBButton.big(
            label: context.loc.metadataBackupRetryRecovery,
            iconData: Icons.restore,
            iconFirst: true,
            onPressed: onRetry ?? () {},
            disabled: onRetry == null || recovering,
            bgColor: accent,
            textColor: context.appColors.surface,
          ),
        ],
      ),
    );
  }
}
