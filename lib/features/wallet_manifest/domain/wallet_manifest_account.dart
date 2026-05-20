import 'package:bb_mobile/features/wallet_manifest/domain/bip85_derivation_path.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_network.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_reserved_identities.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_root_fingerprint.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_wallet_type.dart';

class WalletManifestAccount {
  final String rootFingerprint;
  final Bip85DerivationPath bip85DerivationPath;
  final WalletManifestNetwork network;
  final WalletManifestWalletType walletType;
  final String? name;
  final String? descriptor;
  final String? changeDescriptor;
  final int? timestamp;

  WalletManifestAccount({
    required String rootFingerprint,
    required this.bip85DerivationPath,
    required this.network,
    this.name,
    this.descriptor,
    this.changeDescriptor,
    this.timestamp,
  }) : rootFingerprint = WalletManifestRootFingerprint.normalize(
         rootFingerprint,
       ),
       walletType = classifyWalletManifestIdentity(
         bip85Index: bip85DerivationPath.index,
         network: network,
       );

  String get identity =>
      '$rootFingerprint:${bip85DerivationPath.value}:${network.value}';

  int get bip85Index => bip85DerivationPath.index;

  WalletManifestAccount withoutDescriptors() {
    return WalletManifestAccount(
      rootFingerprint: rootFingerprint,
      bip85DerivationPath: bip85DerivationPath,
      network: network,
      name: name,
      timestamp: timestamp,
    );
  }

  String fallbackName({bool includeNetworkSuffix = false}) {
    final base = 'BIP85 Wallet $bip85Index';
    if (!includeNetworkSuffix) return base;
    return '$base ${network.displaySuffix}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WalletManifestAccount &&
          rootFingerprint == other.rootFingerprint &&
          bip85DerivationPath == other.bip85DerivationPath &&
          network == other.network &&
          walletType == other.walletType &&
          name == other.name &&
          descriptor == other.descriptor &&
          changeDescriptor == other.changeDescriptor &&
          timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(
    rootFingerprint,
    bip85DerivationPath,
    network,
    walletType,
    name,
    descriptor,
    changeDescriptor,
    timestamp,
  );
}
