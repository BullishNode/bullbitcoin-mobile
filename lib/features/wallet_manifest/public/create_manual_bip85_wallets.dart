import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_network.dart';

enum ManualBip85WalletNetworkSelection { bitcoin, liquid, both }

enum CreateManualBip85WalletsFailure {
  labelRequired,
  reservedLabel,
  invalidIndex,
  indexUnavailable,
  walletCreation,
  generic,
}

class CreateManualBip85WalletsException implements Exception {
  final CreateManualBip85WalletsFailure failure;

  const CreateManualBip85WalletsException(this.failure);

  @override
  String toString() => 'CreateManualBip85WalletsException($failure)';
}

class CreateManualBip85WalletsCommand {
  final ManualBip85WalletNetworkSelection networkSelection;
  final int? index;
  final String? bitcoinLabel;
  final String? liquidLabel;

  const CreateManualBip85WalletsCommand({
    required this.networkSelection,
    this.index,
    this.bitcoinLabel,
    this.liquidLabel,
  });
}

class CreateManualBip85WalletsResult {
  final int index;
  final List<CreateManualBip85WalletResult> wallets;
  final bool manifestPublishFailed;
  final bool partialFailure;

  const CreateManualBip85WalletsResult({
    required this.index,
    required this.wallets,
    required this.manifestPublishFailed,
    this.partialFailure = false,
  });
}

class CreateManualBip85WalletResult {
  final WalletManifestNetwork network;
  final String walletId;
  final String label;

  const CreateManualBip85WalletResult({
    required this.network,
    required this.walletId,
    required this.label,
  });
}
