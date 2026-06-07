import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/deterministic_wallets/public/deterministic_wallets_facade.dart';
import 'package:bb_mobile/features/keychain_recovery/application/ports/keychain_recovery_wallet_materializer_port.dart';
import 'package:bb_mobile/features/keychain_recovery/domain/keychain_recovery_result.dart';
import 'package:bb_mobile/features/keychain_recovery/frameworks/deterministic_wallet_recovery_materializer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeDeterministicWalletsFacade deterministicWallets;
  late _FakeGetSettingsUsecase getSettings;
  late DeterministicWalletRecoveryMaterializer materializer;

  setUp(() {
    deterministicWallets = _FakeDeterministicWalletsFacade();
    getSettings = _FakeGetSettingsUsecase(Environment.mainnet);
    materializer = DeterministicWalletRecoveryMaterializer(
      deterministicWallets: deterministicWallets,
      getSettings: getSettings,
    );
  });

  test(
    'uses reservation alias and skips unsupported networks per wallet',
    () async {
      final supported = _intent(walletId: 'btc-wallet');
      final unsupported = _intent(
        walletId: 'testnet-wallet',
        network: Network.bitcoinTestnet,
      );
      deterministicWallets.result = _prepared(
        childSeedFingerprint: '0123abcd',
        wallets: [
          PreparedDeterministicWallet(
            specId: supported.materializationKey,
            wallet: _wallet(supported.walletId),
            created: true,
          ),
        ],
      );

      final result = await materializer.materialize(
        _batch(intents: [supported, unsupported]),
      );

      expect(deterministicWallets.requests.single.bip85Alias, 'BTCPay');
      expect(deterministicWallets.requests.single.walletSpecs, hasLength(1));
      expect(result.materializedWallets.single.intent.walletId, 'btc-wallet');
      expect(result.failedOutcomes.single.intent.walletId, 'testnet-wallet');
      expect(result.failedOutcomes.single.status, _skipped);
    },
  );

  test(
    'rolls back and fails supported batch on child fingerprint mismatch',
    () async {
      final intent = _intent();
      deterministicWallets.result = _prepared(
        childSeedFingerprint: 'deadbeef',
        wallets: [
          PreparedDeterministicWallet(
            specId: intent.materializationKey,
            wallet: _wallet(intent.walletId),
            created: true,
          ),
        ],
      );

      final result = await materializer.materialize(_batch(intents: [intent]));

      expect(result.materializedWallets, isEmpty);
      expect(result.failedOutcomes.single.status, _childFingerprintMismatch);
      expect(deterministicWallets.rollbackCalls, 1);
    },
  );
}

KeychainRecoveryWalletMaterializationBatch _batch({
  required List<KeychainRecoveryWalletIntent> intents,
}) {
  return KeychainRecoveryWalletMaterializationBatch(
    parentFingerprint: 'fedcba98',
    reservationId: 'btcpay_wallet_seed',
    bip85Index: 100,
    deterministicAlias: 'BTCPay',
    intents: intents,
  );
}

KeychainRecoveryWalletIntent _intent({
  String walletId = 'btc-wallet',
  Network network = Network.bitcoinMainnet,
}) {
  return KeychainRecoveryWalletIntent(
    entryId: "fedcba98:39'/0'/12'/100'",
    reservationId: 'btcpay_wallet_seed',
    bip85DerivationPath: "39'/0'/12'/100'",
    walletId: walletId,
    childSeedFingerprint: '0123abcd',
    network: network,
    walletPurpose: 'bitcoin',
    scriptType: ScriptType.bip84,
  );
}

PreparedDeterministicWallets _prepared({
  required String childSeedFingerprint,
  required List<PreparedDeterministicWallet> wallets,
}) {
  return PreparedDeterministicWallets(
    wallets: wallets,
    parentFingerprint: 'fedcba98',
    childSeedFingerprint: childSeedFingerprint,
    childSeedStoredDuringAttempt: true,
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

class _FakeDeterministicWalletsFacade implements DeterministicWalletsFacade {
  final requests = <DeterministicWalletsRequest>[];
  late PreparedDeterministicWallets result;
  int rollbackCalls = 0;

  @override
  Future<PreparedDeterministicWallets> prepare(
    DeterministicWalletsRequest request,
  ) async {
    requests.add(request);
    return result;
  }

  @override
  Future<void> rollbackCreatedWallets(
    PreparedDeterministicWallets result,
  ) async {
    rollbackCalls++;
  }
}

class _FakeGetSettingsUsecase implements GetSettingsUsecase {
  final Environment environment;

  const _FakeGetSettingsUsecase(this.environment);

  @override
  Future<SettingsEntity> execute() async {
    return SettingsEntity(
      environment: environment,
      bitcoinUnit: BitcoinUnit.sats,
      currencyCode: 'USD',
    );
  }
}

const _skipped = KeychainRecoveryWalletRestoreStatus.skippedUnsupported;
const _childFingerprintMismatch =
    KeychainRecoveryWalletRestoreStatus.failedChildSeedFingerprintMismatch;
