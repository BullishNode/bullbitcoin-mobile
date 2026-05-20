import 'package:bb_mobile/core/blockchain/domain/usecases/broadcast_bitcoin_transaction_usecase.dart';
import 'package:bb_mobile/core/blockchain/domain/usecases/broadcast_liquid_transaction_usecase.dart';
import 'package:bb_mobile/core/fees/domain/fees_entity.dart';
import 'package:bb_mobile/core/fees/domain/get_network_fees_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/get_auto_swap_settings_usecase.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/wallet/data/repositories/bitcoin_wallet_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/liquid_wallet_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_address_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/external_receive_wallets/external_receive_wallet_errors.dart';
import 'package:bb_mobile/features/external_receive_wallets/external_receive_wallet_purpose.dart';
import 'package:bb_mobile/features/labels/labels_facade.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/get_external_receive_wallet_usecase.dart';

class SweepExternalReceiveWalletUsecase {
  static const int _dustThresholdSat = 100;

  final GetExternalReceiveWalletUsecase _getWallet;
  final WalletRepository _walletRepository;
  final WalletAddressRepository _walletAddressRepository;
  final LiquidWalletRepository _liquidWalletRepository;
  final BitcoinWalletRepository _bitcoinWalletRepository;
  final BroadcastLiquidTransactionUsecase _broadcastLiquid;
  final BroadcastBitcoinTransactionUsecase _broadcastBitcoin;
  final GetNetworkFeesUsecase _getNetworkFees;
  final GetAutoSwapSettingsUsecase _getAutoSwapSettings;
  final LabelsFacade _labelsFacade;

  SweepExternalReceiveWalletUsecase({
    required GetExternalReceiveWalletUsecase getWallet,
    required WalletRepository walletRepository,
    required WalletAddressRepository walletAddressRepository,
    required LiquidWalletRepository liquidWalletRepository,
    required BitcoinWalletRepository bitcoinWalletRepository,
    required BroadcastLiquidTransactionUsecase broadcastLiquid,
    required BroadcastBitcoinTransactionUsecase broadcastBitcoin,
    required GetNetworkFeesUsecase getNetworkFees,
    required GetAutoSwapSettingsUsecase getAutoSwapSettings,
    required LabelsFacade labelsFacade,
  }) : _getWallet = getWallet,
       _walletRepository = walletRepository,
       _walletAddressRepository = walletAddressRepository,
       _liquidWalletRepository = liquidWalletRepository,
       _bitcoinWalletRepository = bitcoinWalletRepository,
       _broadcastLiquid = broadcastLiquid,
       _broadcastBitcoin = broadcastBitcoin,
       _getNetworkFees = getNetworkFees,
       _getAutoSwapSettings = getAutoSwapSettings,
       _labelsFacade = labelsFacade;

  /// Sweeps all funds from an external receive wallet to the same-network
  /// default wallet. Returns the txid if a sweep was broadcast, or null if no
  /// sweep was needed.
  Future<String?> execute({
    required bool isTestnet,
    required ExternalReceiveWalletPurpose purpose,
    required String expectedWalletId,
    ExternalReceiveWalletAccountKey? accountKey,
  }) async {
    final environment = isTestnet ? Environment.testnet : Environment.mainnet;

    final receiveWallet = await _getWallet.execute(
      environment: environment,
      purpose: purpose,
      accountKey: accountKey,
    );
    if (receiveWallet == null) return null;
    if (receiveWallet.id != expectedWalletId) {
      log.warning(
        'External receive wallet sweep skipped because resolved wallet did not match synced wallet',
      );
      return null;
    }

    // Wallet balance has already been synced by the normal wallet flow.
    if (receiveWallet.balanceSat <= BigInt.from(_dustThresholdSat)) {
      return null;
    }

    final effectiveAccountKey =
        accountKey ??
        ExternalReceiveWalletAccountKey.forNetwork(
          purpose: purpose,
          network: receiveWallet.network,
        );
    final txid = receiveWallet.network.isLiquid
        ? await _sweepLiquid(receiveWallet, environment, isTestnet)
        : await _sweepBitcoin(receiveWallet, environment);

    if (txid == null) return null;
    await _storeSweepLabel(
      txid: txid,
      label: effectiveAccountKey.walletLabel,
      origin: receiveWallet.id,
    );
    return txid;
  }

  Future<String> _sweepLiquid(
    Wallet receiveWallet,
    Environment environment,
    bool isTestnet,
  ) async {
    final defaultWallets = await _walletRepository.getWallets(
      environment: environment,
      onlyDefaults: true,
      onlyLiquid: true,
    );
    final defaultLiquid = defaultWallets.firstOrNull;
    if (defaultLiquid == null) {
      throw ExternalReceiveWalletSweepException(
        'No default Liquid wallet found',
      );
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

    return _broadcastLiquid.execute(signedPset, isTestnet: isTestnet);
  }

  Future<String?> _sweepBitcoin(
    Wallet receiveWallet,
    Environment environment,
  ) async {
    final defaultWallets = await _walletRepository.getWallets(
      environment: environment,
      onlyDefaults: true,
      onlyBitcoin: true,
    );
    final defaultBitcoin = defaultWallets.firstOrNull;
    if (defaultBitcoin == null) {
      throw ExternalReceiveWalletSweepException(
        'No default Bitcoin wallet found',
      );
    }

    final destinationAddress = await _walletAddressRepository
        .generateNewReceiveAddress(walletId: defaultBitcoin.id);

    final fees = await _getNetworkFees.execute(isLiquid: false);
    final psbt = await _bitcoinWalletRepository.buildPsbt(
      walletId: receiveWallet.id,
      address: destinationAddress.address,
      networkFee: fees.economic,
      drain: true,
    );

    final feeSat = await _bitcoinWalletRepository.getTxFeeAmount(psbt: psbt);
    final feePercent = (feeSat / receiveWallet.balanceSat.toDouble()) * 100;
    final autoSwapSettings = await _getAutoSwapSettings.execute();
    if (!autoSwapSettings.withinFeeThreshold(feePercent)) {
      log.warning(
        'External receive Bitcoin autosweep skipped because fee $feePercent% exceeds threshold ${autoSwapSettings.feeThresholdPercent}%',
      );
      return null;
    }

    final signedPsbt = await _bitcoinWalletRepository.signPsbt(
      psbt,
      walletId: receiveWallet.id,
    );
    return _broadcastBitcoin.execute(signedPsbt, isPsbt: true);
  }

  Future<void> _storeSweepLabel({
    required String txid,
    required String label,
    required String origin,
  }) async {
    try {
      await _labelsFacade.store(
        NewLabel.tx(transactionId: txid, label: label, origin: origin),
      );
    } catch (e) {
      log.warning(
        'External receive wallet sweep label transfer failed',
        error: e,
      );
    }
  }
}
