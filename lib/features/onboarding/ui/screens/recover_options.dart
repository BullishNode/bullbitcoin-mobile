import 'package:bb_mobile/features/key_server/presentation/bloc/key_server_cubit.dart';
import 'package:bb_mobile/features/onboarding/ui/onboarding_router.dart';
import 'package:bb_mobile/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:bb_mobile/locator.dart';
import 'package:bb_mobile/ui/components/cards/backup_option_card.dart';
import 'package:bb_mobile/ui/components/navbar/top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

class OnboardingRecoverOptions extends StatefulWidget {
  const OnboardingRecoverOptions({super.key});

  @override
  State<OnboardingRecoverOptions> createState() =>
      _OnboardingRecoverOptionsState();
}

class _OnboardingRecoverOptionsState extends State<OnboardingRecoverOptions> {
  @override
  Widget build(BuildContext context) {
    final isSuperuser = context.select(
      (SettingsCubit cubit) => cubit.state.isSuperuser ?? false,
    );
    return Scaffold(
      appBar: AppBar(
        forceMaterialTransparency: true,
        automaticallyImplyLeading: false,
        flexibleSpace: TopBar(
          onBack: () => context.pop(),
          title: 'Recover your wallet',
        ),
      ),
      body: BlocProvider(
        create: (context) => locator<KeyServerCubit>(),
        child: BlocBuilder<KeyServerCubit, KeyServerState>(
          builder: (context, state) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Gap(16),

                    if (isSuperuser) ...[
                      BackupOptionCard(
                        icon: Image.asset(
                          'assets/encrypted_vault.png',
                          width: 36,
                          height: 45,
                          fit: BoxFit.cover,
                        ),
                        title: 'Encrypted vault',
                        description:
                            'Recover your backup via cloud using your PIN.',

                        onTap:
                            () => {
                              context.read<KeyServerCubit>().checkConnection(),
                              context.pushNamed(
                                OnboardingRoute
                                    .chooseRecoverProvider
                                    .name, // ChooseVaultProviderScreen
                                extra: true,
                              ),
                            },
                      ),
                      const Gap(16),
                    ],
                    BackupOptionCard(
                      icon: Image.asset(
                        'assets/physical_backup.png',
                        width: 36,
                        height: 45,
                        fit: BoxFit.cover,
                      ),
                      title: 'Physical backup',
                      description: 'Recover your wallet via 12 words.',

                      onTap:
                          () => context.pushNamed(
                            OnboardingRoute.recoverFromPhysical.name,
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
