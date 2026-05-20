import 'dart:typed_data';

import 'package:bb_mobile/core/bip85/data/bip85_repository.dart';
import 'package:bb_mobile/core/bip85/domain/bip85_derivation_entity.dart';
import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/external_receive_wallets/external_receive_wallet_purpose.dart';
import 'package:bb_mobile/features/external_receive_wallets/external_receive_wallet_errors.dart';
import 'package:bb_mobile/features/external_receive_wallets/external_receive_wallet_restore_outcome.dart';
import 'package:bb_mobile/features/external_receive_wallets/reserved_external_receive_wallet_labels.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/create_external_receive_wallet_usecase.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/get_external_receive_wallet_usecase.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/restore_reserved_external_receive_wallets_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/public/wallet_manifest.dart';
import 'package:bip32_keys/bip32_keys.dart' as bip32;
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:convert/convert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBip85Repository extends Mock implements Bip85Repository {}

class _MockWalletRepository extends Mock implements WalletRepository {}

class _MockSeedRepository extends Mock implements SeedRepository {}

class _MockGetWallet extends Mock implements GetExternalReceiveWalletUsecase {}

class _MockCreateExternalReceiveWalletUsecase extends Mock
    implements CreateExternalReceiveWalletUsecase {}

class _MockWalletManifestFacade extends Mock implements WalletManifestFacade {}

const _kZeroMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const _kChildMnemonic =
    'legal winner thank year wave sausage worth useful legal winner thank yellow';
const _kFingerprint = '73c5da0a';

Wallet _bitcoinDefault({Network network = Network.bitcoinMainnet}) => Wallet(
  origin: 'btc-default',
  network: network,
  isDefault: true,
  masterFingerprint: _kFingerprint,
  xpubFingerprint: _kFingerprint,
  scriptType: ScriptType.bip84,
  xpub: 'xpubFAKE',
  externalPublicDescriptor: 'wpkh(xpubFAKE/0/*)',
  internalPublicDescriptor: 'wpkh(xpubFAKE/1/*)',
  signer: SignerEntity.local,
  signerDevice: null,
  balanceSat: BigInt.zero,
);

Wallet _externalWallet(
  String label, {
  Network network = Network.liquidMainnet,
}) => Wallet(
  origin: label,
  network: network,
  isDefault: false,
  masterFingerprint: 'aabbccdd',
  xpubFingerprint: 'aabbccdd',
  scriptType: ScriptType.bip84,
  xpub: 'xpubLiquid',
  externalPublicDescriptor: 'ct(slip77(...),elwpkh(xpubLiquid/0/*))',
  internalPublicDescriptor: 'ct(slip77(...),elwpkh(xpubLiquid/1/*))',
  signer: SignerEntity.local,
  signerDevice: null,
  balanceSat: BigInt.zero,
  label: label,
);

Wallet _liquidWallet(String label) => _externalWallet(label);

MnemonicSeed _seedFromMnemonic(String sentence) {
  final mnemonic = bip39.Mnemonic.fromSentence(
    sentence,
    bip39.Language.english,
  );
  return Seed.mnemonic(
        mnemonicWords: sentence.split(' '),
        bytes: Uint8List.fromList(mnemonic.seed),
        masterFingerprint: _kFingerprint,
      )
      as MnemonicSeed;
}

bip39.Mnemonic _mnemonic(String sentence) =>
    bip39.Mnemonic.fromSentence(sentence, bip39.Language.english);

String _fingerprintForMnemonic(String sentence) {
  final mnemonic = _mnemonic(sentence);
  return hex.encode(
    bip32.Bip32Keys.fromSeed(Uint8List.fromList(mnemonic.seed)).fingerprint,
  );
}

WalletManifestOrigin _origin({
  required String walletId,
  required int bip85Index,
  required WalletManifestNetwork network,
}) => WalletManifestOrigin(
  walletId: walletId,
  rootFingerprint: _kFingerprint,
  bip85DerivationPath: Bip85DerivationPath.mnemonic12(index: bip85Index),
  network: network,
  createdAt: 100,
  updatedAt: 100,
);

void main() {
  setUpAll(() {
    registerFallbackValue(Environment.mainnet);
    registerFallbackValue(ExternalReceiveWalletPurpose.lightningAddress);
    registerFallbackValue(
      ExternalReceiveWalletPurpose.lightningAddress.liquidAccountKey(
        isTestnet: false,
      ),
    );
    registerFallbackValue(_seedFromMnemonic(_kZeroMnemonic));
    registerFallbackValue(Network.liquidMainnet);
    registerFallbackValue(ScriptType.bip84);
    registerFallbackValue(bip39.MnemonicLength.words12);
    registerFallbackValue(Bip85Usage.system);
    registerFallbackValue(_mnemonic(_kChildMnemonic));
    registerFallbackValue(_liquidWallet('fallback'));
    registerFallbackValue(WalletManifestNetwork.liquid);
  });

  group('GetExternalReceiveWalletUsecase', () {
    late _MockWalletRepository walletRepository;
    late _MockWalletManifestFacade walletManifest;
    late GetExternalReceiveWalletUsecase usecase;

    setUp(() {
      walletRepository = _MockWalletRepository();
      walletManifest = _MockWalletManifestFacade();
      usecase = GetExternalReceiveWalletUsecase(
        walletRepository: walletRepository,
        walletManifest: walletManifest,
      );
      when(
        () => walletRepository.getWallets(
          environment: any(named: 'environment'),
          onlyDefaults: any(named: 'onlyDefaults'),
          onlyBitcoin: any(named: 'onlyBitcoin'),
        ),
      ).thenAnswer((invocation) async {
        final onlyDefaults = invocation.namedArguments[#onlyDefaults] as bool?;
        final onlyBitcoin = invocation.namedArguments[#onlyBitcoin] as bool?;
        if (onlyDefaults == true && onlyBitcoin == true) {
          return [_bitcoinDefault()];
        }
        return [
          _liquidWallet(ReservedExternalReceiveWalletLabel.paymentPageLiquid),
          _liquidWallet(
            ReservedExternalReceiveWalletLabel.lightningAddressLiquid,
          ),
          _liquidWallet(ReservedExternalReceiveWalletLabel.btcpayLiquid),
          _externalWallet(
            ReservedExternalReceiveWalletLabel.btcpayBitcoin,
            network: Network.bitcoinMainnet,
          ),
        ];
      });
      when(() => walletManifest.fetchOrigins()).thenAnswer(
        (_) async => [
          _origin(
            walletId: ReservedExternalReceiveWalletLabel.paymentPageLiquid,
            bip85Index: ExternalReceiveWalletBip85Index.paymentPage,
            network: WalletManifestNetwork.liquid,
          ),
          _origin(
            walletId: ReservedExternalReceiveWalletLabel.lightningAddressLiquid,
            bip85Index: ExternalReceiveWalletBip85Index.lightningAddress,
            network: WalletManifestNetwork.liquid,
          ),
          _origin(
            walletId: ReservedExternalReceiveWalletLabel.btcpayLiquid,
            bip85Index: ExternalReceiveWalletBip85Index.btcpay,
            network: WalletManifestNetwork.liquid,
          ),
          _origin(
            walletId: ReservedExternalReceiveWalletLabel.btcpayBitcoin,
            bip85Index: ExternalReceiveWalletBip85Index.btcpay,
            network: WalletManifestNetwork.bitcoin,
          ),
        ],
      );
    });

    test('finds the Lightning Address receive wallet when requested', () async {
      final wallet = await usecase.execute(
        environment: Environment.mainnet,
        purpose: ExternalReceiveWalletPurpose.lightningAddress,
      );

      expect(
        wallet?.label,
        ReservedExternalReceiveWalletLabel.lightningAddressLiquid,
      );
      verify(
        () => walletRepository.getWallets(environment: Environment.mainnet),
      ).called(1);
      verify(() => walletManifest.fetchOrigins()).called(1);
    });

    test('finds the requested external receive wallet purpose', () async {
      final wallet = await usecase.execute(
        environment: Environment.mainnet,
        purpose: ExternalReceiveWalletPurpose.paymentPage,
      );

      expect(
        wallet?.label,
        ReservedExternalReceiveWalletLabel.paymentPageLiquid,
      );
    });

    test(
      'finds the manifest origin wallet even when its label changed',
      () async {
        when(
          () => walletRepository.getWallets(environment: Environment.mainnet),
        ).thenAnswer(
          (_) async => [
            _externalWallet(
              'Renamed by user',
              network: Network.liquidMainnet,
            ).copyWith(origin: 'payment-wallet-id'),
          ],
        );
        when(() => walletManifest.fetchOrigins()).thenAnswer(
          (_) async => [
            _origin(
              walletId: 'payment-wallet-id',
              bip85Index: ExternalReceiveWalletBip85Index.paymentPage,
              network: WalletManifestNetwork.liquid,
            ),
          ],
        );

        final wallet = await usecase.execute(
          environment: Environment.mainnet,
          purpose: ExternalReceiveWalletPurpose.paymentPage,
        );

        expect(wallet?.id, 'payment-wallet-id');
        expect(wallet?.label, 'Renamed by user');
      },
    );

    test(
      'does not find old unsuffixed labels as external receive wallets',
      () async {
        when(
          () => walletRepository.getWallets(environment: Environment.mainnet),
        ).thenAnswer(
          (_) async => [
            _externalWallet(
              'User renamed this wallet',
              network: Network.liquidMainnet,
            ),
          ],
        );
        when(() => walletManifest.fetchOrigins()).thenAnswer(
          (_) async => [
            _origin(
              walletId: 'other-wallet',
              bip85Index: ExternalReceiveWalletBip85Index.paymentPage,
              network: WalletManifestNetwork.liquid,
            ),
          ],
        );

        final wallet = await usecase.execute(
          environment: Environment.mainnet,
          purpose: ExternalReceiveWalletPurpose.paymentPage,
        );

        expect(wallet, isNull);
      },
    );

    test('finds the requested external receive wallet account key', () async {
      final wallet = await usecase.execute(
        environment: Environment.mainnet,
        purpose: ExternalReceiveWalletPurpose.btcpay,
        accountKey: ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(
          isTestnet: false,
        ),
      );

      expect(wallet?.label, ReservedExternalReceiveWalletLabel.btcpayBitcoin);
    });

    test('ignores origins from another root fingerprint', () async {
      when(() => walletManifest.fetchOrigins()).thenAnswer(
        (_) async => [
          WalletManifestOrigin(
            walletId: ReservedExternalReceiveWalletLabel.paymentPageLiquid,
            rootFingerprint: 'ffffffff',
            bip85DerivationPath: Bip85DerivationPath.mnemonic12(
              index: ExternalReceiveWalletBip85Index.paymentPage,
            ),
            network: WalletManifestNetwork.liquid,
            createdAt: 100,
            updatedAt: 100,
          ),
        ],
      );

      final wallet = await usecase.execute(
        environment: Environment.mainnet,
        purpose: ExternalReceiveWalletPurpose.paymentPage,
      );

      expect(wallet, isNull);
    });

    test('rejects account keys from the wrong environment', () async {
      await expectLater(
        usecase.execute(
          environment: Environment.testnet,
          purpose: ExternalReceiveWalletPurpose.btcpay,
          accountKey: ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(
            isTestnet: false,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('CreateExternalReceiveWalletUsecase', () {
    late _MockBip85Repository bip85Repository;
    late _MockWalletRepository walletRepository;
    late _MockSeedRepository seedRepository;
    late _MockGetWallet getWallet;
    late _MockWalletManifestFacade walletManifest;
    late CreateExternalReceiveWalletUsecase usecase;

    setUp(() {
      bip85Repository = _MockBip85Repository();
      walletRepository = _MockWalletRepository();
      seedRepository = _MockSeedRepository();
      getWallet = _MockGetWallet();
      walletManifest = _MockWalletManifestFacade();
      usecase = CreateExternalReceiveWalletUsecase(
        bip85Repository: bip85Repository,
        walletRepository: walletRepository,
        seedRepository: seedRepository,
        getWallet: getWallet,
        walletManifest: walletManifest,
      );

      when(
        () => getWallet.execute(
          environment: any(named: 'environment'),
          purpose: any(named: 'purpose'),
          accountKey: any(named: 'accountKey'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => walletRepository.getWallets(
          environment: any(named: 'environment'),
          onlyDefaults: any(named: 'onlyDefaults'),
          onlyBitcoin: any(named: 'onlyBitcoin'),
        ),
      ).thenAnswer((_) async => [_bitcoinDefault()]);
      when(
        () => seedRepository.get(any()),
      ).thenAnswer((_) async => _seedFromMnemonic(_kZeroMnemonic));
      when(
        () => bip85Repository.deriveMnemonicPreview(
          xprvBase58: any(named: 'xprvBase58'),
          length: any(named: 'length'),
          index: any(named: 'index'),
        ),
      ).thenAnswer((invocation) async {
        final index = invocation.namedArguments[#index] as int;
        return (
          derivation: "39'/0'/12'/$index'",
          mnemonic: _mnemonic(_kChildMnemonic),
        );
      });
      when(
        () => bip85Repository.recordMnemonicDerivation(
          xprvBase58: any(named: 'xprvBase58'),
          derivationPath: any(named: 'derivationPath'),
          alias: any(named: 'alias'),
          usage: any(named: 'usage'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => bip85Repository.deleteMnemonicDerivation(
          xprvBase58: any(named: 'xprvBase58'),
          derivationPath: any(named: 'derivationPath'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => seedRepository.createFromMnemonic(
          mnemonicWords: any(named: 'mnemonicWords'),
        ),
      ).thenAnswer((_) async => _seedFromMnemonic(_kChildMnemonic));
      when(
        () => walletRepository.createWallet(
          seed: any(named: 'seed'),
          network: any(named: 'network'),
          scriptType: any(named: 'scriptType'),
          label: any(named: 'label'),
        ),
      ).thenAnswer(
        (invocation) async => _externalWallet(
          invocation.namedArguments[#label] as String,
          network: invocation.namedArguments[#network] as Network,
        ),
      );
      when(
        () =>
            walletRepository.getWallets(environment: any(named: 'environment')),
      ).thenAnswer((_) async => []);
      when(
        () => walletRepository.deleteWallet(walletId: any(named: 'walletId')),
      ).thenAnswer((_) async {});
      when(
        () => walletManifest.recordOrigin(
          walletId: any(named: 'walletId'),
          network: any(named: 'network'),
          rootFingerprint: any(named: 'rootFingerprint'),
          bip85DerivationPath: any(named: 'bip85DerivationPath'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => walletManifest.publishLocalManifest(),
      ).thenAnswer((_) async {});
    });

    test('creates Lightning Address metadata when requested', () async {
      final wallet = await usecase.execute(
        environment: Environment.mainnet,
        purpose: ExternalReceiveWalletPurpose.lightningAddress,
      );

      expect(
        wallet.label,
        ReservedExternalReceiveWalletLabel.lightningAddressLiquid,
      );
      verify(
        () => getWallet.execute(
          environment: Environment.mainnet,
          purpose: ExternalReceiveWalletPurpose.lightningAddress,
          accountKey: any(named: 'accountKey'),
        ),
      ).called(1);
      verify(
        () => walletRepository.getWallets(
          environment: Environment.mainnet,
          onlyDefaults: true,
          onlyBitcoin: true,
        ),
      ).called(1);
      verify(
        () => bip85Repository.deriveMnemonicPreview(
          xprvBase58: any(named: 'xprvBase58'),
          length: bip39.MnemonicLength.words12,
          index: ExternalReceiveWalletBip85Index.lightningAddress,
        ),
      ).called(1);
      verify(
        () => walletRepository.createWallet(
          seed: any(named: 'seed'),
          network: Network.liquidMainnet,
          scriptType: ScriptType.bip84,
          label: ReservedExternalReceiveWalletLabel.lightningAddressLiquid,
        ),
      ).called(1);
      verifyInOrder([
        () => bip85Repository.recordMnemonicDerivation(
          xprvBase58: any(named: 'xprvBase58'),
          derivationPath: "39'/0'/12'/75'",
          alias: ReservedExternalReceiveWalletLabel.lightningAddressLiquid,
          usage: Bip85Usage.system,
        ),
        () => walletManifest.recordOrigin(
          walletId: wallet.id,
          network: WalletManifestNetwork.liquid,
          rootFingerprint: _kFingerprint,
          bip85DerivationPath: "m/83696968'/39'/0'/12'/75'",
        ),
        () => walletManifest.publishLocalManifest(),
      ]);
    });

    test('uses the requested purpose metadata', () async {
      final wallet = await usecase.execute(
        environment: Environment.testnet,
        purpose: ExternalReceiveWalletPurpose.btcpay,
      );

      expect(wallet.label, ReservedExternalReceiveWalletLabel.btcpayLiquid);
      verify(
        () => getWallet.execute(
          environment: Environment.testnet,
          purpose: ExternalReceiveWalletPurpose.btcpay,
          accountKey: any(named: 'accountKey'),
        ),
      ).called(1);
      verify(
        () => walletRepository.getWallets(
          environment: Environment.testnet,
          onlyDefaults: true,
          onlyBitcoin: true,
        ),
      ).called(1);
      verify(
        () => bip85Repository.deriveMnemonicPreview(
          xprvBase58: any(named: 'xprvBase58'),
          length: bip39.MnemonicLength.words12,
          index: ExternalReceiveWalletBip85Index.btcpay,
        ),
      ).called(1);
      verify(
        () => walletRepository.createWallet(
          seed: any(named: 'seed'),
          network: Network.liquidTestnet,
          scriptType: ScriptType.bip84,
          label: ReservedExternalReceiveWalletLabel.btcpayLiquid,
        ),
      ).called(1);
      verify(
        () => bip85Repository.recordMnemonicDerivation(
          xprvBase58: any(named: 'xprvBase58'),
          derivationPath: "39'/0'/12'/77'",
          alias: ReservedExternalReceiveWalletLabel.btcpayLiquid,
          usage: Bip85Usage.system,
        ),
      ).called(1);
      verify(
        () => walletManifest.recordOrigin(
          walletId: wallet.id,
          network: WalletManifestNetwork.liquidTestnet,
          rootFingerprint: _kFingerprint,
          bip85DerivationPath: "m/83696968'/39'/0'/12'/77'",
        ),
      ).called(1);
      verify(() => walletManifest.publishLocalManifest()).called(1);
    });

    test('creates Bitcoin accounts for BTCPay account keys', () async {
      final wallet = await usecase.execute(
        environment: Environment.mainnet,
        purpose: ExternalReceiveWalletPurpose.btcpay,
        accountKey: ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(
          isTestnet: false,
        ),
      );

      expect(wallet.label, ReservedExternalReceiveWalletLabel.btcpayBitcoin);
      verify(
        () => walletRepository.createWallet(
          seed: any(named: 'seed'),
          network: Network.bitcoinMainnet,
          scriptType: ScriptType.bip84,
          label: ReservedExternalReceiveWalletLabel.btcpayBitcoin,
        ),
      ).called(1);
      verify(
        () => walletManifest.recordOrigin(
          walletId: wallet.id,
          network: WalletManifestNetwork.bitcoin,
          rootFingerprint: _kFingerprint,
          bip85DerivationPath: "m/83696968'/39'/0'/12'/77'",
        ),
      ).called(1);
      verify(() => walletManifest.publishLocalManifest()).called(1);
    });

    test('keeps the created wallet when manifest publishing fails', () async {
      when(
        () => walletManifest.publishLocalManifest(),
      ).thenThrow(Exception('relay offline'));

      final wallet = await usecase.execute(
        environment: Environment.mainnet,
        purpose: ExternalReceiveWalletPurpose.paymentPage,
      );

      expect(
        wallet.label,
        ReservedExternalReceiveWalletLabel.paymentPageLiquid,
      );
      verify(
        () => walletManifest.recordOrigin(
          walletId: wallet.id,
          network: WalletManifestNetwork.liquid,
          rootFingerprint: _kFingerprint,
          bip85DerivationPath: "m/83696968'/39'/0'/12'/76'",
        ),
      ).called(1);
      verify(() => walletManifest.publishLocalManifest()).called(1);
    });

    test('does not publish when origin persistence fails', () async {
      when(
        () => walletManifest.recordOrigin(
          walletId: any(named: 'walletId'),
          network: any(named: 'network'),
          rootFingerprint: any(named: 'rootFingerprint'),
          bip85DerivationPath: any(named: 'bip85DerivationPath'),
        ),
      ).thenThrow(Exception('origin failed'));

      await expectLater(
        usecase.execute(
          environment: Environment.mainnet,
          purpose: ExternalReceiveWalletPurpose.paymentPage,
        ),
        throwsA(anything),
      );

      verifyNever(() => walletManifest.publishLocalManifest());
      verify(
        () => bip85Repository.deleteMnemonicDerivation(
          xprvBase58: any(named: 'xprvBase58'),
          derivationPath: "39'/0'/12'/76'",
        ),
      ).called(1);
      verify(
        () => walletRepository.deleteWallet(
          walletId: ReservedExternalReceiveWalletLabel.paymentPageLiquid,
        ),
      ).called(1);
    });

    test('does not record origin when derivation persistence fails', () async {
      when(
        () => bip85Repository.recordMnemonicDerivation(
          xprvBase58: any(named: 'xprvBase58'),
          derivationPath: any(named: 'derivationPath'),
          alias: any(named: 'alias'),
          usage: any(named: 'usage'),
        ),
      ).thenThrow(Exception('derivation failed'));

      await expectLater(
        usecase.execute(
          environment: Environment.mainnet,
          purpose: ExternalReceiveWalletPurpose.paymentPage,
        ),
        throwsA(isA<ExternalReceiveWalletMetadataException>()),
      );

      verifyNever(
        () => walletManifest.recordOrigin(
          walletId: any(named: 'walletId'),
          network: any(named: 'network'),
          rootFingerprint: any(named: 'rootFingerprint'),
          bip85DerivationPath: any(named: 'bip85DerivationPath'),
        ),
      );
      verifyNever(() => walletManifest.publishLocalManifest());
      verify(
        () => walletRepository.deleteWallet(
          walletId: ReservedExternalReceiveWalletLabel.paymentPageLiquid,
        ),
      ).called(1);
    });

    test('does not record origin when local wallet creation fails', () async {
      when(
        () => walletRepository.createWallet(
          seed: any(named: 'seed'),
          network: any(named: 'network'),
          scriptType: any(named: 'scriptType'),
          label: any(named: 'label'),
        ),
      ).thenThrow(Exception('wallet create failed'));

      await expectLater(
        usecase.execute(
          environment: Environment.mainnet,
          purpose: ExternalReceiveWalletPurpose.paymentPage,
        ),
        throwsA(anything),
      );

      verifyNever(
        () => walletManifest.recordOrigin(
          walletId: any(named: 'walletId'),
          network: any(named: 'network'),
          rootFingerprint: any(named: 'rootFingerprint'),
          bip85DerivationPath: any(named: 'bip85DerivationPath'),
        ),
      );
      verifyNever(() => walletManifest.publishLocalManifest());
    });

    test(
      'repairs an existing local wallet before creating a duplicate',
      () async {
        final childFingerprint = _fingerprintForMnemonic(_kChildMnemonic);
        final existingWallet = _liquidWallet(
          ReservedExternalReceiveWalletLabel.paymentPageLiquid,
        ).copyWith(masterFingerprint: childFingerprint, label: 'User label');
        when(
          () => walletRepository.getWallets(environment: Environment.mainnet),
        ).thenAnswer((_) async => [existingWallet]);

        final wallet = await usecase.execute(
          environment: Environment.mainnet,
          purpose: ExternalReceiveWalletPurpose.paymentPage,
        );

        expect(wallet, existingWallet);
        verify(
          () => walletManifest.recordOrigin(
            walletId: existingWallet.id,
            network: WalletManifestNetwork.liquid,
            rootFingerprint: _kFingerprint,
            bip85DerivationPath: "m/83696968'/39'/0'/12'/76'",
          ),
        ).called(1);
        verify(() => walletManifest.publishLocalManifest()).called(1);
        verifyNever(
          () => walletRepository.createWallet(
            seed: any(named: 'seed'),
            network: any(named: 'network'),
            scriptType: any(named: 'scriptType'),
            label: any(named: 'label'),
          ),
        );
        verifyNever(
          () => seedRepository.createFromMnemonic(
            mnemonicWords: any(named: 'mnemonicWords'),
          ),
        );
      },
    );

    test('rejects Bitcoin account keys for non-BTCPay purposes', () async {
      await expectLater(
        usecase.execute(
          environment: Environment.mainnet,
          purpose: ExternalReceiveWalletPurpose.lightningAddress,
          accountKey: ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(
            isTestnet: false,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects account keys from the wrong environment', () async {
      await expectLater(
        usecase.execute(
          environment: Environment.testnet,
          purpose: ExternalReceiveWalletPurpose.btcpay,
          accountKey: ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(
            isTestnet: false,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );

      verifyNever(
        () => walletRepository.createWallet(
          seed: any(named: 'seed'),
          network: any(named: 'network'),
          scriptType: any(named: 'scriptType'),
          label: any(named: 'label'),
        ),
      );
      verifyNever(
        () => walletManifest.recordOrigin(
          walletId: any(named: 'walletId'),
          network: any(named: 'network'),
          rootFingerprint: any(named: 'rootFingerprint'),
          bip85DerivationPath: any(named: 'bip85DerivationPath'),
        ),
      );
      verifyNever(() => walletManifest.publishLocalManifest());
    });

    test('does not derive when the requested wallet exists', () async {
      final existingWallet = _liquidWallet(
        ReservedExternalReceiveWalletLabel.paymentPageLiquid,
      );
      when(
        () => getWallet.execute(
          environment: any(named: 'environment'),
          purpose: any(named: 'purpose'),
          accountKey: any(named: 'accountKey'),
        ),
      ).thenAnswer((_) async => existingWallet);

      await expectLater(
        usecase.execute(
          environment: Environment.mainnet,
          purpose: ExternalReceiveWalletPurpose.paymentPage,
        ),
        throwsA(isA<ExternalReceiveWalletAlreadyExistsException>()),
      );

      verifyNever(
        () => bip85Repository.deriveMnemonicPreview(
          xprvBase58: any(named: 'xprvBase58'),
          length: any(named: 'length'),
          index: any(named: 'index'),
        ),
      );
      verifyNever(
        () => walletManifest.recordOrigin(
          walletId: any(named: 'walletId'),
          network: any(named: 'network'),
          rootFingerprint: any(named: 'rootFingerprint'),
          bip85DerivationPath: any(named: 'bip85DerivationPath'),
        ),
      );
      verifyNever(() => walletManifest.publishLocalManifest());
      verifyNever(
        () => walletRepository.createWallet(
          seed: any(named: 'seed'),
          network: any(named: 'network'),
          scriptType: any(named: 'scriptType'),
          label: any(named: 'label'),
        ),
      );
    });
  });

  group('RestoreReservedExternalReceiveWalletsUsecase', () {
    late _MockGetWallet getWallet;
    late _MockCreateExternalReceiveWalletUsecase createWallet;
    late _MockWalletManifestFacade walletManifest;
    late RestoreReservedExternalReceiveWalletsUsecase usecase;

    setUp(() {
      getWallet = _MockGetWallet();
      createWallet = _MockCreateExternalReceiveWalletUsecase();
      walletManifest = _MockWalletManifestFacade();
      usecase = RestoreReservedExternalReceiveWalletsUsecase(
        getWallet: getWallet,
        createWallet: createWallet,
        walletManifest: walletManifest,
      );

      when(
        () => getWallet.execute(
          environment: any(named: 'environment'),
          purpose: any(named: 'purpose'),
          accountKey: any(named: 'accountKey'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => createWallet.executeWithResult(
          environment: any(named: 'environment'),
          purpose: any(named: 'purpose'),
          accountKey: any(named: 'accountKey'),
          publishManifest: any(named: 'publishManifest'),
        ),
      ).thenAnswer((invocation) async {
        final key =
            invocation.namedArguments[#accountKey]
                as ExternalReceiveWalletAccountKey;
        return CreateExternalReceiveWalletResult(
          wallet: _externalWallet(key.walletLabel, network: key.network),
          status: CreateExternalReceiveWalletStatus.created,
        );
      });
      when(
        () => walletManifest.publishLocalManifest(),
      ).thenAnswer((_) async {});
    });

    test('creates exactly the supported reserved Get Paid wallets', () async {
      final result = await usecase.execute(environment: Environment.mainnet);

      expect(result, hasLength(4));
      expect(
        result.map((outcome) => outcome.status),
        everyElement(ExternalReceiveWalletRestoreOutcomeStatus.created),
      );
      verify(
        () => createWallet.executeWithResult(
          environment: Environment.mainnet,
          purpose: ExternalReceiveWalletPurpose.lightningAddress,
          accountKey: ExternalReceiveWalletPurpose.lightningAddress
              .liquidAccountKey(isTestnet: false),
          publishManifest: false,
        ),
      ).called(1);
      verify(
        () => createWallet.executeWithResult(
          environment: Environment.mainnet,
          purpose: ExternalReceiveWalletPurpose.paymentPage,
          accountKey: ExternalReceiveWalletPurpose.paymentPage.liquidAccountKey(
            isTestnet: false,
          ),
          publishManifest: false,
        ),
      ).called(1);
      verify(
        () => createWallet.executeWithResult(
          environment: Environment.mainnet,
          purpose: ExternalReceiveWalletPurpose.btcpay,
          accountKey: ExternalReceiveWalletPurpose.btcpay.liquidAccountKey(
            isTestnet: false,
          ),
          publishManifest: false,
        ),
      ).called(1);
      verify(
        () => createWallet.executeWithResult(
          environment: Environment.mainnet,
          purpose: ExternalReceiveWalletPurpose.btcpay,
          accountKey: ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(
            isTestnet: false,
          ),
          publishManifest: false,
        ),
      ).called(1);
      verify(() => walletManifest.publishLocalManifest()).called(1);
    });

    test('returns existing wallets as success without creating', () async {
      when(
        () => getWallet.execute(
          environment: any(named: 'environment'),
          purpose: any(named: 'purpose'),
          accountKey: any(named: 'accountKey'),
        ),
      ).thenAnswer((invocation) async {
        final key =
            invocation.namedArguments[#accountKey]
                as ExternalReceiveWalletAccountKey;
        return _externalWallet(key.walletLabel, network: key.network);
      });

      final result = await usecase.execute(environment: Environment.mainnet);

      expect(
        result.map((outcome) => outcome.status),
        everyElement(ExternalReceiveWalletRestoreOutcomeStatus.existing),
      );
      expect(result.any((outcome) => outcome.changedLocalState), isFalse);
      verifyNever(
        () => createWallet.executeWithResult(
          environment: any(named: 'environment'),
          purpose: any(named: 'purpose'),
          accountKey: any(named: 'accountKey'),
          publishManifest: any(named: 'publishManifest'),
        ),
      );
      verifyNever(() => walletManifest.publishLocalManifest());
    });

    test(
      'repairs an existing local wallet that has no manifest origin',
      () async {
        final repairedWallet = _externalWallet(
          'User label',
          network: Network.liquidMainnet,
        );
        when(
          () => createWallet.executeWithResult(
            environment: Environment.mainnet,
            purpose: ExternalReceiveWalletPurpose.lightningAddress,
            accountKey: any(named: 'accountKey'),
            publishManifest: any(named: 'publishManifest'),
          ),
        ).thenAnswer(
          (_) async => CreateExternalReceiveWalletResult(
            wallet: repairedWallet,
            status: CreateExternalReceiveWalletStatus.repaired,
          ),
        );

        final result = await usecase.execute(environment: Environment.mainnet);

        expect(
          result.first.status,
          ExternalReceiveWalletRestoreOutcomeStatus.repaired,
        );
      },
    );

    test('continues when one account fails', () async {
      when(
        () => createWallet.executeWithResult(
          environment: Environment.mainnet,
          purpose: ExternalReceiveWalletPurpose.paymentPage,
          accountKey: any(named: 'accountKey'),
          publishManifest: any(named: 'publishManifest'),
        ),
      ).thenThrow(Exception('create failed'));

      final result = await usecase.execute(environment: Environment.mainnet);

      expect(result, hasLength(4));
      expect(
        result
            .where(
              (outcome) =>
                  outcome.accountKey.purpose ==
                  ExternalReceiveWalletPurpose.paymentPage,
            )
            .single
            .status,
        ExternalReceiveWalletRestoreOutcomeStatus.failed,
      );
      expect(
        result.any(
          (outcome) =>
              outcome.status ==
              ExternalReceiveWalletRestoreOutcomeStatus.failed,
        ),
        isTrue,
      );
      expect(
        result
            .where(
              (outcome) =>
                  outcome.accountKey.purpose ==
                  ExternalReceiveWalletPurpose.paymentPage,
            )
            .single
            .failureReason,
        ExternalReceiveWalletRestoreFailureReason.walletCreationFailed,
      );
      verify(() => walletManifest.publishLocalManifest()).called(1);
    });

    test(
      'reports failed metadata when origin persistence rolls back creation',
      () async {
        final partialWallet = _externalWallet(
          ReservedExternalReceiveWalletLabel.paymentPageLiquid,
        );
        when(
          () => createWallet.executeWithResult(
            environment: Environment.mainnet,
            purpose: ExternalReceiveWalletPurpose.paymentPage,
            accountKey: any(named: 'accountKey'),
            publishManifest: any(named: 'publishManifest'),
          ),
        ).thenThrow(
          ExternalReceiveWalletMetadataException(
            wallet: partialWallet,
            cause: Exception('origin failed'),
          ),
        );

        final result = await usecase.execute(environment: Environment.mainnet);
        final outcome = result
            .where(
              (outcome) =>
                  outcome.accountKey.purpose ==
                  ExternalReceiveWalletPurpose.paymentPage,
            )
            .single;

        expect(
          outcome.status,
          ExternalReceiveWalletRestoreOutcomeStatus.failed,
        );
        expect(
          outcome.failureReason,
          ExternalReceiveWalletRestoreFailureReason.metadataUpdateFailed,
        );
        expect(
          result.any(
            (outcome) =>
                outcome.status ==
                ExternalReceiveWalletRestoreOutcomeStatus.failed,
          ),
          isTrue,
        );
        expect(outcome.changedLocalState, isFalse);
        verify(() => walletManifest.publishLocalManifest()).called(1);
      },
    );

    test(
      'reports a repair metadata failure without claiming creation',
      () async {
        final partialWallet = _externalWallet(
          ReservedExternalReceiveWalletLabel.paymentPageLiquid,
        );
        when(
          () => createWallet.executeWithResult(
            environment: Environment.mainnet,
            purpose: ExternalReceiveWalletPurpose.paymentPage,
            accountKey: any(named: 'accountKey'),
            publishManifest: any(named: 'publishManifest'),
          ),
        ).thenThrow(
          ExternalReceiveWalletMetadataException(
            wallet: partialWallet,
            cause: Exception('origin failed'),
            repairedExistingWallet: true,
          ),
        );

        final result = await usecase.execute(environment: Environment.mainnet);
        final outcome = result
            .where(
              (outcome) =>
                  outcome.accountKey.purpose ==
                  ExternalReceiveWalletPurpose.paymentPage,
            )
            .single;

        expect(
          outcome.status,
          ExternalReceiveWalletRestoreOutcomeStatus.failed,
        );
        expect(
          outcome.failureReason,
          ExternalReceiveWalletRestoreFailureReason.metadataUpdateFailed,
        );
      },
    );

    test('treats an already-exists race as existing after re-read', () async {
      var paymentPageGetCount = 0;
      when(
        () => getWallet.execute(
          environment: any(named: 'environment'),
          purpose: any(named: 'purpose'),
          accountKey: any(named: 'accountKey'),
        ),
      ).thenAnswer((invocation) async {
        final purpose =
            invocation.namedArguments[#purpose] as ExternalReceiveWalletPurpose;
        final key =
            invocation.namedArguments[#accountKey]
                as ExternalReceiveWalletAccountKey;
        if (purpose != ExternalReceiveWalletPurpose.paymentPage) {
          return null;
        }
        paymentPageGetCount += 1;
        if (paymentPageGetCount == 1) return null;
        return _externalWallet(key.walletLabel, network: key.network);
      });
      when(
        () => createWallet.executeWithResult(
          environment: Environment.mainnet,
          purpose: ExternalReceiveWalletPurpose.paymentPage,
          accountKey: any(named: 'accountKey'),
          publishManifest: any(named: 'publishManifest'),
        ),
      ).thenThrow(ExternalReceiveWalletAlreadyExistsException());

      final result = await usecase.execute(environment: Environment.mainnet);

      expect(
        result
            .where(
              (outcome) =>
                  outcome.accountKey.purpose ==
                  ExternalReceiveWalletPurpose.paymentPage,
            )
            .single
            .status,
        ExternalReceiveWalletRestoreOutcomeStatus.existing,
      );
    });

    test(
      'treats an already-exists race as repaired when re-read is missing',
      () async {
        var createCount = 0;
        final repairedWallet = _externalWallet(
          ReservedExternalReceiveWalletLabel.lightningAddressLiquid,
        );
        when(
          () => createWallet.executeWithResult(
            environment: Environment.mainnet,
            purpose: ExternalReceiveWalletPurpose.lightningAddress,
            accountKey: any(named: 'accountKey'),
            publishManifest: any(named: 'publishManifest'),
          ),
        ).thenAnswer((_) async {
          createCount += 1;
          if (createCount == 1) {
            throw ExternalReceiveWalletAlreadyExistsException();
          }
          return CreateExternalReceiveWalletResult(
            wallet: repairedWallet,
            status: CreateExternalReceiveWalletStatus.repaired,
          );
        });

        final result = await usecase.execute(environment: Environment.mainnet);

        expect(
          result.first.status,
          ExternalReceiveWalletRestoreOutcomeStatus.repaired,
        );
      },
    );

    test(
      'does not report an already-exists race for unexpected race recovery failures',
      () async {
        var createCount = 0;
        when(
          () => createWallet.executeWithResult(
            environment: Environment.mainnet,
            purpose: ExternalReceiveWalletPurpose.paymentPage,
            accountKey: any(named: 'accountKey'),
            publishManifest: any(named: 'publishManifest'),
          ),
        ).thenAnswer((_) async {
          createCount += 1;
          if (createCount == 1) {
            throw ExternalReceiveWalletAlreadyExistsException();
          }
          throw Exception('unexpected retry failure');
        });

        final result = await usecase.execute(environment: Environment.mainnet);
        final outcome = result
            .where(
              (outcome) =>
                  outcome.accountKey.purpose ==
                  ExternalReceiveWalletPurpose.paymentPage,
            )
            .single;

        expect(
          outcome.status,
          ExternalReceiveWalletRestoreOutcomeStatus.failed,
        );
        expect(outcome.failureReason, isNull);
      },
    );

    test('maps missing default wallet into per-account failures', () async {
      when(
        () => getWallet.execute(
          environment: any(named: 'environment'),
          purpose: any(named: 'purpose'),
          accountKey: any(named: 'accountKey'),
        ),
      ).thenThrow(ExternalReceiveWalletNoDefaultWalletException());

      final result = await usecase.execute(environment: Environment.mainnet);

      expect(
        result.map((outcome) => outcome.status),
        everyElement(ExternalReceiveWalletRestoreOutcomeStatus.failed),
      );
      expect(
        result.map((outcome) => outcome.failureReason),
        everyElement(ExternalReceiveWalletRestoreFailureReason.noDefaultWallet),
      );
      verifyNever(() => walletManifest.publishLocalManifest());
    });
  });
}
