import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_publish_outcome.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_backup_state_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/publish_wallet_metadata_backup_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_root_port.dart';
import 'package:meta/meta.dart';

final class PublishCurrentWalletMetadataBackupUsecase {
  final WalletMetadataBackupStateRepository _stateRepository;
  final WalletMetadataBackupRootPort _rootPort;
  final PublishWalletMetadataBackupUsecase _publish;

  const PublishCurrentWalletMetadataBackupUsecase({
    required this._stateRepository,
    required this._rootPort,
    required this._publish,
  });

  @useResult
  Future<Result<WalletMetadataPublishOutcome, WalletMetadataBackupFailure>>
  execute() async {
    final stateResult = await _stateRepository.fetch();
    switch (stateResult) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value) when !value.canAttemptPublication:
        return Ok(
          WalletMetadataPublishOutcome(
            status: WalletMetadataPublishStatus.notReady,
          ),
        );
      case Ok():
        break;
    }

    final rootResult = await _rootPort.deriveLocalRoot();
    switch (rootResult) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        return _publish.execute(
          xprvBase58: value.xprvBase58,
          parentFingerprint: value.parentFingerprint,
        );
    }
  }
}
