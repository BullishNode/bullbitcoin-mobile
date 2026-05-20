import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_network.dart';

WalletManifestNetwork walletManifestNetworkFromWalletNetwork(Network network) {
  return switch (network) {
    Network.bitcoinMainnet => WalletManifestNetwork.bitcoin,
    Network.bitcoinTestnet => WalletManifestNetwork.testnet3,
    Network.liquidMainnet => WalletManifestNetwork.liquid,
    Network.liquidTestnet => WalletManifestNetwork.liquidTestnet,
  };
}

Network walletNetworkFromWalletManifestNetwork(WalletManifestNetwork network) {
  return switch (network) {
    WalletManifestNetwork.bitcoin => Network.bitcoinMainnet,
    WalletManifestNetwork.testnet3 => Network.bitcoinTestnet,
    WalletManifestNetwork.liquid => Network.liquidMainnet,
    WalletManifestNetwork.liquidTestnet => Network.liquidTestnet,
  };
}
