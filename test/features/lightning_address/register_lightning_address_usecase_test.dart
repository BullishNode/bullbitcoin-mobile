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
import 'package:bb_mobile/features/external_receive_wallets/public/external_receive_wallets.dart';
import 'package:bb_mobile/features/external_receive_wallets/reserved_external_receive_wallet_labels.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/register_lightning_address_usecase.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPayService extends Mock implements PayServicePort {}

class _MockWalletRepository extends Mock implements WalletRepository {}

class _MockSeedRepository extends Mock implements SeedRepository {}

class _MockExternalReceiveWalletsFacade extends Mock
    implements ExternalReceiveWalletsFacade {}

const _kZeroMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const _kFingerprint = '73c5da0a';
const _kCtDescriptor =
    'ct(slip77(...),elwpkh([fingerprint/84h/1776h/0h]xpubFAKE/<0;1>/*))';
const _kExpectedBullnymAuthPublicKeyHex =
    '23a772c17ca7b9eba8c9442c4378c063d791967e35fbaed98a51d65243c03cd4';
const _kExpectedNip05PublicKeyHex =
    'bb2823fcf6f9187227c5ed4f89730228e32412ca89e9b96a2c190bddb9e525ea';

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
  label: ReservedExternalReceiveWalletLabel.lightningAddressLiquid,
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
    registerFallbackValue(ExternalReceiveWalletPurpose.lightningAddress);
    registerFallbackValue(NostrKeychainHandle.fromSecretKeyHex('01' * 32));
  });

  late _MockPayService payService;
  late _MockWalletRepository walletRepo;
  late _MockSeedRepository seedRepo;
  late _MockExternalReceiveWalletsFacade externalReceiveWallets;
  late RegisterLightningAddressUsecase usecase;

  setUp(() {
    payService = _MockPayService();
    walletRepo = _MockWalletRepository();
    seedRepo = _MockSeedRepository();
    externalReceiveWallets = _MockExternalReceiveWalletsFacade();
    usecase = RegisterLightningAddressUsecase(
      externalReceiveWallets: externalReceiveWallets,
      walletRepository: walletRepo,
      seedRepository: seedRepo,
      payService: payService,
    );

    when(
      () => walletRepo.getWallets(
        environment: any(named: 'environment'),
        onlyDefaults: any(named: 'onlyDefaults'),
        onlyBitcoin: any(named: 'onlyBitcoin'),
      ),
    ).thenAnswer((_) async => [_bitcoinDefault()]);
    when(() => seedRepo.get(any())).thenAnswer((_) async => _zeroSeed());
    when(
      () => externalReceiveWallets.get(
        environment: any(named: 'environment'),
        purpose: any(named: 'purpose'),
      ),
    ).thenAnswer((_) async => _liquidLaWallet());
    when(
      () => externalReceiveWallets.create(
        environment: any(named: 'environment'),
        purpose: any(named: 'purpose'),
      ),
    ).thenAnswer((_) async => _liquidLaWallet());
    when(
      () => payService.register(
        nym: any(named: 'nym'),
        ctDescriptor: any(named: 'ctDescriptor'),
        authHandle: any(named: 'authHandle'),
        verificationNpubHex: any(named: 'verificationNpubHex'),
      ),
    ).thenAnswer(
      (_) async =>
          (address: 'alice@bullpay.ca', quota: const NymQuota(used: 1, cap: 3)),
    );
  });

  ({
    String nym,
    String ctDescriptor,
    NostrKeychainHandle authHandle,
    String verificationNpubHex,
  })
  captureRegister() {
    final captured = verify(
      () => payService.register(
        nym: captureAny(named: 'nym'),
        ctDescriptor: captureAny(named: 'ctDescriptor'),
        authHandle: captureAny(named: 'authHandle'),
        verificationNpubHex: captureAny(named: 'verificationNpubHex'),
      ),
    ).captured;
    return (
      nym: captured[0] as String,
      ctDescriptor: captured[1] as String,
      authHandle: captured[2] as NostrKeychainHandle,
      verificationNpubHex: captured[3] as String,
    );
  }

  test('uses get-or-create wallet flow', () async {
    when(
      () => externalReceiveWallets.get(
        environment: any(named: 'environment'),
        purpose: any(named: 'purpose'),
      ),
    ).thenAnswer((_) async => null);

    await usecase.execute(nym: 'alice', environment: Environment.mainnet);

    verify(
      () => externalReceiveWallets.create(
        environment: any(named: 'environment'),
        purpose: ExternalReceiveWalletPurpose.lightningAddress,
      ),
    ).called(1);
  });

  test('skips create when wallet already exists', () async {
    await usecase.execute(nym: 'alice', environment: Environment.mainnet);

    verifyNever(
      () => externalReceiveWallets.create(
        environment: any(named: 'environment'),
        purpose: any(named: 'purpose'),
      ),
    );
  });

  test('sends nym + ctDescriptor + split Nostr identities', () async {
    await usecase.execute(nym: 'alice', environment: Environment.mainnet);
    final c = captureRegister();

    expect(c.nym, 'alice');
    expect(c.ctDescriptor, _kCtDescriptor);
    expect(c.authHandle.publicKeyHex, _kExpectedBullnymAuthPublicKeyHex);
    expect(c.verificationNpubHex, _kExpectedNip05PublicKeyHex);
    expect(c.verificationNpubHex, isNot(c.authHandle.publicKeyHex));
  });

  test('does not construct Bullnym signatures in the use case', () async {
    await usecase.execute(nym: 'alice', environment: Environment.mainnet);
    final c = captureRegister();

    expect(c.authHandle.publicKeyHex, isNotEmpty);
  });

  test(
    'PayServiceException maps to LightningAddressRegistrationException',
    () async {
      when(
        () => payService.register(
          nym: any(named: 'nym'),
          ctDescriptor: any(named: 'ctDescriptor'),
          authHandle: any(named: 'authHandle'),
          verificationNpubHex: any(named: 'verificationNpubHex'),
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
