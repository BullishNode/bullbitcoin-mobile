import 'package:bb_mobile/core/blockchain/domain/usecases/broadcast_liquid_transaction_usecase.dart';
import 'package:bb_mobile/core/fees/domain/fees_entity.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/liquid_wallet_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_address_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_errors.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/get_lightning_address_wallet_usecase.dart';

class SweepLightningAddressWalletUsecase {
  static const int _dustThresholdSat = 546;

  final GetLightningAddressWalletUsecase _getWallet;
  final WalletRepository _walletRepository;
  final WalletAddressRepository _walletAddressRepository;
  final LiquidWalletRepository _liquidWalletRepository;
  final BroadcastLiquidTransactionUsecase _broadcast;

  SweepLightningAddressWalletUsecase({
    required GetLightningAddressWalletUsecase getWallet,
    required WalletRepository walletRepository,
    required WalletAddressRepository walletAddressRepository,
    required LiquidWalletRepository liquidWalletRepository,
    required BroadcastLiquidTransactionUsecase broadcast,
  }) : _getWallet = getWallet,
       _walletRepository = walletRepository,
       _walletAddressRepository = walletAddressRepository,
       _liquidWalletRepository = liquidWalletRepository,
       _broadcast = broadcast;

  /// Sweeps all funds from the lightning address wallet to the default
  /// Liquid wallet. Returns the txid if a sweep was broadcast, null if
  /// no sweep was needed (no wallet or dust-level balance).
  Future<String?> execute({required bool isTestnet}) async {
    final environment =
        isTestnet ? Environment.testnet : Environment.mainnet;

    // 1. Find the lightning address wallet
    final laWallet = await _getWallet.execute(environment: environment);
    if (laWallet == null) return null;

    // 2. Check balance (wallet is already synced by the normal sync flow)
    if (laWallet.balanceSat <= BigInt.from(_dustThresholdSat)) return null;

    // 3. Get default Liquid wallet address as sweep destination
    final defaultWallets = await _walletRepository.getWallets(
      environment: environment,
      onlyDefaults: true,
      onlyLiquid: true,
    );
    final defaultLiquid = defaultWallets.firstOrNull;
    if (defaultLiquid == null) {
      throw LightningAddressSweepException(
        'No default Liquid wallet found',
      );
    }

    final destinationAddress =
        await _walletAddressRepository.getLastRevealedReceiveAddress(
      walletId: defaultLiquid.id,
    );

    // 4. Build drain PSET, sign, broadcast
    final pset = await _liquidWalletRepository.buildPset(
      walletId: laWallet.id,
      address: destinationAddress.address,
      networkFee: const NetworkFee.relative(0.1),
      drain: true,
    );

    final signedPset = await _liquidWalletRepository.signPset(
      pset: pset,
      walletId: laWallet.id,
    );

    return await _broadcast.execute(signedPset, isTestnet: isTestnet);
  }
}
