import 'package:bb_mobile/features/remote_keychain_recovery/public/recover_remote_keychain_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/public/remote_keychain_recovery_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockRecoveryFacade extends Mock
    implements RemoteKeychainRecoveryFacade {}

void main() {
  late _MockRecoveryFacade facade;
  late RecoverRemoteKeychainUsecase usecase;

  setUpAll(() {
    registerFallbackValue(<String>{});
  });

  setUp(() {
    facade = _MockRecoveryFacade();
    usecase = RecoverRemoteKeychainUsecase(facade);
  });

  test('never throws when the recovery graph throws an Error', () async {
    // A bug anywhere in the optional recovery graph surfaces as an Error
    // (StateError/TypeError), not an Exception. Onboarding / RecoverBull await
    // this usecase before continuing, so it must swallow Errors too.
    when(
      () => facade.recover(
        defaultCreatedWalletIds: any(named: 'defaultCreatedWalletIds'),
      ),
    ).thenThrow(StateError('bug in recovery graph'));

    await expectLater(
      usecase.execute(defaultCreatedWalletIds: {'btc-default'}),
      completes,
    );
  });

  test('never throws when the recovery graph throws an Exception', () async {
    when(
      () => facade.recover(
        defaultCreatedWalletIds: any(named: 'defaultCreatedWalletIds'),
      ),
    ).thenThrow(Exception('network down'));

    await expectLater(
      usecase.execute(defaultCreatedWalletIds: {'btc-default'}),
      completes,
    );
  });

  test('completes for a normal recovery result', () async {
    when(
      () => facade.recover(
        defaultCreatedWalletIds: any(named: 'defaultCreatedWalletIds'),
      ),
    ).thenAnswer(
      (_) async => const RemoteKeychainRecoveryResult(
        status: RemoteKeychainRecoveryStatus.restored,
      ),
    );

    await usecase.execute(defaultCreatedWalletIds: {'btc-default'});

    verify(
      () => facade.recover(defaultCreatedWalletIds: {'btc-default'}),
    ).called(1);
  });
}
