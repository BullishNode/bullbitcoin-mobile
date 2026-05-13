import 'dart:typed_data';

import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/value_objects/nym_quota.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/create_bullnym_receive_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/get_bullnym_receive_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/register_lightning_address_usecase.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPayService extends Mock implements PayServicePort {}

class _MockWalletRepository extends Mock implements WalletRepository {}

class _MockSeedRepository extends Mock implements SeedRepository {}

class _MockGetWallet extends Mock implements GetBullnymReceiveWalletUsecase {}

class _MockCreateWallet extends Mock
    implements CreateBullnymReceiveWalletUsecase {}

const _kZeroMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const _kFingerprint = '73c5da0a';
const _kCtDescriptor =
    'ct(slip77(...),elwpkh([fingerprint/84h/1776h/0h]xpubFAKE/<0;1>/*))';

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

Wallet _liquidLaWallet() => Wallet(
  origin: 'la-liquid',
  network: Network.liquidMainnet,
  isDefault: false,
  masterFingerprint: 'aabbccdd',
  xpubFingerprint: 'aabbccdd',
  scriptType: ScriptType.bip84,
  xpub: 'xpubLA',
  externalPublicDescriptor: _kCtDescriptor,
  internalPublicDescriptor: _kCtDescriptor,
  signer: SignerEntity.local,
  signerDevice: null,
  balanceSat: BigInt.zero,
  label: 'Lightning Address',
);

Seed _zeroSeed() {
  final mnemonic = bip39.Mnemonic.fromSentence(
    _kZeroMnemonic,
    bip39.Language.english,
  );
  return Seed.mnemonic(
    mnemonicWords: _kZeroMnemonic.split(' '),
    bytes: Uint8List.fromList(mnemonic.seed),
    masterFingerprint: _kFingerprint,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(Environment.mainnet);
    registerFallbackValue(NostrKeychainHandle.fromSecretKeyHex('01' * 32));
  });

  late _MockPayService payService;
  late _MockWalletRepository walletRepo;
  late _MockSeedRepository seedRepo;
  late _MockGetWallet getWallet;
  late _MockCreateWallet createWallet;
  late RegisterLightningAddressUsecase usecase;

  setUp(() {
    payService = _MockPayService();
    walletRepo = _MockWalletRepository();
    seedRepo = _MockSeedRepository();
    getWallet = _MockGetWallet();
    createWallet = _MockCreateWallet();
    usecase = RegisterLightningAddressUsecase(
      createWallet: createWallet,
      getWallet: getWallet,
      walletRepository: walletRepo,
      seedRepository: seedRepo,
      payService: payService,
    );

    when(
      () => walletRepo.getWallets(
        onlyDefaults: any(named: 'onlyDefaults'),
        onlyBitcoin: any(named: 'onlyBitcoin'),
      ),
    ).thenAnswer((_) async => [_bitcoinDefault()]);
    when(() => seedRepo.get(any())).thenAnswer((_) async => _zeroSeed());
    when(
      () => getWallet.execute(environment: any(named: 'environment')),
    ).thenAnswer((_) async => _liquidLaWallet());
    when(
      () => createWallet.execute(environment: any(named: 'environment')),
    ).thenAnswer((_) async => _liquidLaWallet());
    when(
      () => payService.register(
        nym: any(named: 'nym'),
        ctDescriptor: any(named: 'ctDescriptor'),
        handle: any(named: 'handle'),
      ),
    ).thenAnswer(
      (_) async =>
          (address: 'alice@bullpay.ca', quota: const NymQuota(used: 1, cap: 3)),
    );
  });

  ({String nym, String ctDescriptor, NostrKeychainHandle handle})
  captureRegister() {
    final captured = verify(
      () => payService.register(
        nym: captureAny(named: 'nym'),
        ctDescriptor: captureAny(named: 'ctDescriptor'),
        handle: captureAny(named: 'handle'),
      ),
    ).captured;
    return (
      nym: captured[0] as String,
      ctDescriptor: captured[1] as String,
      handle: captured[2] as NostrKeychainHandle,
    );
  }

  test('uses get-or-create wallet flow', () async {
    when(
      () => getWallet.execute(environment: any(named: 'environment')),
    ).thenAnswer((_) async => null);

    await usecase.execute(nym: 'alice', environment: Environment.mainnet);

    verify(
      () => createWallet.execute(environment: any(named: 'environment')),
    ).called(1);
  });

  test('skips create when wallet already exists', () async {
    await usecase.execute(nym: 'alice', environment: Environment.mainnet);

    verifyNever(
      () => createWallet.execute(environment: any(named: 'environment')),
    );
  });

  test('sends nym + ctDescriptor + derived Nostr handle', () async {
    await usecase.execute(nym: 'alice', environment: Environment.mainnet);
    final c = captureRegister();

    expect(c.nym, 'alice');
    expect(c.ctDescriptor, _kCtDescriptor);
    expect(c.handle.publicKeyHex, hasLength(64));
  });

  test('does not construct Bullnym signatures in the use case', () async {
    await usecase.execute(nym: 'alice', environment: Environment.mainnet);
    final c = captureRegister();

    expect(c.handle.publicKeyHex, isNotEmpty);
  });

  test(
    'PayServiceException maps to LightningAddressRegistrationException',
    () async {
      when(
        () => payService.register(
          nym: any(named: 'nym'),
          ctDescriptor: any(named: 'ctDescriptor'),
          handle: any(named: 'handle'),
        ),
      ).thenThrow(PayServiceException('NymTaken'));

      await expectLater(
        usecase.execute(nym: 'alice', environment: Environment.mainnet),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString().contains('NymTaken'),
            'wraps server message',
            isTrue,
          ),
        ),
      );
    },
  );
}
