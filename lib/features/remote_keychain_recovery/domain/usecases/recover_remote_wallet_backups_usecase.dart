import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_result.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_facade.dart';

typedef _RecoverKeychain = Future<RemoteKeychainRecoveryResult> Function();

final class RecoverRemoteWalletBackupsUsecase {
  final _RecoverKeychain _recoverKeychain;
  final WalletMetadataBackupFacade _metadataBackup;

  const RecoverRemoteWalletBackupsUsecase(
    this._recoverKeychain,
    this._metadataBackup,
  );

  Future<RemoteKeychainRecoveryResult> execute({
    required Set<String> defaultCreatedWalletIds,
  }) async {
    WalletMetadataRecoverySession? session;
    Object? keychainError;
    StackTrace? keychainStack;
    RemoteKeychainRecoveryResult? keychainResult;

    try {
      session = await _metadataBackup.beginRecoverySession();
    } on Object catch (error, stack) {
      log.warning(
        'Could not prepare metadata recovery session',
        error: error,
        trace: stack,
      );
    }
    try {
      try {
        keychainResult = await _recoverKeychain();
      } on Exception catch (error, stack) {
        keychainError = error;
        keychainStack = stack;
      }

      final metadataPayload = keychainResult?.metadataPayload;
      if (metadataPayload != null) {
        await _recoverMetadata(
          payload: metadataPayload,
          createdWalletRefs: {
            ...defaultCreatedWalletIds,
            ...?keychainResult?.createdWalletIds,
          },
        );
      } else if (session != null) {
        await _recoverMetadataSession(
          session: session,
          createdWalletRefs: {
            ...defaultCreatedWalletIds,
            ...?keychainResult?.createdWalletIds,
          },
        );
      }
    } finally {
      session?.close();
    }

    if (keychainError != null) {
      Error.throwWithStackTrace(keychainError, keychainStack!);
    }
    return keychainResult!;
  }

  Future<void> _recoverMetadataSession({
    required WalletMetadataRecoverySession session,
    required Set<String> createdWalletRefs,
  }) async {
    try {
      final result = await session.recover(
        createdWalletRefs: Set.unmodifiable(createdWalletRefs),
      );
      if (result case Err(:final failure)) {
        log.warning(
          'Remote wallet metadata recovery failed',
          error: StateError(failure.runtimeType.toString()),
        );
      }
    } on Exception catch (error, stack) {
      log.warning(
        'Remote wallet metadata recovery threw unexpectedly',
        error: error,
        trace: stack,
      );
    }
  }

  Future<void> _recoverMetadata({
    required String payload,
    required Set<String> createdWalletRefs,
  }) async {
    try {
      final result = await _metadataBackup.recoverSection(
        payload: payload,
        createdWalletRefs: Set.unmodifiable(createdWalletRefs),
      );
      if (result case Err(:final failure)) {
        log.warning(
          'Remote wallet metadata recovery failed',
          error: StateError(failure.runtimeType.toString()),
        );
      }
    } on Exception catch (error, stack) {
      log.warning(
        'Remote wallet metadata recovery threw unexpectedly',
        error: error,
        trace: stack,
      );
    }
  }
}
