import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/keychain_recovery/domain/keychain_recovery_result.dart';

class KeychainRecoveryWalletMaterializationBatch {
  final String parentFingerprint;
  final String reservationId;
  final int bip85Index;
  final String deterministicAlias;
  final List<KeychainRecoveryWalletIntent> intents;

  const KeychainRecoveryWalletMaterializationBatch({
    required this.parentFingerprint,
    required this.reservationId,
    required this.bip85Index,
    required this.deterministicAlias,
    required this.intents,
  });
}

class KeychainRecoveryMaterializedWallet {
  final KeychainRecoveryWalletIntent intent;
  final Wallet wallet;
  final String childSeedFingerprint;
  final bool created;

  const KeychainRecoveryMaterializedWallet({
    required this.intent,
    required this.wallet,
    required this.childSeedFingerprint,
    required this.created,
  });
}

class KeychainRecoveryWalletMaterializationResult {
  final List<KeychainRecoveryMaterializedWallet> materializedWallets;
  final List<KeychainRecoveryWalletRestoreOutcome> failedOutcomes;
  final Future<void> Function()? rollbackCreatedWallets;

  const KeychainRecoveryWalletMaterializationResult({
    required this.materializedWallets,
    required this.failedOutcomes,
    this.rollbackCreatedWallets,
  });
}

abstract class KeychainRecoveryWalletMaterializerPort {
  Future<KeychainRecoveryWalletMaterializationResult> materialize(
    KeychainRecoveryWalletMaterializationBatch batch,
  );
}
