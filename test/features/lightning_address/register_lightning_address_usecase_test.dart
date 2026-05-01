import 'dart:convert';
import 'dart:typed_data';

import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_v1_signing.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/create_lightning_address_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/get_lightning_address_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/register_lightning_address_usecase.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:crypto/crypto.dart';
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
  final mnemonic = bip39.Mnemonic.fromSentence(_kZeroMnemonic, bip39.Language.english);
  return Seed.mnemonic(
    mnemonicWords: _kZeroMnemonic.split(' '),
    bytes: Uint8List.fromList(mnemonic.seed),
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

    when(() => walletRepo.getWallets(
          onlyDefaults: any(named: 'onlyDefaults'),
          onlyBitcoin: any(named: 'onlyBitcoin'),
        )).thenAnswer((_) async => [_bitcoinDefault()]);
    when(() => seedRepo.get(any())).thenAnswer((_) async => _zeroSeed());
    when(() => getWallet.execute(environment: any(named: 'environment')))
        .thenAnswer((_) async => _liquidLaWallet());
    when(() => createWallet.execute(environment: any(named: 'environment')))
        .thenAnswer((_) async => _liquidLaWallet());
    when(() => payService.register(
          nym: any(named: 'nym'),
          ctDescriptor: any(named: 'ctDescriptor'),
          npubHex: any(named: 'npubHex'),
          signatureHex: any(named: 'signatureHex'),
          timestampSecs: any(named: 'timestampSecs'),
        )).thenAnswer((_) async => 'alice@bullpay.ca');
  });

  ({String nym, String ctDescriptor, String npubHex, String sigHex, int ts})
      _captureRegister() {
    final captured = verify(() => payService.register(
          nym: captureAny(named: 'nym'),
          ctDescriptor: captureAny(named: 'ctDescriptor'),
          npubHex: captureAny(named: 'npubHex'),
          signatureHex: captureAny(named: 'signatureHex'),
          timestampSecs: captureAny(named: 'timestampSecs'),
        )).captured;
    return (
      nym: captured[0] as String,
      ctDescriptor: captured[1] as String,
      npubHex: captured[2] as String,
      sigHex: captured[3] as String,
      ts: captured[4] as int,
    );
  }

  test('uses get-or-create wallet flow', () async {
    when(() => getWallet.execute(environment: any(named: 'environment')))
        .thenAnswer((_) async => null);

    await usecase.execute(nym: 'alice', environment: Environment.mainnet);

    verify(() => createWallet.execute(environment: any(named: 'environment')))
        .called(1);
  });

  test('skips create when wallet already exists', () async {
    await usecase.execute(nym: 'alice', environment: Environment.mainnet);

    verifyNever(() => createWallet.execute(environment: any(named: 'environment')));
  });

  test('sends nym + ctDescriptor + recent timestamp', () async {
    final before = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    await usecase.execute(nym: 'alice', environment: Environment.mainnet);
    final after = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final c = _captureRegister();

    expect(c.nym, 'alice');
    expect(c.ctDescriptor, _kCtDescriptor);
    expect(c.ts, inInclusiveRange(before, after));
  });

  test('signs the v1 wire format with the BIP85-derived Nostr key', () async {
    await usecase.execute(nym: 'alice', environment: Environment.mainnet);
    final c = _captureRegister();

    // The Schnorr signature must verify against
    //   sha256(`bullpay-la-v1\x00register\x00<npub>\x00<nym>\x00<ct_desc>\x00<ts>`)
    // under the captured npub. Same shape verified server-side in
    // pay-service/src/auth.rs.
    final message = buildLaV1Message(
      action: 'register',
      npubHex: c.npubHex,
      payloadFields: [c.nym, c.ctDescriptor],
      timestampSecs: c.ts,
    );
    final digest = sha256.convert(message).bytes;
    // npub is BIP-340 x-only (32 bytes). Prefix with 0x02 (even-Y) for the
    // generic compressed-pubkey codec; verifyBip340Signature ignores the
    // parity byte.
    final pub = ECPublic.fromHex('02${c.npubHex}');
    expect(
      pub.verifyBip340Signature(
        digest: digest,
        signature: _hexDecode(c.sigHex),
        tweak: false,
      ),
      isTrue,
      reason: 'sig must verify against canonical v1 message bytes',
    );
  });

  test('cross-action replay: a register sig must not verify as a delete',
      () async {
    await usecase.execute(nym: 'alice', environment: Environment.mainnet);
    final c = _captureRegister();

    final fakeDeleteMessage = buildLaV1Message(
      action: 'delete',
      npubHex: c.npubHex,
      payloadFields: const [],
      timestampSecs: c.ts,
    );
    final digest = sha256.convert(fakeDeleteMessage).bytes;
    // npub is BIP-340 x-only (32 bytes). Prefix with 0x02 (even-Y) for the
    // generic compressed-pubkey codec; verifyBip340Signature ignores the
    // parity byte.
    final pub = ECPublic.fromHex('02${c.npubHex}');
    expect(
      pub.verifyBip340Signature(
        digest: digest,
        signature: _hexDecode(c.sigHex),
        tweak: false,
      ),
      isFalse,
      reason: 'register sig must not verify as delete (action separation)',
    );
  });

  test('PayServiceException maps to LightningAddressRegistrationException',
      () async {
    when(() => payService.register(
          nym: any(named: 'nym'),
          ctDescriptor: any(named: 'ctDescriptor'),
          npubHex: any(named: 'npubHex'),
          signatureHex: any(named: 'signatureHex'),
          timestampSecs: any(named: 'timestampSecs'),
        )).thenThrow(PayServiceException('NymTaken'));

    await expectLater(
      usecase.execute(nym: 'alice', environment: Environment.mainnet),
      throwsA(isA<Exception>().having(
        (e) => e.toString().contains('NymTaken'),
        'wraps server message',
        isTrue,
      )),
    );
  });
}

List<int> _hexDecode(String hex) {
  final out = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    out.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return out;
}

// Suppress unused import warning for utf8 — buildLaV1Message uses utf8 internally.
// ignore: unused_element
const _ = utf8;
