import 'dart:typed_data';

import 'package:bb_mobile/core/bip85/data/bip85_repository.dart';
import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/external_receive_wallets/external_receive_wallet_purpose.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/delete_created_external_receive_wallet_usecase.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/get_external_receive_wallet_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/public/wallet_manifest.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockGetWallet extends Mock implements GetExternalReceiveWalletUsecase {}

class _MockWalletRepository extends Mock implements WalletRepository {}

class _MockSeedRepository extends Mock implements SeedRepository {}

class _MockBip85Repository extends Mock implements Bip85Repository {}

class _MockWalletManifestFacade extends Mock implements WalletManifestFacade {}

void main() {
  setUpAll(() {
    registerFallbackValue(Environment.mainnet);
    registerFallbackValue(ExternalReceiveWalletPurpose.btcpay);
    registerFallbackValue(
      ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(isTestnet: false),
    );
  });

  late _MockGetWallet getWallet;
  late _MockWalletRepository walletRepository;
  late _MockSeedRepository seedRepository;
  late _MockBip85Repository bip85Repository;
  late _MockWalletManifestFacade walletManifest;
  late DeleteCreatedExternalReceiveWalletUsecase usecase;

  setUp(() {
    getWallet = _MockGetWallet();
    walletRepository = _MockWalletRepository();
    seedRepository = _MockSeedRepository();
    bip85Repository = _MockBip85Repository();
    walletManifest = _MockWalletManifestFacade();
    usecase = DeleteCreatedExternalReceiveWalletUsecase(
      getWallet: getWallet,
      walletRepository: walletRepository,
      seedRepository: seedRepository,
      bip85Repository: bip85Repository,
      walletManifest: walletManifest,
    );

    when(
      () => getWallet.execute(
        environment: any(named: 'environment'),
        purpose: any(named: 'purpose'),
        accountKey: any(named: 'accountKey'),
      ),
    ).thenAnswer((_) async => _wallet('BTCPay-BTC', Network.bitcoinMainnet));
    when(
      () => walletRepository.deleteWallet(walletId: any(named: 'walletId')),
    ).thenAnswer((_) async {});
    when(
      () => walletManifest.deleteOrigin(walletId: any(named: 'walletId')),
    ).thenAnswer((_) async {});
    when(
      () => walletRepository.getWallets(
        environment: any(named: 'environment'),
        onlyDefaults: any(named: 'onlyDefaults'),
        onlyBitcoin: any(named: 'onlyBitcoin'),
      ),
    ).thenAnswer(
      (_) async => [
        _wallet('default-btc', Network.bitcoinMainnet, isDefault: true),
      ],
    );
    when(() => seedRepository.get(any())).thenAnswer((_) async => _seed());
    when(
      () => bip85Repository.deleteMnemonicDerivation(
        xprvBase58: any(named: 'xprvBase58'),
        derivationPath: any(named: 'derivationPath'),
      ),
    ).thenAnswer((_) async {});
  });

  test('keeps shared path derivation when a sibling origin remains', () async {
    when(() => walletManifest.fetchOrigins()).thenAnswer(
      (_) async => [
        WalletManifestOrigin(
          walletId: 'BTCPay-LBTC',
          rootFingerprint: '73c5da0a',
          bip85DerivationPath: Bip85DerivationPath.mnemonic12(index: 77),
          network: WalletManifestNetwork.liquid,
          createdAt: 1,
          updatedAt: 1,
        ),
      ],
    );

    await usecase.execute(
      environment: Environment.mainnet,
      purpose: ExternalReceiveWalletPurpose.btcpay,
      accountKey: ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(
        isTestnet: false,
      ),
      expectedWalletId: 'BTCPay-BTC',
    );

    verify(
      () => walletRepository.deleteWallet(walletId: 'BTCPay-BTC'),
    ).called(1);
    verifyNever(
      () => bip85Repository.deleteMnemonicDerivation(
        xprvBase58: any(named: 'xprvBase58'),
        derivationPath: any(named: 'derivationPath'),
      ),
    );
  });

  test('deletes path derivation when no sibling origin remains', () async {
    when(() => walletManifest.fetchOrigins()).thenAnswer((_) async => const []);

    await usecase.execute(
      environment: Environment.mainnet,
      purpose: ExternalReceiveWalletPurpose.btcpay,
      accountKey: ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(
        isTestnet: false,
      ),
      expectedWalletId: 'BTCPay-BTC',
    );

    verify(
      () => bip85Repository.deleteMnemonicDerivation(
        xprvBase58: any(named: 'xprvBase58'),
        derivationPath: "m/83696968'/39'/0'/12'/77'",
      ),
    ).called(1);
  });
}

Wallet _wallet(String id, Network network, {bool isDefault = false}) {
  return Wallet(
    origin: id,
    label: id,
    network: network,
    isDefault: isDefault,
    masterFingerprint: '73c5da0a',
    xpubFingerprint: '73c5da0a',
    scriptType: ScriptType.bip84,
    xpub: 'xpub',
    externalPublicDescriptor: 'wpkh(xpub/0/*)',
    internalPublicDescriptor: 'wpkh(xpub/1/*)',
    signer: SignerEntity.local,
    signerDevice: null,
    balanceSat: BigInt.zero,
  );
}

MnemonicSeed _seed() {
  final mnemonic = bip39.Mnemonic.fromSentence(
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
    bip39.Language.english,
  );
  return Seed.mnemonic(
        mnemonicWords: mnemonic.words,
        bytes: Uint8List.fromList(mnemonic.seed),
        masterFingerprint: '73c5da0a',
      )
      as MnemonicSeed;
}
