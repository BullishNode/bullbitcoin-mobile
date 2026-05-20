import 'package:bb_mobile/core/wallet/domain/usecases/create_default_wallets_usecase.dart';
import 'package:bb_mobile/features/onboarding/complete_physical_backup_verification_usecase.dart';
import 'package:bb_mobile/features/onboarding/presentation/bloc/onboarding_bloc.dart';
import 'package:bb_mobile/features/onboarding/application/start_onboarding_wallet_manifest_restore_usecase.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCreateDefaultWallets extends Mock
    implements CreateDefaultWalletsUsecase {}

class _MockCompletePhysicalBackupVerification extends Mock
    implements CompletePhysicalBackupVerificationUsecase {}

class _MockStartWalletManifestRestore extends Mock
    implements StartOnboardingWalletManifestRestoreUsecase {}

void main() {
  late _MockCreateDefaultWallets createDefaultWallets;
  late _MockCompletePhysicalBackupVerification completePhysicalBackup;
  late _MockStartWalletManifestRestore startWalletManifestRestore;
  late OnboardingBloc bloc;
  late bool walletRefreshRequested;

  setUp(() {
    createDefaultWallets = _MockCreateDefaultWallets();
    completePhysicalBackup = _MockCompletePhysicalBackupVerification();
    startWalletManifestRestore = _MockStartWalletManifestRestore();
    walletRefreshRequested = false;
    bloc = OnboardingBloc(
      createDefaultWalletsUsecase: createDefaultWallets,
      completePhysicalBackupVerificationUsecase: completePhysicalBackup,
      startWalletManifestRestore: startWalletManifestRestore,
      onWalletStateMayHaveChanged: () => walletRefreshRequested = true,
    );

    when(
      () => createDefaultWallets.execute(
        mnemonicWords: any(named: 'mnemonicWords'),
      ),
    ).thenAnswer((_) async => const []);
    when(
      () => createDefaultWallets.execute(),
    ).thenAnswer((_) async => const []);
    when(() => completePhysicalBackup.execute()).thenAnswer((_) async {});
  });

  tearDown(() async {
    await bloc.close();
  });

  test(
    'physical seed recovery starts non-blocking wallet manifest restore',
    () async {
      final calls = <String>[];
      void Function()? capturedCallback;
      when(
        () => createDefaultWallets.execute(
          mnemonicWords: any(named: 'mnemonicWords'),
        ),
      ).thenAnswer((_) async {
        calls.add('default-wallets');
        return const [];
      });
      when(() => completePhysicalBackup.execute()).thenAnswer((_) async {
        calls.add('physical-backup');
      });
      when(
        () => startWalletManifestRestore.execute(
          onWalletStateMayHaveChanged: any(
            named: 'onWalletStateMayHaveChanged',
          ),
        ),
      ).thenAnswer((invocation) {
        calls.add('wallet-manifest');
        capturedCallback =
            invocation.namedArguments[#onWalletStateMayHaveChanged]
                as void Function()?;
      });

      bloc.add(
        OnboardingRecoverWalletClicked(
          mnemonic: (
            words: const [
              'abandon',
              'abandon',
              'abandon',
              'abandon',
              'abandon',
              'abandon',
              'abandon',
              'abandon',
              'abandon',
              'abandon',
              'abandon',
              'about',
            ],
            passphrase: '',
            label: '',
            language: bip39.Language.english,
          ),
        ),
      );

      await expectLater(
        bloc.stream,
        emitsThrough(
          isA<OnboardingState>().having(
            (state) => state.onboardingStepStatus,
            'status',
            OnboardingStepStatus.success,
          ),
        ),
      );

      expect(calls, ['default-wallets', 'physical-backup', 'wallet-manifest']);

      capturedCallback?.call();
      expect(walletRefreshRequested, isTrue);
    },
  );

  test('new wallet creation does not start wallet manifest restore', () async {
    bloc.add(const OnboardingCreateNewWallet());

    await expectLater(
      bloc.stream,
      emitsThrough(
        isA<OnboardingState>().having(
          (state) => state.onboardingStepStatus,
          'status',
          OnboardingStepStatus.success,
        ),
      ),
    );

    verify(() => createDefaultWallets.execute()).called(1);
    verifyNever(
      () => startWalletManifestRestore.execute(
        onWalletStateMayHaveChanged: any(named: 'onWalletStateMayHaveChanged'),
      ),
    );
  });

  test(
    'does not start wallet manifest restore if physical recovery fails',
    () async {
      when(
        () => createDefaultWallets.execute(
          mnemonicWords: any(named: 'mnemonicWords'),
        ),
      ).thenThrow(Exception('restore failed'));

      bloc.add(
        OnboardingRecoverWalletClicked(
          mnemonic: (
            words: const ['abandon'],
            passphrase: '',
            label: '',
            language: bip39.Language.english,
          ),
        ),
      );

      await expectLater(
        bloc.stream,
        emitsThrough(
          isA<OnboardingState>().having(
            (state) => state.onboardingStepStatus,
            'status',
            OnboardingStepStatus.none,
          ),
        ),
      );

      verifyNever(() => completePhysicalBackup.execute());
      verifyNever(
        () => startWalletManifestRestore.execute(
          onWalletStateMayHaveChanged: any(
            named: 'onWalletStateMayHaveChanged',
          ),
        ),
      );
    },
  );

  test(
    'does not start wallet manifest restore if backup verification fails',
    () async {
      when(
        () => completePhysicalBackup.execute(),
      ).thenThrow(Exception('backup verification failed'));

      bloc.add(
        OnboardingRecoverWalletClicked(
          mnemonic: (
            words: const ['abandon'],
            passphrase: '',
            label: '',
            language: bip39.Language.english,
          ),
        ),
      );

      await expectLater(
        bloc.stream,
        emitsThrough(
          isA<OnboardingState>().having(
            (state) => state.onboardingStepStatus,
            'status',
            OnboardingStepStatus.none,
          ),
        ),
      );

      verifyNever(
        () => startWalletManifestRestore.execute(
          onWalletStateMayHaveChanged: any(
            named: 'onWalletStateMayHaveChanged',
          ),
        ),
      );
    },
  );
}
