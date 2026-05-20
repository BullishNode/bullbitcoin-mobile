import 'package:bb_mobile/features/wallet_manifest/domain/bip85_derivation_path.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_network.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_reserved_identities.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_root_fingerprint.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_wallet_type.dart';

class WalletManifestOrigin {
  final String walletId;
  final String rootFingerprint;
  final Bip85DerivationPath bip85DerivationPath;
  final WalletManifestNetwork network;
  final int createdAt;
  final int updatedAt;

  WalletManifestOrigin({
    required String walletId,
    required String rootFingerprint,
    required this.bip85DerivationPath,
    required this.network,
    required this.createdAt,
    required this.updatedAt,
  }) : walletId = normalizeWalletId(walletId),
       rootFingerprint = WalletManifestRootFingerprint.normalize(
         rootFingerprint,
       ) {
    if (createdAt < 0) {
      throw ArgumentError.value(createdAt, 'createdAt', 'must be non-negative');
    }
    if (updatedAt < createdAt) {
      throw ArgumentError.value(
        updatedAt,
        'updatedAt',
        'must be greater than or equal to createdAt',
      );
    }
  }

  String get identity =>
      '$rootFingerprint:${bip85DerivationPath.value}:${network.value}';

  int get bip85Index => bip85DerivationPath.index;

  WalletManifestWalletType get walletType => classifyWalletManifestIdentity(
    bip85Index: bip85DerivationPath.index,
    network: network,
  );

  static String normalizeWalletId(String walletId) {
    final normalized = walletId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(walletId, 'walletId', 'must not be empty');
    }
    return normalized;
  }
}
