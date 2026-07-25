import 'dart:async';

import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/create_default_wallets_usecase.dart';
import 'package:bb_mobile/features/onboarding/complete_physical_backup_verification_usecase.dart';
import 'package:bb_mobile/features/onboarding/presentation/bloc/onboarding_bloc.dart';
import 'package:bb_mobile/features/onboarding/recover_remote_keychain_usecase.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

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

  OnboardingBloc buildBloc() {
    return OnboardingBloc(
      createDefaultWalletsUsecase: createDefaultWallets,
      completePhysicalBackupVerificationUsecase: completePhysicalBackup,
      recoverRemoteKeychainUsecase: recoverRemoteKeychain,
    );
  }

  setUp(() {
    createDefaultWallets = _MockCreateDefaultWallets();
    completePhysicalBackup = _MockCompletePhysicalBackup();
    recoverRemoteKeychain = _MockRecoverRemoteKeychain();

    when(
      () => createDefaultWallets.execute(
        mnemonicWords: any(named: 'mnemonicWords'),
      ),
    ).thenAnswer((_) async => <Wallet>[]);
    when(completePhysicalBackup.execute).thenAnswer((_) async {});
    when(recoverRemoteKeychain.execute).thenAnswer((_) async {});
  });

  test('does not signal success until manifest recovery completes', () async {
    final recoveryGate = Completer<void>();
    when(recoverRemoteKeychain.execute).thenAnswer((_) => recoveryGate.future);

    final bloc = buildBloc();
    addTearDown(bloc.close);

    bloc.add(OnboardingRecoverWalletClicked(mnemonic: mnemonic()));
    await pumpEventQueue();

    verify(recoverRemoteKeychain.execute).called(1);
    expect(bloc.state.onboardingStepStatus, OnboardingStepStatus.loading);

    recoveryGate.complete();
    await pumpEventQueue();

    expect(bloc.state.onboardingStepStatus, OnboardingStepStatus.success);
  });

  test('orders seed restore, verification, and remote recovery', () async {
    final order = <String>[];
    when(
      () => createDefaultWallets.execute(
        mnemonicWords: any(named: 'mnemonicWords'),
      ),
    ).thenAnswer((_) async {
      order.add('create');
      return <Wallet>[];
    });
    when(completePhysicalBackup.execute).thenAnswer((_) async {
      order.add('verify');
    });
    when(recoverRemoteKeychain.execute).thenAnswer((_) async {
      order.add('recover');
    });

    final bloc = buildBloc();
    addTearDown(bloc.close);

    bloc.add(OnboardingRecoverWalletClicked(mnemonic: mnemonic()));
    await pumpEventQueue();

    expect(order, ['create', 'verify', 'recover']);
    expect(bloc.state.onboardingStepStatus, OnboardingStepStatus.success);
  });
}

final class _MockCreateDefaultWallets extends Mock
    implements CreateDefaultWalletsUsecase {}

final class _MockCompletePhysicalBackup extends Mock
    implements CompletePhysicalBackupVerificationUsecase {}

final class _MockRecoverRemoteKeychain extends Mock
    implements RecoverRemoteKeychainUsecase {}
