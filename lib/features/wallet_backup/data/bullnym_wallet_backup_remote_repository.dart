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
    try {
      final head = await _bullnym.fetchBackup(
        signer: _adaptSigner(signer),
        stream: BullnymBackupStream.walletBackup,
      );
      if (!head.found) {
        return Ok(
          WalletBackupRemoteHead.absent(
            generation: head.generation,
            etag: head.etag,
          ),
        );
      }
      return Ok(
        WalletBackupRemoteHead.present(
          generation: head.generation,
          etag: head.etag!,
          ciphertext: WalletBackupCiphertext(head.ciphertext!.value),
          ciphertextSha256: head.ciphertextSha256!,
          updatedAtSecs: head.updatedAtSecs!,
        ),
      );
    } on BullnymException catch (error, trace) {
      return Err(_mapBullnymFailure(error, trace));
    } on AuthenticatedBackupCipherException catch (error, trace) {
      return Err(_mapCipherFailure(error, trace));
    } on ArgumentError catch (error, trace) {
      log.warning(
        'Bullnym returned an invalid wallet backup head',
        error: error.runtimeType,
        trace: trace,
      );
      return Err(
        WalletBackupInvalidRemoteFailure(error.runtimeType.toString()),
      );
    } on Exception catch (error, trace) {
      log.warning(
        'Unexpected wallet backup fetch failure',
        error: error.runtimeType,
        trace: trace,
      );
      return Err(WalletBackupUnexpectedFailure(error.runtimeType.toString()));
    }
  }

  @override
  @useResult
  Future<Result<WalletBackupRemoteCheckpoint, WalletBackupFailure>> store({
    required WalletBackupSigner signer,
    required WalletBackupRemoteHead current,
    required WalletBackupCiphertext ciphertext,
  }) async {
    try {
      final receipt = await _bullnym.storeBackup(
        signer: _adaptSigner(signer),
        stream: BullnymBackupStream.walletBackup,
        currentHead: _adaptHead(current),
        ciphertext: AuthenticatedBackupCiphertext(ciphertext.value),
      );
      return Ok(
        WalletBackupRemoteCheckpoint(
          generation: receipt.generation,
          etag: receipt.etag,
        ),
      );
    } on BullnymException catch (error, trace) {
      return Err(_mapBullnymFailure(error, trace));
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
    } on Exception catch (error, trace) {
      log.warning(
        'Unexpected wallet backup store failure',
        error: error.runtimeType,
        trace: trace,
      );
      return Err(WalletBackupUnexpectedFailure(error.runtimeType.toString()));
    }
  }

  @override
  @useResult
  Future<Result<WalletBackupRemoteCheckpoint?, WalletBackupFailure>> delete({
    required WalletBackupSigner signer,
    required WalletBackupRemoteHead current,
  }) async {
    try {
      final receipt = await _bullnym.deleteBackup(
        signer: _adaptSigner(signer),
        stream: BullnymBackupStream.walletBackup,
        currentHead: _adaptHead(current),
      );
      if (receipt == null) return const Ok(null);
      return Ok(
        WalletBackupRemoteCheckpoint(
          generation: receipt.generation,
          etag: receipt.etag,
        ),
      );
    } on BullnymException catch (error, trace) {
      return Err(_mapBullnymFailure(error, trace));
    } on AuthenticatedBackupCipherException catch (error, trace) {
      return Err(_mapCipherFailure(error, trace));
    } on ArgumentError catch (error, trace) {
      log.warning(
        'Bullnym returned an invalid wallet backup delete receipt',
        error: error.runtimeType,
        trace: trace,
      );
      return Err(
        WalletBackupInvalidRemoteFailure(error.runtimeType.toString()),
      );
    } on Exception catch (error, trace) {
      log.warning(
        'Unexpected wallet backup delete failure',
        error: error.runtimeType,
        trace: trace,
      );
      return Err(WalletBackupUnexpectedFailure(error.runtimeType.toString()));
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

WalletBackupFailure _mapBullnymFailure(
  BullnymException error,
  StackTrace trace,
) {
  log.warning(
    'Bullnym wallet backup request failed',
    error: error.code,
    trace: trace,
  );
  return switch (error.code) {
    'BackupHeadConflict' => const WalletBackupHeadConflictFailure(),
    'BackupBlobTooLarge' => const WalletBackupTooLargeFailure(),
    'InvalidServerResponse' => WalletBackupInvalidRemoteFailure(error.code),
    'BackupInvalidRequest' ||
    'BackupAuthError' => WalletBackupRemoteRejectedFailure(error.code),
    'SigningFailed' => WalletBackupSigningFailure(error.code),
    'NetworkError' ||
    'Timeout' ||
    'HttpError' ||
    'EmptyResponse' ||
    'RateLimited' ||
    'BackupCapacityExceeded' ||
    'InternalError' => WalletBackupRemoteUnavailableFailure(error.code),
    _ => WalletBackupUnexpectedFailure(error.code),
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
