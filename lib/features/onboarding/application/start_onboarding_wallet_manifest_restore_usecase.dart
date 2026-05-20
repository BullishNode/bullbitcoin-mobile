import 'package:bb_mobile/features/wallet_manifest/public/wallet_manifest_facade.dart';

class StartOnboardingWalletManifestRestoreUsecase {
  final WalletManifestFacade _walletManifest;

  const StartOnboardingWalletManifestRestoreUsecase({
    required WalletManifestFacade walletManifest,
  }) : _walletManifest = walletManifest;

  void execute({void Function()? onWalletStateMayHaveChanged}) {
    _walletManifest.startRestoreAfterSeedRecovery(
      onWalletStateMayHaveChanged: onWalletStateMayHaveChanged,
    );
  }
}
