import 'package:bb_mobile/core/blockchain/domain/usecases/broadcast_liquid_transaction_usecase.dart';
import 'package:bb_mobile/core/fees/domain/fees_entity.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/liquid_wallet_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_address_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/labels/labels_facade.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_errors.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/get_bullnym_receive_wallet_usecase.dart';

class SweepBullnymReceiveWalletUsecase {
  static const int _dustThresholdSat = 100;

  final GetBullnymReceiveWalletUsecase _getWallet;
  final WalletRepository _walletRepository;
  final WalletAddressRepository _walletAddressRepository;
  final LiquidWalletRepository _liquidWalletRepository;
  final BroadcastLiquidTransactionUsecase _broadcast;
  final LabelsFacade _labelsFacade;

  SweepBullnymReceiveWalletUsecase({
    required GetBullnymReceiveWalletUsecase getWallet,
    required WalletRepository walletRepository,
    required WalletAddressRepository walletAddressRepository,
    required LiquidWalletRepository liquidWalletRepository,
    required BroadcastLiquidTransactionUsecase broadcast,
    required LabelsFacade labelsFacade,
  }) : _getWallet = getWallet,
       _walletRepository = walletRepository,
       _walletAddressRepository = walletAddressRepository,
       _liquidWalletRepository = liquidWalletRepository,
       _broadcast = broadcast,
       _labelsFacade = labelsFacade;

  /// Sweeps all funds from the Bullnym receive wallet to the default Liquid
  /// wallet. Returns the txid if a sweep was broadcast, or null if no sweep was
  /// needed.
  Future<String?> execute({required bool isTestnet}) async {
    final environment = isTestnet ? Environment.testnet : Environment.mainnet;

    final receiveWallet = await _getWallet.execute(environment: environment);
    if (receiveWallet == null) return null;

    // Wallet balance has already been synced by the normal wallet flow.
    if (receiveWallet.balanceSat <= BigInt.from(_dustThresholdSat)) {
      return null;
    }

    final defaultWallets = await _walletRepository.getWallets(
      environment: environment,
      onlyDefaults: true,
      onlyLiquid: true,
    );
    final defaultLiquid = defaultWallets.firstOrNull;
    if (defaultLiquid == null) {
      throw BullnymReceiveWalletSweepException('No default Liquid wallet found');
    }

    final destinationAddress = await _walletAddressRepository
        .generateNewReceiveAddress(walletId: defaultLiquid.id);

    final pset = await _liquidWalletRepository.buildPset(
      walletId: receiveWallet.id,
      address: destinationAddress.address,
      networkFee: const NetworkFee.relative(0.1),
      drain: true,
    );

    final signedPset = await _liquidWalletRepository.signPset(
      pset: pset,
      walletId: receiveWallet.id,
    );

    final txid = await _broadcast.execute(signedPset, isTestnet: isTestnet);

    await _labelsFacade.store(
      NewLabel.tx(
        transactionId: txid,
        label: bullnymReceiveWalletLabel,
        origin: receiveWallet.id,
      ),
    );

    return txid;
  }
}
