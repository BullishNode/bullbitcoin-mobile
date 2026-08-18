import 'package:bb_mobile/features/backup_settings/domain/usecases/get_last_wallet_backup_recovery_outcome_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/retry_wallet_backup_recovery_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/public/remote_keychain_recovery_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

final class _MockRemoteRecovery extends Mock
    implements RemoteKeychainRecoveryFacade {}

void main() {
  test('maps every remote recovery status explicitly', () {
    const expected =
        <RemoteKeychainRecoveryStatus, WalletBackupRecoveryOutcomeStatus>{
          RemoteKeychainRecoveryStatus.noBackup:
              WalletBackupRecoveryOutcomeStatus.noBackup,
          RemoteKeychainRecoveryStatus.nothingToRestore:
              WalletBackupRecoveryOutcomeStatus.nothingToRestore,
          RemoteKeychainRecoveryStatus.unavailable:
              WalletBackupRecoveryOutcomeStatus.unavailable,
          RemoteKeychainRecoveryStatus.invalid:
              WalletBackupRecoveryOutcomeStatus.invalid,
          RemoteKeychainRecoveryStatus.tooLarge:
              WalletBackupRecoveryOutcomeStatus.tooLarge,
          RemoteKeychainRecoveryStatus.newerVersion:
              WalletBackupRecoveryOutcomeStatus.newerVersion,
          RemoteKeychainRecoveryStatus.conflict:
              WalletBackupRecoveryOutcomeStatus.conflict,
          RemoteKeychainRecoveryStatus.localFailure:
              WalletBackupRecoveryOutcomeStatus.localFailure,
          RemoteKeychainRecoveryStatus.restored:
              WalletBackupRecoveryOutcomeStatus.restored,
          RemoteKeychainRecoveryStatus.partiallyRestored:
              WalletBackupRecoveryOutcomeStatus.partiallyRestored,
          RemoteKeychainRecoveryStatus.timedOut:
              WalletBackupRecoveryOutcomeStatus.timedOut,
        };

    for (final entry in expected.entries) {
      expect(mapRemoteRecoveryStatus(entry.key), entry.value);
    }
  });

  test(
    'manual retry does not classify existing defaults as newly created',
    () async {
      final recovery = _MockRemoteRecovery();
      when(
        () => recovery.recover(
          defaultCreatedWalletIds: any(named: 'defaultCreatedWalletIds'),
        ),
      ).thenAnswer(
        (_) async => const RemoteKeychainRecoveryResult(
          status: RemoteKeychainRecoveryStatus.restored,
        ),
      );

      final result = await RetryWalletBackupRecoveryUsecase(recovery).execute();

      expect(result.status, WalletBackupRecoveryOutcomeStatus.restored);
      verify(
        () => recovery.recover(defaultCreatedWalletIds: const {}),
      ).called(1);
    },
  );
}
