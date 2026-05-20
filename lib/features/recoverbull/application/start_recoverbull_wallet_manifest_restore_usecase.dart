import 'package:bb_mobile/features/wallet_manifest/public/wallet_manifest_facade.dart';

class StartRecoverBullWalletManifestRestoreUsecase {
  final WalletManifestFacade _walletManifest;

  const StartRecoverBullWalletManifestRestoreUsecase({
    required WalletManifestFacade walletManifest,
  }) : _walletManifest = walletManifest;

  void execute({void Function()? onWalletStateMayHaveChanged}) {
    _walletManifest.startRestoreAfterSeedRecovery(
      onWalletStateMayHaveChanged: onWalletStateMayHaveChanged,
    );
  }
}
