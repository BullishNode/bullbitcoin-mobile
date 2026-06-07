import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/keychain_recovery/application/ports/keychain_recovery_wallet_materializer_port.dart';
import 'package:bb_mobile/features/keychain_recovery/application/restore_keychain_manifest_wallets_usecase.dart';
import 'package:bb_mobile/features/keychain_recovery/domain/keychain_recovery_result.dart';
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
          wallet: _wallet(intent.walletId),
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
        keychainManifest.recordRequests.single.materializations.single
            as KeychainManifestWalletMaterializationRequest;
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
          walletId: intent.walletId,
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
    keychainManifest.recordError = const KeychainManifestException('failed');
    var rollbackCalled = false;
    materializer.result = KeychainRecoveryWalletMaterializationResult(
      materializedWallets: [
        KeychainRecoveryMaterializedWallet(
          intent: _recoveryIntent(intent),
          wallet: _wallet(intent.walletId),
          childSeedFingerprint: intent.childSeedFingerprint,
          created: true,
        ),
      ],
      failedOutcomes: const [],
      rollbackCreatedWallets: () async {
        rollbackCalled = true;
      },
    );

    final result = await usecase.execute(_plan(intent));

    expect(result.hasFailures, true);
    expect(result.walletOutcomes.single.status, _recordFailed);
    expect(rollbackCalled, true);
  });

  test(
    'reports metadata repair for existing wallets with new manifest records',
    () async {
      final intent = _intent();
      keychainManifest.recordResult =
          const KeychainManifestRecordReservedDerivationResult.forTesting(
            insertedMaterializations: [
              KeychainManifestRecordedMaterialization.walletForTesting(
                entryId: "fedcba98:39'/0'/12'/100'",
                walletId: 'btc-wallet',
              ),
            ],
          );
      materializer.result = KeychainRecoveryWalletMaterializationResult(
        materializedWallets: [
          KeychainRecoveryMaterializedWallet(
            intent: _recoveryIntent(intent),
            wallet: _wallet(intent.walletId),
            childSeedFingerprint: intent.childSeedFingerprint,
            created: false,
          ),
        ],
        failedOutcomes: const [],
      );

      final result = await usecase.execute(_plan(intent));

      expect(result.hasFailures, false);
      expect(result.walletOutcomes.single.status, _metadataRepaired);
    },
  );
}

KeychainManifestImportPlan _plan(
  KeychainManifestWalletMaterializationIntent intent,
) {
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
        walletMaterializations: [intent],
      ),
    ],
  );
}

KeychainManifestWalletMaterializationIntent _intent() {
  return KeychainManifestWalletMaterializationIntent(
    entryId: "fedcba98:39'/0'/12'/100'",
    reservationId: 'btcpay_wallet_seed',
    bip85DerivationPath: "39'/0'/12'/100'",
    walletId: 'btc-wallet',
    childSeedFingerprint: '0123abcd',
    network: Network.bitcoinMainnet,
    walletPurpose: 'bitcoin',
    scriptType: ScriptType.bip84,
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

Wallet _wallet(String id) {
  return Wallet(
    origin: id,
    network: Network.bitcoinMainnet,
    masterFingerprint: '0123abcd',
    xpubFingerprint: '0123abcd',
    scriptType: ScriptType.bip84,
    xpub: 'xpub',
    externalPublicDescriptor: 'external',
    internalPublicDescriptor: 'internal',
    signer: SignerEntity.local,
    signerDevice: null,
    balanceSat: BigInt.zero,
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
  KeychainManifestRecordReservedDerivationResult recordResult =
      const KeychainManifestRecordReservedDerivationResult.forTesting(
        insertedMaterializations: [],
      );

  @override
  Future<KeychainManifestRecordReservedDerivationResult>
  recordReservedDerivation(
    KeychainManifestReservedDerivationRequest request, {
    DateTime? now,
  }) async {
    final error = recordError;
    if (error != null) throw error;
    recordRequests.add(request);
    return recordResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _created = KeychainRecoveryWalletRestoreStatus.created;
const _metadataRepaired = KeychainRecoveryWalletRestoreStatus.metadataRepaired;
const _skipped = KeychainRecoveryWalletRestoreStatus.skippedUnsupported;
const _recordFailed = KeychainRecoveryWalletRestoreStatus.failedManifestRecord;
