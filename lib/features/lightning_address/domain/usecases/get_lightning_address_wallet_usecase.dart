import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';

class GetLightningAddressWalletUsecase {
  final WalletRepository _walletRepository;

  GetLightningAddressWalletUsecase({
    required WalletRepository walletRepository,
  }) : _walletRepository = walletRepository;

  Future<Wallet?> execute({required Environment environment}) async {
    final wallets = await _walletRepository.getWallets(
      environment: environment,
      onlyLiquid: true,
    );
    return wallets
        .where((w) => w.label == lightningAddressWalletLabel)
        .firstOrNull;
  }
}
