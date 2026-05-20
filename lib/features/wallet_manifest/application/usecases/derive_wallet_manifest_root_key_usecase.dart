import 'package:bb_mobile/features/wallet_manifest/application/ports/wallet_manifest_wallet_operations_port.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_root_fingerprint.dart';
import 'package:bb_mobile/features/wallet_manifest/wallet_manifest_errors.dart';

class WalletManifestRootKeyContext {
  final String xprvBase58;
  final String rootFingerprint;

  const WalletManifestRootKeyContext({
    required this.xprvBase58,
    required this.rootFingerprint,
  });
}

class DeriveWalletManifestRootKeyUsecase {
  final WalletManifestWalletOperationsPort _walletOperations;

  const DeriveWalletManifestRootKeyUsecase({
    required WalletManifestWalletOperationsPort walletOperations,
  }) : _walletOperations = walletOperations;

  Future<WalletManifestRootKeyContext> execute() async {
    try {
      final wallets = await _walletOperations.getDefaultBitcoinWallets();
      final defaultWallet = wallets.firstOrNull;
      if (defaultWallet == null) {
        throw WalletManifestKeyDerivationException(
          'No default Bitcoin wallet found',
        );
      }

      final xprv = await _walletOperations.getSeedXprv(
        masterFingerprint: defaultWallet.masterFingerprint,
        network: defaultWallet.network,
      );

      return WalletManifestRootKeyContext(
        xprvBase58: xprv,
        rootFingerprint: WalletManifestRootFingerprint.normalize(
          defaultWallet.masterFingerprint,
        ),
      );
    } on WalletManifestKeyDerivationException {
      rethrow;
    } catch (e) {
      throw WalletManifestKeyDerivationException(e);
    }
  }
}
