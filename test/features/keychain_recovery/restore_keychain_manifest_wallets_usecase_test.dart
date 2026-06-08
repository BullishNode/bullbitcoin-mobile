import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/keychain_recovery/domain/keychain_recovery_result.dart';
import 'package:bb_mobile/features/keychain_recovery/domain/keychain_recovery_wallet_materializer_port.dart';
import 'package:bb_mobile/features/keychain_recovery/domain/restore_keychain_manifest_wallets_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeWalletMaterializer materializer;
  late _FakeKeychainManifestFacade keychainManifest;
  late RestoreKeychainManifestWalletsUsecase usecase;

  setUp(() {
    materializer = _FakeWalletMaterializer();
    keychainManifest = _FakeKeychainManifestFacade();
    usecase = RestoreKeychainManifestWalletsUsecase(
      walletMaterializer: materializer,
      keychainManifest: keychainManifest,
    );
  });

  test('records and reports restored wallet materializations', () async {
    final intent = _intent();
    materializer.result = KeychainRecoveryWalletMaterializationResult(
      materializedWallets: [
        KeychainRecoveryMaterializedWallet(
          intent: _recoveryIntent(intent),
          walletId: intent.walletId,
          network: intent.network,
          scriptType: intent.scriptType,
          childSeedFingerprint: intent.childSeedFingerprint,
          created: true,
        ),
      ],
      failedOutcomes: const [],
    );

    final result = await usecase.execute(_plan(intent));

    expect(result.hasFailures, false);
    expect(result.walletOutcomes.single.status, _created);
    expect(materializer.batches.single.deterministicAlias, 'BTCPay');
    expect(
      keychainManifest.recordRequests.single.reservationId,
      intent.reservationId,
    );
    final requestMaterialization =
        keychainManifest.recordRequests.single.materializations.single;
    expect(requestMaterialization.walletId, intent.walletId);
  });

  test('preserves materializer failures without recording metadata', () async {
    final intent = _intent();
    materializer.result = KeychainRecoveryWalletMaterializationResult(
      materializedWallets: const [],
      failedOutcomes: [
        KeychainRecoveryWalletRestoreOutcome(
          intent: _recoveryIntent(intent),
          status: KeychainRecoveryWalletRestoreStatus.skippedUnsupported,
        ),
      ],
    );

    final result = await usecase.execute(_plan(intent));

    expect(result.hasFailures, true);
    expect(result.walletOutcomes.single.status, _skipped);
    expect(keychainManifest.recordRequests, isEmpty);
  });

  test('reports manifest record failures per materialized wallet', () async {
    final intent = _intent();
    final liquidIntent = _intent(
      walletId: 'lbtc-wallet',
      network: Network.liquidMainnet,
      walletPurpose: 'liquid',
    );
    var rollbackCalls = 0;
    keychainManifest.recordError = KeychainManifestFileParseException(
      reason: KeychainManifestFileParseFailureReason.invalidMetadata,
    );
    materializer.result = KeychainRecoveryWalletMaterializationResult(
      materializedWallets: [
        KeychainRecoveryMaterializedWallet(
          intent: _recoveryIntent(intent),
          walletId: intent.walletId,
          network: intent.network,
          scriptType: intent.scriptType,
          childSeedFingerprint: intent.childSeedFingerprint,
          created: true,
        ),
        KeychainRecoveryMaterializedWallet(
          intent: _recoveryIntent(liquidIntent),
          walletId: liquidIntent.walletId,
          network: Network.liquidMainnet,
          scriptType: liquidIntent.scriptType,
          childSeedFingerprint: liquidIntent.childSeedFingerprint,
          created: true,
        ),
      ],
      failedOutcomes: const [],
      rollbackCreatedWallets: () async {
        rollbackCalls++;
      },
    );

    final result = await usecase.execute(_plan(intent, liquidIntent));

    expect(result.hasFailures, true);
    expect(result.walletOutcomes.map((outcome) => outcome.status), [
      _recordFailed,
      _recordFailed,
    ]);
    expect(rollbackCalls, 1);
  });

  test(
    'reports existing wallets as already present after manifest recording',
    () async {
      final intent = _intent();
      materializer.result = KeychainRecoveryWalletMaterializationResult(
        materializedWallets: [
          KeychainRecoveryMaterializedWallet(
            intent: _recoveryIntent(intent),
            walletId: intent.walletId,
            network: intent.network,
            scriptType: intent.scriptType,
            childSeedFingerprint: intent.childSeedFingerprint,
            created: false,
          ),
        ],
        failedOutcomes: const [],
      );

      final result = await usecase.execute(_plan(intent));

      expect(result.hasFailures, false);
      expect(result.walletOutcomes.single.status, _alreadyPresent);
    },
  );

  test(
    'reports existing Lightning Address wallet as requiring reactivation',
    () async {
      final plan = _unsupportedPlan(
        reservationId: 'lightning_address_wallet_seed',
        path: "39'/0'/12'/101'",
        ownerFeature: 'lightningAddress',
        bip85Application: 39,
        bip85Index: 101,
        walletId: 'lightning-address-wallet',
      );
      final intent = plan.walletMaterializations.single;
      materializer.result = KeychainRecoveryWalletMaterializationResult(
        materializedWallets: [
          KeychainRecoveryMaterializedWallet(
            intent: _recoveryIntent(intent),
            walletId: intent.walletId,
            network: Network.liquidMainnet,
            scriptType: intent.scriptType,
            childSeedFingerprint: intent.childSeedFingerprint,
            created: false,
          ),
        ],
        failedOutcomes: const [],
      );

      final result = await usecase.execute(plan);

      expect(result.hasFailures, false);
      expect(result.hasProductReactivationRequired, true);
      expect(result.productReactivationRequiredOutcomes, hasLength(1));
      expect(result.walletOutcomes.single.status, _requiresReactivation);
    },
  );

  test('rejects forged import plans before wallet materialization', () async {
    final intent = _intent();
    final forgedIntent = KeychainManifestWalletMaterializationIntent(
      entryId: intent.entryId,
      reservationId: intent.reservationId,
      bip85DerivationPath: intent.bip85DerivationPath,
      walletId: intent.walletId,
      childSeedFingerprint: intent.childSeedFingerprint,
      network: intent.network,
      walletPurpose: intent.walletPurpose,
      scriptType: intent.scriptType,
    );
    final forgedPlan = KeychainManifestImportPlan(
      parentFingerprint: 'fedcba98',
      entries: [
        KeychainManifestImportEntryIntent(
          entryId: "fedcba98:39'/0'/12'/101'",
          parentFingerprint: 'fedcba98',
          bip85DerivationPath: "39'/0'/12'/100'",
          reservationId: 'btcpay_wallet_seed',
          entryType: 'walletSeed',
          ownerFeature: 'lightningAddress',
          bip85Application: 39,
          bip85Index: 100,
          walletMaterializations: [forgedIntent],
        ),
      ],
    );

    final result = await usecase.execute(forgedPlan);

    expect(result.hasFailures, true);
    expect(result.walletOutcomes.single.status, _invalidImportPlan);
    expect(materializer.batches, isEmpty);
    expect(keychainManifest.recordRequests, isEmpty);
  });

  test(
    'rejects non-wallet reservations before wallet materialization',
    () async {
      final intent = KeychainManifestWalletMaterializationIntent(
        entryId: "fedcba98:9000'/1'/1'",
        reservationId: 'nostr_wallet_manifest_key',
        bip85DerivationPath: "9000'/1'/1'",
        walletId: 'nostr-wallet',
        childSeedFingerprint: '0123abcd',
        network: Network.liquidMainnet,
        walletPurpose: 'liquid',
        scriptType: ScriptType.bip84,
      );
      final plan = KeychainManifestImportPlan(
        parentFingerprint: 'fedcba98',
        entries: [
          KeychainManifestImportEntryIntent(
            entryId: "fedcba98:9000'/1'/1'",
            parentFingerprint: 'fedcba98',
            bip85DerivationPath: "9000'/1'/1'",
            reservationId: 'nostr_wallet_manifest_key',
            entryType: 'nonWalletNostrKey',
            ownerFeature: 'nostr',
            bip85Application: 9000,
            bip85Index: 1,
            walletMaterializations: [intent],
          ),
        ],
      );

      final result = await usecase.execute(plan);

      expect(result.hasFailures, true);
      expect(result.walletOutcomes.single.status, _invalidImportPlan);
      expect(materializer.batches, isEmpty);
      expect(keychainManifest.recordRequests, isEmpty);
    },
  );

  test(
    'restores Lightning Address plans after wallet materialization',
    () async {
      final plan = _unsupportedPlan(
        reservationId: 'lightning_address_wallet_seed',
        path: "39'/0'/12'/101'",
        ownerFeature: 'lightningAddress',
        bip85Application: 39,
        bip85Index: 101,
        walletId: 'lightning-address-wallet',
      );
      final intent = plan.walletMaterializations.single;
      materializer.result = KeychainRecoveryWalletMaterializationResult(
        materializedWallets: [
          KeychainRecoveryMaterializedWallet(
            intent: _recoveryIntent(intent),
            walletId: intent.walletId,
            network: Network.liquidMainnet,
            scriptType: intent.scriptType,
            childSeedFingerprint: intent.childSeedFingerprint,
            created: true,
          ),
        ],
        failedOutcomes: const [],
      );

      final result = await usecase.execute(plan);

      expect(result.hasFailures, false);
      expect(result.walletOutcomes.single.status, _requiresReactivation);
      expect(
        materializer.batches.single.reservationId,
        'lightning_address_wallet_seed',
      );
      expect(materializer.batches.single.bip85Index, 101);
      expect(
        materializer.batches.single.deterministicAlias,
        'Lightning Address',
      );
      expect(
        keychainManifest.recordRequests.single.reservationId,
        'lightning_address_wallet_seed',
      );
    },
  );

  test(
    'rejects Lightning Address recovery plans for Bitcoin wallets',
    () async {
      final result = await usecase.execute(
        _unsupportedPlan(
          reservationId: 'lightning_address_wallet_seed',
          path: "39'/0'/12'/101'",
          ownerFeature: 'lightningAddress',
          bip85Index: 101,
          walletId: 'lightning-address-wallet',
          network: Network.bitcoinMainnet,
        ),
      );

      expect(result.hasFailures, true);
      expect(result.walletOutcomes.single.status, _invalidImportPlan);
      expect(materializer.batches, isEmpty);
      expect(keychainManifest.recordRequests, isEmpty);
    },
  );

  test(
    'rejects Lightning Address recovery plans with the wrong purpose',
    () async {
      final result = await usecase.execute(
        _unsupportedPlan(
          reservationId: 'lightning_address_wallet_seed',
          path: "39'/0'/12'/101'",
          ownerFeature: 'lightningAddress',
          bip85Application: 39,
          bip85Index: 101,
          walletId: 'lightning-address-wallet',
          walletPurpose: 'bitcoin',
        ),
      );

      expect(result.hasFailures, true);
      expect(result.walletOutcomes.single.status, _invalidImportPlan);
      expect(materializer.batches, isEmpty);
      expect(keychainManifest.recordRequests, isEmpty);
    },
  );

  test(
    'rejects Lightning Address recovery plans with the wrong script type',
    () async {
      final result = await usecase.execute(
        _unsupportedPlan(
          reservationId: 'lightning_address_wallet_seed',
          path: "39'/0'/12'/101'",
          ownerFeature: 'lightningAddress',
          bip85Application: 39,
          bip85Index: 101,
          walletId: 'lightning-address-wallet',
          scriptType: ScriptType.bip49,
        ),
      );

      expect(result.hasFailures, true);
      expect(result.walletOutcomes.single.status, _invalidImportPlan);
      expect(materializer.batches, isEmpty);
      expect(keychainManifest.recordRequests, isEmpty);
    },
  );

  test('rejects multiple Lightning Address recovery wallets', () async {
    final result = await usecase.execute(
      _unsupportedPlan(
        reservationId: 'lightning_address_wallet_seed',
        path: "39'/0'/12'/101'",
        ownerFeature: 'lightningAddress',
        bip85Application: 39,
        bip85Index: 101,
        walletId: 'lightning-address-wallet',
        extraWalletIds: ['second-lightning-address-wallet'],
      ),
    );

    expect(result.hasFailures, true);
    expect(result.walletOutcomes.map((outcome) => outcome.status), [
      _invalidImportPlan,
      _invalidImportPlan,
    ]);
    expect(materializer.batches, isEmpty);
    expect(keychainManifest.recordRequests, isEmpty);
  });

  test('rejects Payment Page plans before wallet materialization', () async {
    final result = await usecase.execute(
      _unsupportedPlan(
        reservationId: 'payment_page_wallet_seed',
        path: "39'/0'/12'/102'",
        ownerFeature: 'paymentPage',
        bip85Index: 102,
        walletId: 'payment-page-wallet',
      ),
    );

    expect(result.hasFailures, true);
    expect(result.walletOutcomes.single.status, _invalidImportPlan);
    expect(materializer.batches, isEmpty);
    expect(keychainManifest.recordRequests, isEmpty);
  });
}

KeychainManifestImportPlan _plan(
  KeychainManifestWalletMaterializationIntent intent, [
  KeychainManifestWalletMaterializationIntent? secondIntent,
]) {
  return KeychainManifestImportPlan(
    parentFingerprint: 'fedcba98',
    entries: [
      KeychainManifestImportEntryIntent(
        entryId: "fedcba98:39'/0'/12'/100'",
        parentFingerprint: 'fedcba98',
        bip85DerivationPath: "39'/0'/12'/100'",
        reservationId: 'btcpay_wallet_seed',
        entryType: 'walletSeed',
        ownerFeature: 'btcpay',
        bip85Application: 39,
        bip85Index: 100,
        walletMaterializations: [intent, ?secondIntent],
      ),
    ],
  );
}

KeychainManifestWalletMaterializationIntent _intent({
  String walletId = 'btc-wallet',
  Network network = Network.bitcoinMainnet,
  String walletPurpose = 'bitcoin',
}) {
  return KeychainManifestWalletMaterializationIntent(
    entryId: "fedcba98:39'/0'/12'/100'",
    reservationId: 'btcpay_wallet_seed',
    bip85DerivationPath: "39'/0'/12'/100'",
    walletId: walletId,
    childSeedFingerprint: '0123abcd',
    network: network,
    walletPurpose: walletPurpose,
    scriptType: ScriptType.bip84,
  );
}

KeychainManifestImportPlan _unsupportedPlan({
  required String reservationId,
  required String path,
  required String ownerFeature,
  int bip85Application = 39,
  required int bip85Index,
  required String walletId,
  Network network = Network.liquidMainnet,
  String walletPurpose = 'liquid',
  ScriptType scriptType = ScriptType.bip84,
  List<String> extraWalletIds = const [],
}) {
  final entryId = 'fedcba98:$path';
  final intent = KeychainManifestWalletMaterializationIntent(
    entryId: entryId,
    reservationId: reservationId,
    bip85DerivationPath: path,
    walletId: walletId,
    childSeedFingerprint: '0123abcd',
    network: network,
    walletPurpose: walletPurpose,
    scriptType: scriptType,
  );
  final extraIntents = extraWalletIds
      .map(
        (extraWalletId) => KeychainManifestWalletMaterializationIntent(
          entryId: entryId,
          reservationId: reservationId,
          bip85DerivationPath: path,
          walletId: extraWalletId,
          childSeedFingerprint: '0123abcd',
          network: network,
          walletPurpose: walletPurpose,
          scriptType: scriptType,
        ),
      )
      .toList(growable: false);
  return KeychainManifestImportPlan(
    parentFingerprint: 'fedcba98',
    entries: [
      KeychainManifestImportEntryIntent(
        entryId: entryId,
        parentFingerprint: 'fedcba98',
        bip85DerivationPath: path,
        reservationId: reservationId,
        entryType: 'walletSeed',
        ownerFeature: ownerFeature,
        bip85Application: bip85Application,
        bip85Index: bip85Index,
        walletMaterializations: [intent, ...extraIntents],
      ),
    ],
  );
}

KeychainRecoveryWalletIntent _recoveryIntent(
  KeychainManifestWalletMaterializationIntent intent,
) {
  return KeychainRecoveryWalletIntent(
    entryId: intent.entryId,
    reservationId: intent.reservationId,
    bip85DerivationPath: intent.bip85DerivationPath,
    walletId: intent.walletId,
    childSeedFingerprint: intent.childSeedFingerprint,
    network: intent.network,
    walletPurpose: intent.walletPurpose,
    scriptType: intent.scriptType,
  );
}

class _FakeWalletMaterializer
    implements KeychainRecoveryWalletMaterializerPort {
  final batches = <KeychainRecoveryWalletMaterializationBatch>[];
  late KeychainRecoveryWalletMaterializationResult result;

  @override
  Future<KeychainRecoveryWalletMaterializationResult> materialize(
    KeychainRecoveryWalletMaterializationBatch batch,
  ) async {
    batches.add(batch);
    return result;
  }
}

class _FakeKeychainManifestFacade implements KeychainManifestFacade {
  final recordRequests = <KeychainManifestReservedDerivationRequest>[];
  KeychainManifestException? recordError;

  @override
  Future<void> recordReservedDerivation(
    KeychainManifestReservedDerivationRequest request, {
    DateTime? now,
  }) async {
    final error = recordError;
    if (error != null) throw error;
    recordRequests.add(request);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _created = KeychainRecoveryWalletRestoreStatus.created;
const _alreadyPresent = KeychainRecoveryWalletRestoreStatus.alreadyPresent;
const _requiresReactivation =
    KeychainRecoveryWalletRestoreStatus.requiresProductReactivation;
const _skipped = KeychainRecoveryWalletRestoreStatus.skippedUnsupported;
const _invalidImportPlan =
    KeychainRecoveryWalletRestoreStatus.failedInvalidImportPlan;
const _recordFailed = KeychainRecoveryWalletRestoreStatus.failedManifestRecord;
