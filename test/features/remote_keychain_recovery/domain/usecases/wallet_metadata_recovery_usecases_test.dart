import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_default_wallet_xprv.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_default_wallet_xprv_port.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_wallet_metadata_recovery_failure.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/apply_remote_wallet_metadata_recovery_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/check_remote_wallet_metadata_recovery_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_facade.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeWalletMetadataBackupFacade metadataBackup;

  setUp(() {
    metadataBackup = _FakeWalletMetadataBackupFacade();
  });

  test('derives and forwards the default wallet root for lookup', () async {
    final xprv = _FakeDefaultWalletXprvPort();
    metadataBackup.fetchResult = const Err(WalletMetadataBackupRelayFailure());

    final result = await CheckRemoteWalletMetadataRecoveryUsecase(
      defaultWalletXprv: xprv,
      metadataBackup: metadataBackup,
    ).execute();

    expect(metadataBackup.fetchedXprv, 'test-xprv');
    expect(metadataBackup.fetchedFingerprint, '627ef3a6');
    expect(
      result,
      isA<
        Err<WalletMetadataRecoveryResult, RemoteWalletMetadataRecoveryFailure>
      >(),
    );
    expect(
      (result
              as Err<
                WalletMetadataRecoveryResult,
                RemoteWalletMetadataRecoveryFailure
              >)
          .failure,
      isA<RemoteWalletMetadataRecoveryUnavailableFailure>(),
    );
  });

  test(
    'maps default wallet derivation exceptions into the recovery domain',
    () async {
      final xprv = _FakeDefaultWalletXprvPort()..error = Exception('failed');

      final result = await CheckRemoteWalletMetadataRecoveryUsecase(
        defaultWalletXprv: xprv,
        metadataBackup: metadataBackup,
      ).execute();

      expect(metadataBackup.fetchedXprv, isNull);
      expect(
        result,
        isA<
          Err<WalletMetadataRecoveryResult, RemoteWalletMetadataRecoveryFailure>
        >(),
      );
    },
  );

  test('forwards apply inputs and translates metadata failures', () async {
    const plan = _FakeRecoveryPlan();
    metadataBackup.applyResult = const Err(
      WalletMetadataBackupEncodingFailure(),
    );

    final result = await ApplyRemoteWalletMetadataRecoveryUsecase(
      metadataBackup,
    ).execute(plan: plan, createdWalletRefs: {'wallet-a'});

    expect(metadataBackup.appliedPlan, same(plan));
    expect(metadataBackup.appliedWalletRefs, {'wallet-a'});
    expect(
      result,
      isA<
        Err<
          WalletMetadataRecoveryApplyResult,
          RemoteWalletMetadataRecoveryFailure
        >
      >(),
    );
    expect(
      (result
              as Err<
                WalletMetadataRecoveryApplyResult,
                RemoteWalletMetadataRecoveryFailure
              >)
          .failure,
      isA<RemoteWalletMetadataRecoveryUnavailableFailure>(),
    );
  });
}

class _FakeDefaultWalletXprvPort
    implements RemoteKeychainRecoveryDefaultWalletXprvPort {
  Exception? error;

  @override
  Future<RemoteKeychainRecoveryDefaultWalletXprv>
  deriveDefaultWalletXprv() async {
    final error = this.error;
    if (error != null) throw error;
    return const RemoteKeychainRecoveryDefaultWalletXprv(
      xprvBase58: 'test-xprv',
      parentFingerprint: '627ef3a6',
    );
  }
}

class _FakeRecoveryPlan implements WalletMetadataRecoveryPlan {
  const _FakeRecoveryPlan();

  @override
  int get invalidRecordCount => 0;

  @override
  bool get isOlderRestore => false;

  @override
  int get plannedRecordCount => 1;

  @override
  int get unsupportedCount => 0;
}

class _FakeWalletMetadataBackupFacade implements WalletMetadataBackupFacade {
  Result<WalletMetadataRecoveryResult, WalletMetadataBackupFailure>
  fetchResult = const Ok(WalletMetadataRecoveryResult.noSnapshotFound());
  Result<WalletMetadataRecoveryApplyResult, WalletMetadataBackupFailure>
  applyResult = const Err(WalletMetadataBackupEncodingFailure());

  String? fetchedXprv;
  String? fetchedFingerprint;
  WalletMetadataRecoveryPlan? appliedPlan;
  Set<String>? appliedWalletRefs;

  @override
  Future<Result<WalletMetadataRecoveryResult, WalletMetadataBackupFailure>>
  fetchRecoveryPlan({
    required String xprvBase58,
    required String parentFingerprint,
  }) async {
    fetchedXprv = xprvBase58;
    fetchedFingerprint = parentFingerprint;
    return fetchResult;
  }

  @override
  Future<Result<WalletMetadataRecoveryApplyResult, WalletMetadataBackupFailure>>
  applyRecoveryPlan({
    required WalletMetadataRecoveryPlan plan,
    required Set<String> createdWalletRefs,
  }) async {
    appliedPlan = plan;
    appliedWalletRefs = Set.of(createdWalletRefs);
    return applyResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
