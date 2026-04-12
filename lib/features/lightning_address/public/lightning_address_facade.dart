import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/sweep_lightning_address_wallet_usecase.dart';

/// Public API for the lightning_address feature.
///
/// All cross-feature access MUST go through this facade.
class LightningAddressFacade {
  static const String walletLabel = lightningAddressWalletLabel;

  static bool isLightningAddressWallet(Wallet wallet) =>
      wallet.label == walletLabel;

  final SweepLightningAddressWalletUsecase _sweep;

  LightningAddressFacade({
    required SweepLightningAddressWalletUsecase sweep,
  }) : _sweep = sweep;

  Future<String?> sweep({required bool isTestnet}) =>
      _sweep.execute(isTestnet: isTestnet);
}
