import 'dart:async';

import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/create_default_wallets_usecase.dart';
import 'package:bb_mobile/features/onboarding/complete_physical_backup_verification_usecase.dart';
import 'package:bb_mobile/features/onboarding/presentation/bloc/onboarding_bloc.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/public/recover_remote_keychain_usecase.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCreateDefaultWallets extends Mock
    implements CreateDefaultWalletsUsecase {}

class _MockCompletePhysicalBackup extends Mock
    implements CompletePhysicalBackupVerificationUsecase {}

class _MockRecoverRemoteKeychain extends Mock
    implements RecoverRemoteKeychainUsecase {}

class _MockWallet extends Mock implements Wallet {}

void main() {
  late _MockCreateDefaultWallets createDefaultWallets;
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

  OnboardingBloc buildBloc() => OnboardingBloc(
    createDefaultWalletsUsecase: createDefaultWallets,
    completePhysicalBackupVerificationUsecase: completePhysicalBackup,
    recoverRemoteKeychainUsecase: recoverRemoteKeychain,
  );

  setUp(() {
    createDefaultWallets = _MockCreateDefaultWallets();
    completePhysicalBackup = _MockCompletePhysicalBackup();
    recoverRemoteKeychain = _MockRecoverRemoteKeychain();

    final wallet = _MockWallet();
    when(() => wallet.id).thenReturn('default-btc');
    when(
      () => createDefaultWallets.execute(
        mnemonicWords: any(named: 'mnemonicWords'),
      ),
    ).thenAnswer((_) async => [wallet]);
    when(completePhysicalBackup.execute).thenAnswer((_) async {});
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
      () => createDefaultWallets.execute(
        mnemonicWords: any(named: 'mnemonicWords'),
      ),
    ).thenAnswer((_) async {
      order.add('create');
      final wallet = _MockWallet();
      when(() => wallet.id).thenReturn('default-btc');
      return [wallet];
    });
    when(completePhysicalBackup.execute).thenAnswer((_) async {
      order.add('verify');
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
      () => createDefaultWallets.execute(
        mnemonicWords: any(named: 'mnemonicWords'),
      ),
    ).called(1);
  });
}
