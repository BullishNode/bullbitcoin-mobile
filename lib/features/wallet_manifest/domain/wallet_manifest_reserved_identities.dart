import 'package:bb_mobile/core/bip85/domain/reserved_bip85_indexes.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_network.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_wallet_type.dart';

WalletManifestWalletType classifyWalletManifestIdentity({
  required int bip85Index,
  required WalletManifestNetwork network,
}) {
  if (bip85Index == ReservedBip85Indexes.lightningAddress && network.isLiquid) {
    return WalletManifestWalletType.lightningAddress;
  }
  if (bip85Index == ReservedBip85Indexes.paymentPage && network.isLiquid) {
    return WalletManifestWalletType.paymentPage;
  }
  if (bip85Index == ReservedBip85Indexes.btcpay) {
    return WalletManifestWalletType.btcpay;
  }
  return WalletManifestWalletType.manual;
}
