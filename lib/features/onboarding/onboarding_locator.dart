import 'package:bb_mobile/core/settings/data/settings_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/create_default_wallets_usecase.dart';
import 'package:bb_mobile/features/onboarding/complete_physical_backup_verification_usecase.dart';
import 'package:bb_mobile/features/onboarding/presentation/bloc/onboarding_bloc.dart';
import 'package:bb_mobile/features/onboarding/application/start_onboarding_wallet_manifest_restore_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/public/wallet_manifest_facade.dart';
import 'package:get_it/get_it.dart';

class OnboardingLocator {
  static void setup(GetIt locator) {
    // Blocs
    locator.registerFactoryParam<OnboardingBloc, void Function()?, void>(
      (onWalletStateMayHaveChanged, _) => OnboardingBloc(
        createDefaultWalletsUsecase: locator<CreateDefaultWalletsUsecase>(),
        completePhysicalBackupVerificationUsecase:
            locator<CompletePhysicalBackupVerificationUsecase>(),
        startWalletManifestRestore:
            locator<StartOnboardingWalletManifestRestoreUsecase>(),
        onWalletStateMayHaveChanged: onWalletStateMayHaveChanged,
      ),
    );

    // Usecases
    locator.registerFactory<StartOnboardingWalletManifestRestoreUsecase>(
      () => StartOnboardingWalletManifestRestoreUsecase(
        walletManifest: locator<WalletManifestFacade>(),
      ),
    );
    locator.registerFactory<CompletePhysicalBackupVerificationUsecase>(
      () => CompletePhysicalBackupVerificationUsecase(
        walletRepository: locator<WalletRepository>(),
        settingsRepository: locator<SettingsRepository>(),
      ),
    );
  }
}
