import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/recoverbull/domain/complete_encrypted_vault_backup_usecase.dart';
import 'package:bb_mobile/features/recoverbull/domain/encrypted_vault_backup_completion_port.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCompletionPort extends Mock
    implements EncryptedVaultBackupCompletionPort {}

void main() {
  late _MockCompletionPort completion;
  late CompleteEncryptedVaultBackupUsecase usecase;

  setUpAll(() => registerFallbackValue(DateTime.utc(2000)));

  setUp(() {
    completion = _MockCompletionPort();
    usecase = CompleteEncryptedVaultBackupUsecase(completion);
  });

  test('timestamps only the wallet used to create the vault', () async {
    when(
      () => completion.markCompleted(
        walletId: 'bitcoin',
        completedAt: any(named: 'completedAt'),
      ),
    ).thenAnswer((_) async {});
    final before = DateTime.now();

    final result = await usecase.execute(walletId: 'bitcoin');

    final after = DateTime.now();
    expect(result, isA<Ok>());
    final timestamp =
        verify(
              () => completion.markCompleted(
                walletId: 'bitcoin',
                completedAt: captureAny(named: 'completedAt'),
              ),
            ).captured.single
            as DateTime;
    expect(timestamp.isBefore(before), isFalse);
    expect(timestamp.isAfter(after), isFalse);
  });

  test('maps a wallet persistence error to a Recoverbull failure', () async {
    when(
      () => completion.markCompleted(
        walletId: 'missing',
        completedAt: any(named: 'completedAt'),
      ),
    ).thenThrow(Exception('missing'));

    final result = await usecase.execute(walletId: 'missing');

    expect(result, isA<Err>());
  });
}
