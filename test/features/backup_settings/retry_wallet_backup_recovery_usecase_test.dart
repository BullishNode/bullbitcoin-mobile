import 'package:bb_mobile/features/backup_settings/domain/usecases/retry_wallet_backup_recovery_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/public/remote_keychain_recovery_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

final class _MockRemoteRecovery extends Mock
    implements RemoteKeychainRecoveryFacade {}

void main() {
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

      expect(result.status, RemoteKeychainRecoveryStatus.restored);
      verify(
        () => recovery.recover(defaultCreatedWalletIds: const {}),
      ).called(1);
    },
  );
}
