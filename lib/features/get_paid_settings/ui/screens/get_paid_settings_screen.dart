import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/core/widgets/settings_entry_item.dart';
import 'package:bb_mobile/features/get_paid_settings/presentation/get_paid_settings_cubit.dart';
import 'package:bb_mobile/features/get_paid_settings/presentation/get_paid_settings_state.dart';
import 'package:bb_mobile/features/get_paid_settings/ui/widgets/automated_backup_off_warning.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/public/remote_keychain_recovery_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class GetPaidSettingsScreen extends StatelessWidget {
  const GetPaidSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.loc.getPaidSettingsScreenTitle)),
      body: SafeArea(
        child: BlocBuilder<GetPaidSettingsCubit, GetPaidSettingsState>(
          builder: (context, state) {
            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        context.loc.getPaidAutomatedBackupToggleLabel,
                      ),
                      value: state.automatedBackupEnabled,
                      onChanged: state.saving
                          ? null
                          : (value) => context
                                .read<GetPaidSettingsCubit>()
                                .toggleAutomatedBackup(value),
                    ),
                    if (!state.automatedBackupEnabled) ...[
                      const SizedBox(height: 8),
                      const AutomatedBackupOffWarning(),
                    ],
                    const SizedBox(height: 8),
                    SettingsEntryItem(
                      icon: Icons.restore,
                      title: context.loc.getPaidRecoverRowTitle,
                      contentPadding: EdgeInsets.zero,
                      onTap: () => context.pushNamed(
                        RemoteKeychainRecoveryRoute.getPaidRecovery.name,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
