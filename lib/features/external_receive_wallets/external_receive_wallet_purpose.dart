import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/external_receive_wallets/reserved_external_receive_wallet_labels.dart';
import 'package:bb_mobile/features/wallet_manifest/public/wallet_manifest.dart';

enum ExternalReceiveWalletPurpose { lightningAddress, paymentPage, btcpay }

class ExternalReceiveWalletAccountKey {
  final ExternalReceiveWalletPurpose purpose;
  final Network network;

  const ExternalReceiveWalletAccountKey._({
    required this.purpose,
    required this.network,
  });

  factory ExternalReceiveWalletAccountKey.liquid({
    required ExternalReceiveWalletPurpose purpose,
    required bool isTestnet,
  }) {
    return ExternalReceiveWalletAccountKey._(
      purpose: purpose,
      network: isTestnet ? Network.liquidTestnet : Network.liquidMainnet,
    );
  }

  factory ExternalReceiveWalletAccountKey.btcpayBitcoin({
    required bool isTestnet,
  }) {
    return ExternalReceiveWalletAccountKey._(
      purpose: ExternalReceiveWalletPurpose.btcpay,
      network: isTestnet ? Network.bitcoinTestnet : Network.bitcoinMainnet,
    );
  }

  factory ExternalReceiveWalletAccountKey.forNetwork({
    required ExternalReceiveWalletPurpose purpose,
    required Network network,
  }) {
    if (network.isLiquid) {
      return ExternalReceiveWalletAccountKey._(
        purpose: purpose,
        network: network,
      );
    }
    if (purpose == ExternalReceiveWalletPurpose.btcpay) {
      return ExternalReceiveWalletAccountKey._(
        purpose: purpose,
        network: network,
      );
    }
    throw UnsupportedError(
      'Only BTCPay supports Bitcoin external receive wallets',
    );
  }

  int get bip85Index => purpose.bip85Index;

  String get settingsNetworkKey => network.isLiquid ? 'liquid' : 'bitcoin';

  String get walletLabel => switch ((purpose, network.isLiquid)) {
    (ExternalReceiveWalletPurpose.lightningAddress, true) =>
      ReservedExternalReceiveWalletLabel.lightningAddressLiquid,
    (ExternalReceiveWalletPurpose.paymentPage, true) =>
      ReservedExternalReceiveWalletLabel.paymentPageLiquid,
    (ExternalReceiveWalletPurpose.btcpay, true) =>
      ReservedExternalReceiveWalletLabel.btcpayLiquid,
    (ExternalReceiveWalletPurpose.btcpay, false) =>
      ReservedExternalReceiveWalletLabel.btcpayBitcoin,
    _ => throw UnsupportedError(
      'Only BTCPay supports Bitcoin external receive wallets',
    ),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExternalReceiveWalletAccountKey &&
          purpose == other.purpose &&
          network == other.network;

  @override
  int get hashCode => Object.hash(purpose, network);
}

class ExternalReceiveWalletBip85Index {
  const ExternalReceiveWalletBip85Index._();

  static const lightningAddress =
      WalletManifestReservedBip85Indexes.lightningAddress;
  static const paymentPage = WalletManifestReservedBip85Indexes.paymentPage;
  static const btcpay = WalletManifestReservedBip85Indexes.btcpay;
}

extension ExternalReceiveWalletPurposeConfig on ExternalReceiveWalletPurpose {
  int get bip85Index => switch (this) {
    ExternalReceiveWalletPurpose.lightningAddress =>
      ExternalReceiveWalletBip85Index.lightningAddress,
    ExternalReceiveWalletPurpose.paymentPage =>
      ExternalReceiveWalletBip85Index.paymentPage,
    ExternalReceiveWalletPurpose.btcpay =>
      ExternalReceiveWalletBip85Index.btcpay,
  };

  String get walletLabel => liquidAccountKey(isTestnet: false).walletLabel;

  ExternalReceiveWalletAccountKey liquidAccountKey({required bool isTestnet}) {
    return ExternalReceiveWalletAccountKey.liquid(
      purpose: this,
      isTestnet: isTestnet,
    );
  }

  ExternalReceiveWalletAccountKey bitcoinAccountKey({required bool isTestnet}) {
    if (this != ExternalReceiveWalletPurpose.btcpay) {
      throw UnsupportedError('Only BTCPay has a Bitcoin account key');
    }
    return ExternalReceiveWalletAccountKey.btcpayBitcoin(isTestnet: isTestnet);
  }
}
