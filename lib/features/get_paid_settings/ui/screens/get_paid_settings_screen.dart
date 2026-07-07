import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/features/get_paid_settings/presentation/get_paid_settings_cubit.dart';
import 'package:bb_mobile/features/get_paid_settings/presentation/get_paid_settings_state.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/public/remote_keychain_recovery_routes.dart';
import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class GetPaidSettingsScreen extends StatelessWidget {
  const GetPaidSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BullScaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            BullTopBar(
              title: context.loc.getPaidSettingsScreenTitle,
              onBack: context.pop,
            ),
            Expanded(
              child: BlocBuilder<GetPaidSettingsCubit, GetPaidSettingsState>(
                builder: (context, state) {
                  final toggle = state.saving
                      ? null
                      : () => context
                            .read<GetPaidSettingsCubit>()
                            .toggleAutomatedBackup(!state.automatedBackupEnabled);
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BullSettingsEntryItem(
                          icon: Icons.backup,
                          title: context.loc.getPaidAutomatedBackupToggleLabel,
                          onTap: toggle,
                          contentPadding: EdgeInsets.zero,
                          trailing: BullSwitch(
                            value: state.automatedBackupEnabled,
                            onChanged: state.saving
                                ? null
                                : (value) => context
                                      .read<GetPaidSettingsCubit>()
                                      .toggleAutomatedBackup(value),
                          ),
                        ),
                        if (!state.automatedBackupEnabled) ...[
                          const Gap(8),
                          // Locked copy — do not reword (mirrors the shared
                          // AutomatedBackupOffWarning used by the consent dialog).
                          BullInfoCard(
                            description:
                                context.loc.getPaidAutomatedBackupOffWarning,
                            tagColor: context.bull.warning,
                            bgColor: context.bull.warning.withValues(alpha: 0.14),
                          ),
                        ],
                        const Gap(8),
                        BullSettingsEntryItem(
                          icon: Icons.restore,
                          title: context.loc.getPaidRecoverRowTitle,
                          contentPadding: EdgeInsets.zero,
                          onTap: () => context.pushNamed(
                            RemoteKeychainRecoveryRoute.getPaidRecovery.name,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
