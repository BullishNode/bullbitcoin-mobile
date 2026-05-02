import 'dart:typed_data';

import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_v1_signing.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/value_objects/nym_quota.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/delete_lightning_address_usecase.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPayService extends Mock implements PayServicePort {}

class _MockWalletRepository extends Mock implements WalletRepository {}

class _MockSeedRepository extends Mock implements SeedRepository {}

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

Seed _zeroSeed() {
  final m =
      bip39.Mnemonic.fromSentence(_kZeroMnemonic, bip39.Language.english);
  return Seed.mnemonic(
    mnemonicWords: _kZeroMnemonic.split(' '),
    bytes: Uint8List.fromList(m.seed),
    masterFingerprint: _kFingerprint,
  );
}

List<int> _hexDecode(String hex) => [
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];

void main() {
  late _MockPayService payService;
  late _MockWalletRepository walletRepo;
  late _MockSeedRepository seedRepo;
  late DeleteLightningAddressUsecase usecase;

  setUp(() {
    payService = _MockPayService();
    walletRepo = _MockWalletRepository();
    seedRepo = _MockSeedRepository();
    usecase = DeleteLightningAddressUsecase(
      walletRepository: walletRepo,
      seedRepository: seedRepo,
      payService: payService,
    );

    when(() => walletRepo.getWallets(
          onlyDefaults: any(named: 'onlyDefaults'),
          onlyBitcoin: any(named: 'onlyBitcoin'),
        )).thenAnswer((_) async => [_bitcoinDefault()]);
    when(() => seedRepo.get(any())).thenAnswer((_) async => _zeroSeed());
    when(() => payService.deleteRegistration(
          npubHex: any(named: 'npubHex'),
          signatureHex: any(named: 'signatureHex'),
          timestampSecs: any(named: 'timestampSecs'),
        )).thenAnswer((_) async => const NymQuota(used: 1, cap: 3));
  });

  ({String npubHex, String sigHex, int ts}) _capture() {
    final captured = verify(() => payService.deleteRegistration(
          npubHex: captureAny(named: 'npubHex'),
          signatureHex: captureAny(named: 'signatureHex'),
          timestampSecs: captureAny(named: 'timestampSecs'),
        )).captured;
    return (
      npubHex: captured[0] as String,
      sigHex: captured[1] as String,
      ts: captured[2] as int,
    );
  }

  test('signs the v1 wire format with action=delete and no payload fields',
      () async {
    final before = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    await usecase.execute();
    final after = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final c = _capture();

    expect(c.ts, inInclusiveRange(before, after));

    final message = buildLaV1Message(
      action: 'delete',
      npubHex: c.npubHex,
      payloadFields: const [],
      timestampSecs: c.ts,
    );
    final digest = sha256.convert(message).bytes;
    final pub = ECPublic.fromHex('02${c.npubHex}');
    expect(
      pub.verifyBip340Signature(
        digest: digest,
        signature: _hexDecode(c.sigHex),
        tweak: false,
      ),
      isTrue,
      reason: 'sig must verify against canonical delete v1 message bytes',
    );
  });

  test('a delete sig must not verify against a register-shaped message',
      () async {
    await usecase.execute();
    final c = _capture();

    final fakeRegisterMessage = buildLaV1Message(
      action: 'register',
      npubHex: c.npubHex,
      payloadFields: const ['alice', 'ct(...)'],
      timestampSecs: c.ts,
    );
    final digest = sha256.convert(fakeRegisterMessage).bytes;
    final pub = ECPublic.fromHex('02${c.npubHex}');
    expect(
      pub.verifyBip340Signature(
        digest: digest,
        signature: _hexDecode(c.sigHex),
        tweak: false,
      ),
      isFalse,
    );
  });

  test('PayServiceException maps to LightningAddressRegistrationException',
      () async {
    when(() => payService.deleteRegistration(
          npubHex: any(named: 'npubHex'),
          signatureHex: any(named: 'signatureHex'),
          timestampSecs: any(named: 'timestampSecs'),
        )).thenThrow(PayServiceException('NotFound'));

    await expectLater(
      usecase.execute(),
      throwsA(isA<Exception>().having(
        (e) => e.toString().contains('NotFound'),
        'wraps server message',
        isTrue,
      )),
    );
  });

}
