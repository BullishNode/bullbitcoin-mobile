import 'dart:async';

import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/onboarding/domain/usecases/complete_physical_backup_verification_usecase.dart';
import 'package:bb_mobile/features/onboarding/domain/usecases/create_onboarding_wallets_usecase.dart';
import 'package:bb_mobile/features/onboarding/presentation/bloc/onboarding_bloc.dart';
import 'package:bb_mobile/features/onboarding/recover_remote_keychain_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/public/remote_keychain_recovery_facade.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCreateOnboardingWallets extends Mock
    implements CreateOnboardingWalletsUsecase {}

class _MockRecoveryFacade extends Mock
    implements RemoteKeychainRecoveryFacade {}

class _MockCompletePhysicalBackup extends Mock
    implements CompletePhysicalBackupVerificationUsecase {}

class _MockRecoverRemoteKeychain extends Mock
    implements RecoverRemoteKeychainUsecase {}

class _MockWallet extends Mock implements Wallet {}

void main() {
  late _MockCreateOnboardingWallets createOnboardingWallets;
  late _MockCompletePhysicalBackup completePhysicalBackup;
  late _MockRecoverRemoteKeychain recoverRemoteKeychain;

  ({
    List<String> words,
    String passphrase,
    String label,
    bip39.Language language,
  })
  mnemonic() => (
    words: List<String>.filled(12, 'abandon'),
    passphrase: '',
    label: '',
    language: bip39.Language.english,
  );

  _MockWallet walletStub() {
    final wallet = _MockWallet();
    when(() => wallet.id).thenReturn('default-btc');
    when(() => wallet.masterFingerprint).thenReturn('f00dbabe');
    return wallet;
  }

  OnboardingBloc buildBloc() => OnboardingBloc(
    createOnboardingWalletsUsecase: createOnboardingWallets,
    completePhysicalBackupVerificationUsecase: completePhysicalBackup,
    recoverRemoteKeychainUsecase: recoverRemoteKeychain,
  );

  setUpAll(() {
    registerFallbackValue(<String>{});
  });

  setUp(() {
    createOnboardingWallets = _MockCreateOnboardingWallets();
    completePhysicalBackup = _MockCompletePhysicalBackup();
    recoverRemoteKeychain = _MockRecoverRemoteKeychain();

    when(
      () => createOnboardingWallets.execute(
        mnemonicWords: any(named: 'mnemonicWords'),
      ),
    ).thenAnswer((_) async => Ok([walletStub()]));
    when(
      () => completePhysicalBackup.execute(
        masterFingerprint: any(named: 'masterFingerprint'),
      ),
    ).thenAnswer((_) async => const Ok(null));
    when(
      () => recoverRemoteKeychain.execute(
        defaultCreatedWalletIds: any(named: 'defaultCreatedWalletIds'),
      ),
    ).thenAnswer((_) async {});
  });

  test('does not signal success until manifest recovery completes', () async {
    // Gate recovery so we can observe the bloc while it is in flight.
    final gate = Completer<void>();
    when(
      () => recoverRemoteKeychain.execute(
        defaultCreatedWalletIds: any(named: 'defaultCreatedWalletIds'),
      ),
    ).thenAnswer((_) => gate.future);

    final bloc = buildBloc();
    addTearDown(bloc.close);

    bloc.add(OnboardingRecoverWalletClicked(mnemonic: mnemonic()));
    await pumpEventQueue();

    // Recovery has started but not finished: success must NOT be emitted yet.
    verify(
      () => recoverRemoteKeychain.execute(
        defaultCreatedWalletIds: {'default-btc'},
      ),
    ).called(1);
    expect(bloc.state.onboardingStepStatus, OnboardingStepStatus.loading);

    gate.complete();
    await pumpEventQueue();

    expect(bloc.state.onboardingStepStatus, OnboardingStepStatus.success);
  });

  test('creates the defaults and verifies backup before recovery, then '
      'succeeds', () async {
    final order = <String>[];
    when(
      () => createOnboardingWallets.execute(
        mnemonicWords: any(named: 'mnemonicWords'),
      ),
    ).thenAnswer((_) async {
      order.add('create');
      return Ok([walletStub()]);
    });
    when(
      () => completePhysicalBackup.execute(
        masterFingerprint: any(named: 'masterFingerprint'),
      ),
    ).thenAnswer((_) async {
      order.add('verify');
      return const Ok(null);
    });
    when(
      () => recoverRemoteKeychain.execute(
        defaultCreatedWalletIds: any(named: 'defaultCreatedWalletIds'),
      ),
    ).thenAnswer((_) async {
      order.add('recover');
    });

    final bloc = buildBloc();
    addTearDown(bloc.close);

    bloc.add(OnboardingRecoverWalletClicked(mnemonic: mnemonic()));
    await pumpEventQueue();

    expect(order, ['create', 'verify', 'recover']);
    expect(bloc.state.onboardingStepStatus, OnboardingStepStatus.success);
    // Defaults are created regardless of the recovery outcome, so a silent
    // recovery failure still leaves the restored defaults in place.
    verify(
      () => createOnboardingWallets.execute(
        mnemonicWords: any(named: 'mnemonicWords'),
      ),
    ).called(1);
  });

  test('emits success even when the recovery graph throws an Error', () async {
    // Drive the REAL recovery wrapper over a facade that throws a StateError:
    // the wrapper must swallow it so onboarding never fails on optional
    // recovery (the old fire-and-forget could never take onboarding down).
    final facade = _MockRecoveryFacade();
    when(
      () => facade.recover(
        defaultCreatedWalletIds: any(named: 'defaultCreatedWalletIds'),
      ),
    ).thenThrow(StateError('bug in recovery graph'));

    final bloc = OnboardingBloc(
      createOnboardingWalletsUsecase: createOnboardingWallets,
      completePhysicalBackupVerificationUsecase: completePhysicalBackup,
      recoverRemoteKeychainUsecase: RecoverRemoteKeychainUsecase(facade),
    );
    addTearDown(bloc.close);

    bloc.add(OnboardingRecoverWalletClicked(mnemonic: mnemonic()));
    await pumpEventQueue();

    expect(bloc.state.onboardingStepStatus, OnboardingStepStatus.success);
    expect(bloc.state.failure, isNull);
  });
}
