import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';

class KeychainManifestReservedDerivationRequest {
  final String reservationId;
  final String parentFingerprint;

  /// The BIP85 path that was actually derived when the child seed was
  /// materialized. Recording refuses the request when this proven path does
  /// not match the registry reservation's exact path.
  final String derivationPath;
  final List<KeychainManifestWalletMaterializationRequest> materializations;

  const KeychainManifestReservedDerivationRequest({
    required this.reservationId,
    required this.parentFingerprint,
    required this.derivationPath,
    required this.materializations,
  });
}

class KeychainManifestWalletMaterializationRequest {
  final String walletId;
  final String childSeedFingerprint;
  final Network network;
  final ScriptType scriptType;

  const KeychainManifestWalletMaterializationRequest({
    required this.walletId,
    required this.childSeedFingerprint,
    required this.network,
    required this.scriptType,
  });
}

class KeychainManifestNostrKeyRequest {
  final String reservationId;
  final String parentFingerprint;
  final String derivationPath;
  final String publicKeyHex;
  final KeychainManifestNostrKeyKind keyKind;
  final String purpose;

  const KeychainManifestNostrKeyRequest({
    required this.reservationId,
    required this.parentFingerprint,
    required this.derivationPath,
    required this.publicKeyHex,
    required this.keyKind,
    required this.purpose,
  });
}
