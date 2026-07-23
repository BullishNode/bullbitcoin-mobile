import 'dart:async';

import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/keychain_recovery/public/keychain_recovery_facade.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/payment_page/public/payment_page_facade.dart';
import 'package:bb_mobile/features/pos/public/pos_facade.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/recover_remote_keychain_manifest_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_result.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/heal_recovered_products_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/public/wallet_backup_facade.dart';
import 'package:bb_mobile/features/wallet_backup/watchers/wallet_backup_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeWalletBackupFacade walletBackup;
  late _FakeKeychainManifestFacade manifest;
  late _FakeKeychainRecoveryFacade recovery;
  late _FakeLightningAddressFacade lightningAddress;
  late _FakePaymentPageFacade paymentPage;
  late _FakePosFacade pos;

  RecoverRemoteKeychainManifestUsecase buildUsecase({
    Clock clock = const SystemClock(),
    Duration budget =
        RecoverRemoteKeychainManifestUsecase.defaultRecoveryBudget,
  }) {
    return RecoverRemoteKeychainManifestUsecase(
      walletBackup,
      manifest,
      recovery,
      HealRecoveredProductsUsecase(lightningAddress, paymentPage, pos),
      clock: clock,
      budget: budget,
    );
  }

  setUp(() {
    walletBackup = _FakeWalletBackupFacade();
    manifest = _FakeKeychainManifestFacade();
    recovery = _FakeKeychainRecoveryFacade();
    lightningAddress = _FakeLightningAddressFacade();
    paymentPage = _FakePaymentPageFacade();
    pos = _FakePosFacade();
  });

  test(
    'reports an absent unified backup without parsing or restoring',
    () async {
      final result = await buildUsecase().execute();

      expect(result.status, RemoteKeychainRecoveryStatus.noBackup);
      expect(walletBackup.fetchCalls, 1);
      expect(manifest.parseCalls, 0);
      expect(recovery.restoreCalls, 0);
    },
  );

  test('distinguishes a present empty manifest from no backup', () async {
    walletBackup.fetchResult = Ok(
      _manifestImport(metadataPayload: '{"sections":[],"records":[]}'),
    );
    manifest.plan = _plan(entries: const []);

    final result = await buildUsecase().execute();

    expect(result.status, RemoteKeychainRecoveryStatus.nothingToRestore);
    expect(result.metadataPayload, '{"sections":[],"records":[]}');
    expect(recovery.restoreCalls, 0);
  });

  for (final testCase
      in <({WalletBackupFailure failure, RemoteKeychainRecoveryStatus status})>[
        (
          failure: const WalletBackupRemoteUnavailableFailure(),
          status: RemoteKeychainRecoveryStatus.unavailable,
        ),
        (
          failure: const WalletBackupTooLargeFailure(),
          status: RemoteKeychainRecoveryStatus.tooLarge,
        ),
        (
          failure: const WalletBackupUnsupportedEnvelopeVersionFailure(2),
          status: RemoteKeychainRecoveryStatus.newerVersion,
        ),
        (
          failure: const WalletBackupUnsupportedSectionFailure(
            sectionId: 'manifest',
            version: 2,
          ),
          status: RemoteKeychainRecoveryStatus.newerVersion,
        ),
        (
          failure: const WalletBackupHeadConflictFailure(),
          status: RemoteKeychainRecoveryStatus.conflict,
        ),
        (
          failure: const WalletBackupInvalidEnvelopeFailure(),
          status: RemoteKeychainRecoveryStatus.invalid,
        ),
        (
          failure: const WalletBackupManifestFailure(),
          status: RemoteKeychainRecoveryStatus.invalid,
        ),
        (
          failure: const WalletBackupKeyDerivationFailure(),
          status: RemoteKeychainRecoveryStatus.localFailure,
        ),
        (
          failure: const WalletBackupRemoteRejectedFailure(),
          status: RemoteKeychainRecoveryStatus.localFailure,
        ),
      ]) {
    test(
      'maps ${testCase.failure.runtimeType} to ${testCase.status.name}',
      () async {
        walletBackup.fetchResult = Err(testCase.failure);

        final result = await buildUsecase().execute();

        expect(result.status, testCase.status);
        expect(recovery.restoreCalls, 0);
      },
    );
  }

  test('fails closed when the public DTO cannot be reparsed', () async {
    walletBackup.fetchResult = Ok(_manifestImport());
    manifest.parseError = KeychainManifestFileParseException(
      reason: KeychainManifestFileParseFailureReason.invalidMetadata,
    );

    final result = await buildUsecase().execute();

    expect(result.status, RemoteKeychainRecoveryStatus.invalid);
    expect(recovery.restoreCalls, 0);
  });

  test('restores a validated plan and reports newly created wallets', () async {
    final plan = _plan(entries: [_entry()]);
    walletBackup.fetchResult = Ok(_manifestImport());
    manifest.plan = plan;
    recovery.result = const KeychainRecoveryResult(
      walletOutcomes: [
        KeychainRecoveryWalletRestoreOutcome(
          intent: _btcpayIntent,
          status: KeychainRecoveryWalletRestoreStatus.created,
          materializedWalletId: 'btcpay-wallet',
          created: true,
        ),
      ],
    );

    final result = await buildUsecase().execute();

    expect(result.status, RemoteKeychainRecoveryStatus.restored);
    expect(result.restoredCount, 1);
    expect(result.failedCount, 0);
    expect(result.createdWalletIds, ['btcpay-wallet']);
    expect(recovery.deadlines.single, isNotNull);
  });

  test('heals only a restored product that requests reactivation', () async {
    final plan = _plan(entries: [_entry(lightningAddress: true)]);
    walletBackup.fetchResult = Ok(_manifestImport());
    manifest.plan = plan;
    recovery.result = const KeychainRecoveryResult(
      walletOutcomes: [
        KeychainRecoveryWalletRestoreOutcome(
          intent: _lightningAddressIntent,
          status:
              KeychainRecoveryWalletRestoreStatus.requiresProductReactivation,
          materializedWalletId: 'lightning-wallet',
          created: true,
        ),
      ],
    );

    final result = await buildUsecase().execute();

    expect(result.status, RemoteKeychainRecoveryStatus.restored);
    expect(result.createdWalletIds, ['lightning-wallet']);
    expect(lightningAddress.ensureCalls, 1);
    expect(lightningAddress.allowReregisterCalls, [false]);
  });

  test('heals a restored payment page that requests reactivation', () async {
    final plan = _plan(entries: [_paymentPageEntry()]);
    walletBackup.fetchResult = Ok(_manifestImport());
    manifest.plan = plan;
    recovery.result = const KeychainRecoveryResult(
      walletOutcomes: [
        KeychainRecoveryWalletRestoreOutcome(
          intent: _paymentPageIntent,
          status:
              KeychainRecoveryWalletRestoreStatus.requiresProductReactivation,
          materializedWalletId: 'payment-page-wallet',
          created: true,
        ),
      ],
    );

    final result = await buildUsecase().execute();

    expect(result.status, RemoteKeychainRecoveryStatus.restored);
    expect(result.createdWalletIds, ['payment-page-wallet']);
    expect(paymentPage.ensureCalls, 1);
  });

  test('heals a restored point of sale that requests reactivation', () async {
    final plan = _plan(entries: [_posEntry()]);
    walletBackup.fetchResult = Ok(_manifestImport());
    manifest.plan = plan;
    recovery.result = const KeychainRecoveryResult(
      walletOutcomes: [
        KeychainRecoveryWalletRestoreOutcome(
          intent: _posIntent,
          status:
              KeychainRecoveryWalletRestoreStatus.requiresProductReactivation,
          materializedWalletId: 'pos-wallet',
          created: true,
        ),
      ],
    );

    final result = await buildUsecase().execute();

    expect(result.status, RemoteKeychainRecoveryStatus.restored);
    expect(result.createdWalletIds, ['pos-wallet']);
    expect(pos.ensureCalls, 1);
  });

  test('reports partial restoration without discarding successes', () async {
    final plan = _plan(entries: [_entry()]);
    walletBackup.fetchResult = Ok(_manifestImport());
    manifest.plan = plan;
    recovery.result = const KeychainRecoveryResult(
      walletOutcomes: [
        KeychainRecoveryWalletRestoreOutcome(
          intent: _btcpayIntent,
          status: KeychainRecoveryWalletRestoreStatus.created,
          created: true,
        ),
        KeychainRecoveryWalletRestoreOutcome(
          intent: _otherBtcpayIntent,
          status: KeychainRecoveryWalletRestoreStatus.failedWalletCreation,
        ),
      ],
    );

    final result = await buildUsecase().execute();

    expect(result.status, RemoteKeychainRecoveryStatus.partiallyRestored);
    expect(result.restoredCount, 1);
    expect(result.failedCount, 1);
  });

  test(
    'deadline expiry after a success retains counts but reports timedOut',
    () async {
      final plan = _plan(entries: [_entry()]);
      walletBackup.fetchResult = Ok(_manifestImport());
      manifest.plan = plan;
      recovery.result = const KeychainRecoveryResult(
        walletOutcomes: [
          KeychainRecoveryWalletRestoreOutcome(
            intent: _btcpayIntent,
            status: KeychainRecoveryWalletRestoreStatus.created,
            materializedWalletId: 'btcpay-wallet',
            created: true,
          ),
          KeychainRecoveryWalletRestoreOutcome(
            intent: _otherBtcpayIntent,
            status:
                KeychainRecoveryWalletRestoreStatus.skippedTimeBudgetExpired,
          ),
        ],
      );

      final result = await buildUsecase().execute();

      expect(result.status, RemoteKeychainRecoveryStatus.timedOut);
      expect(result.restoredCount, 1);
      expect(result.failedCount, 1);
      expect(result.createdWalletIds, ['btcpay-wallet']);
    },
  );

  test('healing deadline expiry retains restored wallet counts', () async {
    final plan = _plan(entries: [_entry(lightningAddress: true)]);
    walletBackup.fetchResult = Ok(_manifestImport());
    manifest.plan = plan;
    recovery.result = const KeychainRecoveryResult(
      walletOutcomes: [
        KeychainRecoveryWalletRestoreOutcome(
          intent: _lightningAddressIntent,
          status:
              KeychainRecoveryWalletRestoreStatus.requiresProductReactivation,
          materializedWalletId: 'lightning-wallet',
          created: true,
        ),
      ],
    );
    lightningAddress.outcome = const LightningAddressHealOutcome(
      liveness: LightningAddressRegistrationLiveness.timedOut,
    );

    final result = await buildUsecase().execute();

    expect(result.status, RemoteKeychainRecoveryStatus.timedOut);
    expect(result.restoredCount, 1);
    expect(result.failedCount, 0);
    expect(result.createdWalletIds, ['lightning-wallet']);
    expect(lightningAddress.ensureCalls, 1);
  });

  test('final successful restoration crossing deadline skips healing and '
      'reports timedOut with counts', () async {
    final plan = _plan(entries: [_entry(lightningAddress: true)]);
    final clock = _FakeClock(DateTime.utc(2026));
    walletBackup.fetchResult = Ok(_manifestImport());
    manifest.plan = plan;
    recovery.result = const KeychainRecoveryResult(
      walletOutcomes: [
        KeychainRecoveryWalletRestoreOutcome(
          intent: _lightningAddressIntent,
          status:
              KeychainRecoveryWalletRestoreStatus.requiresProductReactivation,
          materializedWalletId: 'lightning-wallet',
          created: true,
        ),
      ],
    );
    recovery.beforeReturn = () => clock.advance(const Duration(seconds: 61));

    final result = await buildUsecase(
      clock: clock,
      budget: const Duration(seconds: 60),
    ).execute();

    expect(result.status, RemoteKeychainRecoveryStatus.timedOut);
    expect(result.restoredCount, 1);
    expect(result.failedCount, 0);
    expect(result.createdWalletIds, ['lightning-wallet']);
    expect(lightningAddress.ensureCalls, 0);
  });

  test('maps an all-invalid materialization result to invalid', () async {
    final plan = _plan(entries: [_entry()]);
    walletBackup.fetchResult = Ok(_manifestImport());
    manifest.plan = plan;
    recovery.result = const KeychainRecoveryResult(
      walletOutcomes: [
        KeychainRecoveryWalletRestoreOutcome(
          intent: _btcpayIntent,
          status: KeychainRecoveryWalletRestoreStatus.failedInvalidImportPlan,
        ),
      ],
    );

    final result = await buildUsecase().execute();

    expect(result.status, RemoteKeychainRecoveryStatus.invalid);
  });

  test('bounds a stalled remote fetch with the total budget', () async {
    final fetch =
        Completer<Result<WalletBackupManifestImport?, WalletBackupFailure>>();
    walletBackup.fetchFuture = fetch.future;

    final result = await buildUsecase(
      budget: const Duration(milliseconds: 10),
    ).execute();

    expect(result.status, RemoteKeychainRecoveryStatus.timedOut);
    expect(recovery.restoreCalls, 0);
    fetch.complete(const Ok(null));
  });

  test('does not start product healing after the deadline', () async {
    final plan = _plan(entries: [_entry(lightningAddress: true)]);
    walletBackup.fetchResult = Ok(_manifestImport());
    manifest.plan = plan;
    recovery.delay = const Duration(milliseconds: 30);
    recovery.result = const KeychainRecoveryResult(
      walletOutcomes: [
        KeychainRecoveryWalletRestoreOutcome(
          intent: _lightningAddressIntent,
          status:
              KeychainRecoveryWalletRestoreStatus.requiresProductReactivation,
          created: true,
        ),
      ],
    );

    final result = await buildUsecase(
      budget: const Duration(milliseconds: 10),
    ).execute();
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(result.status, RemoteKeychainRecoveryStatus.timedOut);
    expect(lightningAddress.ensureCalls, 0);
  });

  test(
    'started restoration holds the recovery lease beyond its deadline',
    () async {
      final plan = _plan(entries: [_entry()]);
      final restore = Completer<KeychainRecoveryResult>();
      walletBackup.fetchResult = Ok(_manifestImport());
      manifest.plan = plan;
      recovery.restoreFuture = restore.future;
      final coordinator = WalletBackupCoordinator(
        manifestChanges: const Stream.empty(),
        syncResults: const Stream.empty(),
        publishBackup: () async => const Ok(null),
        markDirty: () async => const Ok(null),
      );
      addTearDown(coordinator.dispose);
      final lease = await coordinator.beginRecoveryLease();
      var recoveryFinished = false;
      final recoveryOperation =
          buildUsecase(
            budget: const Duration(milliseconds: 10),
          ).execute().whenComplete(() {
            recoveryFinished = true;
            lease.close();
          });

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(recovery.restoreCalls, 1);
      expect(recoveryFinished, isFalse);
      var deletionStarted = false;
      final deletion = coordinator.beginDeletionLease().then((lease) {
        deletionStarted = true;
        lease.close();
      });
      await pumpEventQueue();
      expect(deletionStarted, isFalse);

      restore.complete(
        const KeychainRecoveryResult(
          walletOutcomes: [
            KeychainRecoveryWalletRestoreOutcome(
              intent: _btcpayIntent,
              status: KeychainRecoveryWalletRestoreStatus.created,
              materializedWalletId: 'btcpay-wallet',
              created: true,
            ),
          ],
        ),
      );

      final result = await recoveryOperation;
      await deletion;
      expect(result.status, RemoteKeychainRecoveryStatus.timedOut);
      expect(result.restoredCount, 1);
      expect(deletionStarted, isTrue);
    },
  );
}

WalletBackupManifestImport _manifestImport({String? metadataPayload}) {
  return WalletBackupManifestImport(
    payload: '{"manifest":"payload"}',
    parentFingerprint: 'fedcba98',
    metadataPayload: metadataPayload,
  );
}

KeychainManifestImportPlan _plan({
  required List<KeychainManifestImportEntryIntent> entries,
}) {
  return KeychainManifestImportPlan(
    parentFingerprint: 'fedcba98',
    entries: entries,
  );
}

KeychainManifestImportEntryIntent _entry({bool lightningAddress = false}) {
  final path = lightningAddress ? "39'/0'/12'/101'" : "39'/0'/12'/100'";
  final reservationId = lightningAddress
      ? 'lightning_address_wallet_seed'
      : 'btcpay_wallet_seed';
  final owner = lightningAddress ? 'lightningAddress' : 'btcpay';
  final walletId = lightningAddress ? 'lightning-wallet' : 'btcpay-wallet';
  return KeychainManifestImportEntryIntent(
    entryId: 'fedcba98:$path',
    parentFingerprint: 'fedcba98',
    bip85DerivationPath: path,
    reservationId: reservationId,
    entryType: 'walletSeed',
    ownerFeature: owner,
    bip85Application: 39,
    bip85Index: lightningAddress ? 101 : 100,
    walletMaterializations: [
      KeychainManifestWalletMaterializationIntent(
        entryId: 'fedcba98:$path',
        reservationId: reservationId,
        bip85DerivationPath: path,
        walletId: walletId,
        childSeedFingerprint: lightningAddress ? '89abcdef' : '0123abcd',
        network: lightningAddress
            ? Network.liquidMainnet
            : Network.bitcoinMainnet,
        scriptType: ScriptType.bip84,
      ),
    ],
  );
}

KeychainManifestImportEntryIntent _paymentPageEntry() {
  const path = "39'/0'/12'/102'";
  return KeychainManifestImportEntryIntent(
    entryId: 'fedcba98:$path',
    parentFingerprint: 'fedcba98',
    bip85DerivationPath: path,
    reservationId: 'payment_page_wallet_seed',
    entryType: 'walletSeed',
    ownerFeature: 'paymentPage',
    bip85Application: 39,
    bip85Index: 102,
    walletMaterializations: [
      KeychainManifestWalletMaterializationIntent(
        entryId: 'fedcba98:$path',
        reservationId: 'payment_page_wallet_seed',
        bip85DerivationPath: path,
        walletId: 'payment-page-wallet',
        childSeedFingerprint: 'cdef0123',
        network: Network.liquidMainnet,
        scriptType: ScriptType.bip84,
      ),
    ],
  );
}

KeychainManifestImportEntryIntent _posEntry() {
  const path = "39'/0'/12'/103'";
  return KeychainManifestImportEntryIntent(
    entryId: 'fedcba98:$path',
    parentFingerprint: 'fedcba98',
    bip85DerivationPath: path,
    reservationId: 'pos_wallet_seed',
    entryType: 'walletSeed',
    ownerFeature: 'pos',
    bip85Application: 39,
    bip85Index: 103,
    walletMaterializations: [
      KeychainManifestWalletMaterializationIntent(
        entryId: 'fedcba98:$path',
        reservationId: 'pos_wallet_seed',
        bip85DerivationPath: path,
        walletId: 'pos-wallet',
        childSeedFingerprint: 'def01234',
        network: Network.liquidMainnet,
        scriptType: ScriptType.bip84,
      ),
    ],
  );
}

const _btcpayIntent = KeychainRecoveryWalletIntent(
  entryId: "fedcba98:39'/0'/12'/100'",
  reservationId: 'btcpay_wallet_seed',
  bip85DerivationPath: "39'/0'/12'/100'",
  walletId: 'btcpay-wallet',
  childSeedFingerprint: '0123abcd',
  network: Network.bitcoinMainnet,
  scriptType: ScriptType.bip84,
);

const _otherBtcpayIntent = KeychainRecoveryWalletIntent(
  entryId: "fedcba98:39'/0'/12'/100'",
  reservationId: 'btcpay_wallet_seed',
  bip85DerivationPath: "39'/0'/12'/100'",
  walletId: 'btcpay-liquid-wallet',
  childSeedFingerprint: '4567abcd',
  network: Network.liquidMainnet,
  scriptType: ScriptType.bip84,
);

const _lightningAddressIntent = KeychainRecoveryWalletIntent(
  entryId: "fedcba98:39'/0'/12'/101'",
  reservationId: 'lightning_address_wallet_seed',
  bip85DerivationPath: "39'/0'/12'/101'",
  walletId: 'lightning-wallet',
  childSeedFingerprint: '89abcdef',
  network: Network.liquidMainnet,
  scriptType: ScriptType.bip84,
);

const _paymentPageIntent = KeychainRecoveryWalletIntent(
  entryId: "fedcba98:39'/0'/12'/102'",
  reservationId: 'payment_page_wallet_seed',
  bip85DerivationPath: "39'/0'/12'/102'",
  walletId: 'payment-page-wallet',
  childSeedFingerprint: 'cdef0123',
  network: Network.liquidMainnet,
  scriptType: ScriptType.bip84,
);

const _posIntent = KeychainRecoveryWalletIntent(
  entryId: "fedcba98:39'/0'/12'/103'",
  reservationId: 'pos_wallet_seed',
  bip85DerivationPath: "39'/0'/12'/103'",
  walletId: 'pos-wallet',
  childSeedFingerprint: 'def01234',
  network: Network.liquidMainnet,
  scriptType: ScriptType.bip84,
);

final class _FakeWalletBackupFacade implements WalletBackupFacade {
  Result<WalletBackupManifestImport?, WalletBackupFailure> fetchResult =
      const Ok(null);
  Future<Result<WalletBackupManifestImport?, WalletBackupFailure>>? fetchFuture;
  int fetchCalls = 0;

  @override
  Future<Result<WalletBackupManifestImport?, WalletBackupFailure>>
  fetchManifestImport() {
    fetchCalls++;
    return fetchFuture ?? Future.value(fetchResult);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeKeychainManifestFacade implements KeychainManifestFacade {
  KeychainManifestImportPlan? plan;
  KeychainManifestException? parseError;
  int parseCalls = 0;

  @override
  KeychainManifestImportPlan parseManifestFilePayload(
    String payload, {
    required String expectedParentFingerprint,
    bool allowEmpty = false,
  }) {
    parseCalls++;
    final error = parseError;
    if (error != null) throw error;
    expect(payload, '{"manifest":"payload"}');
    expect(expectedParentFingerprint, 'fedcba98');
    expect(allowEmpty, true);
    return plan!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeKeychainRecoveryFacade implements KeychainRecoveryFacade {
  KeychainRecoveryResult result = const KeychainRecoveryResult(
    walletOutcomes: [],
  );
  Duration delay = Duration.zero;
  Future<KeychainRecoveryResult>? restoreFuture;
  void Function()? beforeReturn;
  int restoreCalls = 0;
  final deadlines = <DateTime?>[];

  @override
  Future<KeychainRecoveryResult> restoreWallets(
    KeychainManifestImportPlan importPlan, {
    DateTime? deadline,
  }) async {
    restoreCalls++;
    deadlines.add(deadline);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    beforeReturn?.call();
    return await (restoreFuture ?? Future.value(result));
  }
}

final class _FakeLightningAddressFacade implements LightningAddressFacade {
  int ensureCalls = 0;
  final allowReregisterCalls = <bool>[];
  LightningAddressHealOutcome outcome = const LightningAddressHealOutcome(
    liveness: LightningAddressRegistrationLiveness.live,
  );

  @override
  Future<LightningAddressHealOutcome> ensureRegistrationLive({
    DateTime? deadline,
    bool allowReregister = true,
  }) async {
    ensureCalls++;
    allowReregisterCalls.add(allowReregister);
    return outcome;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakePaymentPageFacade implements PaymentPageFacade {
  int ensureCalls = 0;
  PaymentPageHealOutcome outcome = const PaymentPageHealOutcome(
    liveness: PaymentPageLiveness.live,
  );

  @override
  Future<PaymentPageHealOutcome> ensurePageLive() async {
    ensureCalls++;
    return outcome;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakePosFacade implements PosFacade {
  int ensureCalls = 0;
  PosHealOutcome outcome = const PosHealOutcome(liveness: PosLiveness.live);

  @override
  Future<PosHealOutcome> ensurePosLive() async {
    ensureCalls++;
    return outcome;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeClock implements Clock {
  DateTime current;

  _FakeClock(this.current);

  void advance(Duration duration) {
    current = current.add(duration);
  }

  @override
  DateTime nowUtc() => current;
}
