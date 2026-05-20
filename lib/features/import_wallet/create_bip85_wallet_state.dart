import 'package:bb_mobile/features/wallet_manifest/public/create_manual_bip85_wallets.dart';

enum CreateBip85WalletStatus { idle, submitting, succeeded, failed }

class CreateBip85WalletState {
  final CreateBip85WalletStatus status;
  final CreateManualBip85WalletsResult? result;
  final CreateManualBip85WalletsFailure? failure;

  const CreateBip85WalletState({
    this.status = CreateBip85WalletStatus.idle,
    this.result,
    this.failure,
  });

  bool get isSubmitting => status == CreateBip85WalletStatus.submitting;
  bool get succeeded => status == CreateBip85WalletStatus.succeeded;
  bool get failed => status == CreateBip85WalletStatus.failed;
}
