import 'package:bb_mobile/core/backup/authenticated_backup_cipher.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_encryption.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_remote.dart';
import 'package:bb_mobile/features/wallet_backup/domain/repositories/wallet_backup_remote_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_failure.dart';
import 'package:meta/meta.dart';

final class BullnymWalletBackupRemoteRepository
    implements WalletBackupRemoteRepository {
  final BullnymFacade _bullnym;

  const BullnymWalletBackupRemoteRepository(this._bullnym);

  @override
  @useResult
  Future<Result<WalletBackupRemoteHead, WalletBackupFailure>> fetch(
    WalletBackupSigner signer,
  ) async {
    final result = await _bullnym.fetchBackup(
      signer: _adaptSigner(signer),
      stream: BullnymBackupStream.walletBackup,
    );
    return switch (result) {
      Err(:final failure) => Err(_mapBullnymFailure(failure)),
      Ok(:final value) => _mapHead(value),
    };
  }

  @override
  @useResult
  Future<Result<WalletBackupRemoteCheckpoint, WalletBackupFailure>> store({
    required WalletBackupSigner signer,
    required WalletBackupRemoteHead current,
    required WalletBackupCiphertext ciphertext,
  }) async {
    try {
      final result = await _bullnym.storeBackup(
        signer: _adaptSigner(signer),
        stream: BullnymBackupStream.walletBackup,
        currentHead: _adaptHead(current),
        ciphertext: AuthenticatedBackupCiphertext(ciphertext.value),
      );
      return switch (result) {
        Err(:final failure) => Err(_mapBullnymFailure(failure)),
        Ok(:final value) => Ok(
          WalletBackupRemoteCheckpoint(
            generation: value.generation,
            etag: value.etag,
          ),
        ),
      };
    } on AuthenticatedBackupCipherException catch (error, trace) {
      return Err(_mapCipherFailure(error, trace));
    } on ArgumentError catch (error, trace) {
      log.warning(
        'Bullnym returned an invalid wallet backup store receipt',
        error: error.runtimeType,
        trace: trace,
      );
      return Err(
        WalletBackupInvalidRemoteFailure(error.runtimeType.toString()),
      );
    }
  }

  @override
  @useResult
  Future<Result<WalletBackupRemoteCheckpoint?, WalletBackupFailure>> delete({
    required WalletBackupSigner signer,
    required WalletBackupRemoteHead current,
  }) async {
    final result = await _bullnym.deleteBackup(
      signer: _adaptSigner(signer),
      stream: BullnymBackupStream.walletBackup,
      currentHead: _adaptHead(current),
    );
    return switch (result) {
      Err(:final failure) => Err(_mapBullnymFailure(failure)),
      Ok(:final value) =>
        value == null
            ? const Ok(null)
            : Ok(
                WalletBackupRemoteCheckpoint(
                  generation: value.generation,
                  etag: value.etag,
                ),
              ),
    };
  }

  Result<WalletBackupRemoteHead, WalletBackupFailure> _mapHead(
    BullnymBackupHead head,
  ) {
    if (!head.found) {
      return Ok(
        WalletBackupRemoteHead.absent(
          generation: head.generation,
          etag: head.etag,
        ),
      );
    }
    try {
      return Ok(
        WalletBackupRemoteHead.present(
          generation: head.generation,
          etag: head.etag!,
          ciphertext: WalletBackupCiphertext(head.ciphertext!.value),
          ciphertextSha256: head.ciphertextSha256!,
          updatedAtSecs: head.updatedAtSecs!,
        ),
      );
    } on ArgumentError catch (error, trace) {
      log.warning(
        'Bullnym returned an invalid wallet backup head',
        error: error.runtimeType,
        trace: trace,
      );
      return Err(
        WalletBackupInvalidRemoteFailure(error.runtimeType.toString()),
      );
    }
  }

  BullnymAuthSigner _adaptSigner(WalletBackupSigner signer) {
    return BullnymAuthSigner(
      npubHex: signer.publicKeyHex,
      signHashHex: signer.signHashHex,
    );
  }

  BullnymBackupHead _adaptHead(WalletBackupRemoteHead head) {
    final ciphertext = head.ciphertext;
    if (ciphertext == null) {
      return BullnymBackupHead.absent(
        generation: head.generation,
        etag: head.etag,
      );
    }
    return BullnymBackupHead.present(
      generation: head.generation,
      etag: head.etag!,
      ciphertext: AuthenticatedBackupCiphertext(ciphertext.value),
      ciphertextSha256: head.ciphertextSha256!,
      updatedAtSecs: head.updatedAtSecs!,
    );
  }
}

WalletBackupFailure _mapBullnymFailure(BullnymFailure failure) {
  log.warning('Bullnym wallet backup request failed', error: failure.code);
  return switch (failure.code) {
    'BackupHeadConflict' => const WalletBackupHeadConflictFailure(),
    'BackupBlobTooLarge' => const WalletBackupTooLargeFailure(),
    'InvalidServerResponse' => WalletBackupInvalidRemoteFailure(failure.code),
    'BackupInvalidRequest' ||
    'BackupAuthError' => WalletBackupRemoteRejectedFailure(failure.code),
    'SigningFailed' => WalletBackupSigningFailure(failure.code),
    'NetworkError' ||
    'Timeout' ||
    'HttpError' ||
    'EmptyResponse' ||
    'RateLimited' ||
    'BackupCapacityExceeded' ||
    'InternalError' => WalletBackupRemoteUnavailableFailure(failure.code),
    _ => WalletBackupUnexpectedFailure(failure.code),
  };
}

WalletBackupFailure _mapCipherFailure(
  AuthenticatedBackupCipherException error,
  StackTrace trace,
) {
  log.warning(
    'Wallet backup ciphertext boundary failed',
    error: error.runtimeType,
    trace: trace,
  );
  return error.message.contains('too large')
      ? const WalletBackupTooLargeFailure()
      : WalletBackupInvalidRemoteFailure(error.runtimeType.toString());
}
