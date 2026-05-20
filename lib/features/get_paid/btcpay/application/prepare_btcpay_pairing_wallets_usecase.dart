import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/external_receive_wallets/public/external_receive_wallets.dart';
import 'package:bb_mobile/features/get_paid/btcpay/domain/samrock_pairing_request.dart';

class PrepareBtcpayPairingWalletsResult {
  final List<PrepareBtcpayPairingWalletResult> wallets;

  const PrepareBtcpayPairingWalletsResult({required this.wallets});
}

class PrepareBtcpayPairingWalletResult {
  final BtcpayPairingWalletNetwork network;
  final ExternalReceiveWalletAccountKey accountKey;
  final Wallet wallet;
  final bool created;

  const PrepareBtcpayPairingWalletResult({
    required this.network,
    required this.accountKey,
    required this.wallet,
    required this.created,
  });
}

enum BtcpayPairingWalletNetwork { bitcoin, liquid }

class PrepareBtcpayPairingWalletsUsecase {
  final GetSettingsUsecase _getSettings;
  final ExternalReceiveWalletsFacade _externalReceiveWallets;

  const PrepareBtcpayPairingWalletsUsecase({
    required GetSettingsUsecase getSettings,
    required ExternalReceiveWalletsFacade externalReceiveWallets,
  }) : _getSettings = getSettings,
       _externalReceiveWallets = externalReceiveWallets;

  Future<PrepareBtcpayPairingWalletsResult> execute({
    required SamRockPairingRequest request,
  }) async {
    final settings = await _getSettings.execute();
    final isTestnet = settings.environment.isTestnet;
    final requested = <BtcpayPairingWalletNetwork>[
      if (request.supportsBitcoinChain) BtcpayPairingWalletNetwork.bitcoin,
      if (request.supportsLiquidChain || request.supportsLightning)
        BtcpayPairingWalletNetwork.liquid,
    ];
    if (requested.isEmpty) {
      throw ArgumentError.value(
        request,
        'request',
        'BTCPay pairing requires at least one supported payment method',
      );
    }

    final wallets = <PrepareBtcpayPairingWalletResult>[];
    try {
      for (final network in requested) {
        final key = _accountKey(network: network, isTestnet: isTestnet);
        final existing = await _externalReceiveWallets.get(
          environment: settings.environment,
          purpose: ExternalReceiveWalletPurpose.btcpay,
          accountKey: key,
        );
        if (existing != null) {
          wallets.add(
            PrepareBtcpayPairingWalletResult(
              network: network,
              accountKey: key,
              wallet: existing,
              created: false,
            ),
          );
          continue;
        }

        final created = await _externalReceiveWallets.create(
          environment: settings.environment,
          purpose: ExternalReceiveWalletPurpose.btcpay,
          accountKey: key,
          publishManifest: false,
        );
        wallets.add(
          PrepareBtcpayPairingWalletResult(
            network: network,
            accountKey: key,
            wallet: created,
            created: true,
          ),
        );
      }
    } catch (e, stack) {
      await _rollbackCreatedWalletsBestEffort(
        environment: settings.environment,
        wallets: wallets,
      );
      log.warning(
        'BTCPay wallet preparation failed after partial wallet creation',
        error: e,
        trace: stack,
      );
      rethrow;
    }

    return PrepareBtcpayPairingWalletsResult(wallets: wallets);
  }

  Future<void> rollbackCreatedWallets(
    PrepareBtcpayPairingWalletsResult result,
  ) async {
    final settings = await _getSettings.execute();
    for (final prepared in result.wallets.where((wallet) => wallet.created)) {
      await _externalReceiveWallets.deleteCreated(
        environment: settings.environment,
        purpose: ExternalReceiveWalletPurpose.btcpay,
        accountKey: prepared.accountKey,
        expectedWalletId: prepared.wallet.id,
      );
    }
  }

  Future<void> _rollbackCreatedWalletsBestEffort({
    required Environment environment,
    required List<PrepareBtcpayPairingWalletResult> wallets,
  }) async {
    for (final prepared in wallets.where((wallet) => wallet.created)) {
      try {
        await _externalReceiveWallets.deleteCreated(
          environment: environment,
          purpose: ExternalReceiveWalletPurpose.btcpay,
          accountKey: prepared.accountKey,
          expectedWalletId: prepared.wallet.id,
        );
      } catch (e, stack) {
        log.warning(
          'BTCPay wallet preparation rollback failed',
          error: e,
          trace: stack,
        );
      }
    }
  }

  ExternalReceiveWalletAccountKey _accountKey({
    required BtcpayPairingWalletNetwork network,
    required bool isTestnet,
  }) {
    return switch (network) {
      BtcpayPairingWalletNetwork.bitcoin =>
        ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(
          isTestnet: isTestnet,
        ),
      BtcpayPairingWalletNetwork.liquid =>
        ExternalReceiveWalletPurpose.btcpay.liquidAccountKey(
          isTestnet: isTestnet,
        ),
    };
  }
}
