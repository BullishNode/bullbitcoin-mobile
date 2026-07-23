import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/features/backup_settings/presentation/cubit/wallet_backup_settings_cubit.dart';
import 'package:bb_mobile/features/backup_settings/presentation/cubit/wallet_backup_settings_state.dart';
import 'package:bb_mobile/features/wallet_backup/public/wallet_backup_facade.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

class WalletBackupControls extends StatelessWidget {
  const WalletBackupControls({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WalletBackupSettingsCubit, WalletBackupSettingsState>(
      builder: (context, state) {
        final backup = state.backup;
        final busy = state.busy;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
                Text(
                  context.loc.walletBackupSettingsTitle,
                  style: context.font.titleMedium,
                ),
                const Gap(8),
                Text(
                  context.loc.walletBackupSettingsDescription,
                  style: context.font.bodySmall?.copyWith(
                    color: context.appColors.textMuted,
                  ),
                ),
                const Gap(12),
                if (state.loading && backup == null)
                  const LinearProgressIndicator()
                else ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.loc.walletBackupSettingsEnabled),
                    value: backup?.enabled ?? false,
                    onChanged:
                        backup == null ||
                            busy ||
                            (backup.unsupportedVersion != null &&
                                !backup.enabled)
                        ? null
                        : context.read<WalletBackupSettingsCubit>().setEnabled,
                  ),
                  Text(
                    _statusText(context, backup),
                    style: context.font.bodySmall?.copyWith(
                      color: context.appColors.textMuted,
                    ),
                  ),
                  if (state.lastRecoveryOutcome?.isIncomplete ?? false) ...[
                    const Gap(12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.warning_amber_outlined,
                        color: context.appColors.error,
                      ),
                      title: Text(
                        context.loc.metadataBackupStateRecoveryIncomplete,
                      ),
                      subtitle: Text(
                        context.loc.metadataBackupStateRecoveryIncompleteBody,
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: state.canRetryRecovery
                          ? context
                                .read<WalletBackupSettingsCubit>()
                                .retryRecovery
                          : null,
                      icon:
                          state.operation ==
                              WalletBackupSettingsOperation.recovering
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.restore),
                      label: Text(context.loc.metadataBackupRetryRecovery),
                    ),
                  ],
                  const Gap(12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed:
                              backup?.enabled == true &&
                                  !busy &&
                                  backup?.recoveryBlocked != true &&
                                  backup?.unsupportedVersion == null
                              ? context
                                    .read<WalletBackupSettingsCubit>()
                                    .backupNow
                              : null,
                          child: Text(
                            context.loc.walletBackupSettingsBackupNow,
                          ),
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: backup != null && !backup.enabled && !busy
                              ? () => _confirmDelete(context)
                              : null,
                          child: Text(context.loc.walletBackupSettingsDelete),
                        ),
                      ),
                    ],
                  ),
                  if (busy) ...[const Gap(12), const LinearProgressIndicator()],
                ],
              ],
            ),
          ),
        );
      },
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
