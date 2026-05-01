import 'dart:typed_data';

import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/create_lightning_address_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/get_lightning_address_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/recover_lightning_address_usecase.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPayService extends Mock implements PayServicePort {}

class _MockWalletRepository extends Mock implements WalletRepository {}

class _MockSeedRepository extends Mock implements SeedRepository {}

class _MockGetWallet extends Mock implements GetLightningAddressWalletUsecase {}

class _MockCreateWallet extends Mock
    implements CreateLightningAddressWalletUsecase {}

const _kZeroMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const _kFingerprint = '73c5da0a';

Wallet _bitcoinDefault() => Wallet(
      origin: 'btc-default',
      network: Network.bitcoinMainnet,
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

Wallet _liquidLaWallet() => Wallet(
      origin: 'la-liquid',
      network: Network.liquidMainnet,
      isDefault: false,
      masterFingerprint: 'aabbccdd',
      xpubFingerprint: 'aabbccdd',
      scriptType: ScriptType.bip84,
      xpub: 'xpubLA',
      externalPublicDescriptor: 'elwpkh(xpubLA)',
      internalPublicDescriptor: 'elwpkh(xpubLA)',
      signer: SignerEntity.local,
      signerDevice: null,
      balanceSat: BigInt.zero,
      label: 'Lightning Address',
    );

Seed _zeroSeed() {
  final m =
      bip39.Mnemonic.fromSentence(_kZeroMnemonic, bip39.Language.english);
  return Seed.mnemonic(
    mnemonicWords: _kZeroMnemonic.split(' '),
    bytes: Uint8List.fromList(m.seed),
    masterFingerprint: _kFingerprint,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(Environment.mainnet);
  });

  late _MockPayService payService;
  late _MockWalletRepository walletRepo;
  late _MockSeedRepository seedRepo;
  late _MockGetWallet getWallet;
  late _MockCreateWallet createWallet;
  late RecoverLightningAddressUsecase usecase;

  setUp(() {
    payService = _MockPayService();
    walletRepo = _MockWalletRepository();
    seedRepo = _MockSeedRepository();
    getWallet = _MockGetWallet();
    createWallet = _MockCreateWallet();
    usecase = RecoverLightningAddressUsecase(
      getWallet: getWallet,
      createWallet: createWallet,
      payService: payService,
      walletRepository: walletRepo,
      seedRepository: seedRepo,
    );

    when(() => walletRepo.getWallets(
          onlyDefaults: any(named: 'onlyDefaults'),
          onlyBitcoin: any(named: 'onlyBitcoin'),
        )).thenAnswer((_) async => [_bitcoinDefault()]);
    when(() => seedRepo.get(any())).thenAnswer((_) async => _zeroSeed());
    when(() => getWallet.execute(environment: any(named: 'environment')))
        .thenAnswer((_) async => _liquidLaWallet());
    when(() => createWallet.execute(environment: any(named: 'environment')))
        .thenAnswer((_) async => _liquidLaWallet());
    when(() => payService.storeAddress(any()))
        .thenAnswer((_) async {});
    when(() => payService.getStoredAddress()).thenAnswer((_) async => null);
  });

  test('exits early when an address is already stored locally', () async {
    when(() => payService.getStoredAddress())
        .thenAnswer((_) async => 'already@bullpay.ca');

    final out = await usecase.execute(environment: Environment.mainnet);

    expect(out, isNull);
    verifyNever(() => payService.lookupByNpub(any()));
  });

  test('returns null on 404 (no server-side registration)', () async {
    when(() => payService.lookupByNpub(any()))
        .thenAnswer((_) async => null);

    final out = await usecase.execute(environment: Environment.mainnet);

    expect(out, isNull);
    verifyNever(() => payService.storeAddress(any()));
  });

  test('returns null on inactive registration', () async {
    when(() => payService.lookupByNpub(any()))
        .thenAnswer((_) async => (nym: 'alice', active: false));

    final out = await usecase.execute(environment: Environment.mainnet);

    expect(out, isNull);
    verifyNever(() => payService.storeAddress(any()));
  });

  test('catches PayServiceException (5xx/timeout) and returns null', () async {
    when(() => payService.lookupByNpub(any()))
        .thenThrow(PayServiceException('connection-reset'));

    final out = await usecase.execute(environment: Environment.mainnet);

    expect(out, isNull);
    // Don't mark recovery complete on transient failure — next launch retries.
    verifyNever(() => payService.storeAddress(any()));
  });

  test('on active record: creates wallet if missing and stores address',
      () async {
    when(() => getWallet.execute(environment: any(named: 'environment')))
        .thenAnswer((_) async => null);
    when(() => payService.lookupByNpub(any()))
        .thenAnswer((_) async => (nym: 'alice', active: true));

    final out = await usecase.execute(environment: Environment.mainnet);

    expect(out, 'alice@bullpay.ca');
    verify(() => createWallet.execute(environment: any(named: 'environment')))
        .called(1);
    verify(() => payService.storeAddress('alice@bullpay.ca')).called(1);
  });

  test('on active record: skips wallet create when wallet already present',
      () async {
    when(() => payService.lookupByNpub(any()))
        .thenAnswer((_) async => (nym: 'alice', active: true));

    final out = await usecase.execute(environment: Environment.mainnet);

    expect(out, 'alice@bullpay.ca');
    verifyNever(() => createWallet.execute(environment: any(named: 'environment')));
    verify(() => payService.storeAddress('alice@bullpay.ca')).called(1);
  });
}

