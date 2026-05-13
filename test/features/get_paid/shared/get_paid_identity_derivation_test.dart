import 'dart:typed_data';

import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/get_paid/shared/get_paid_identity_derivation.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockWalletRepository extends Mock implements WalletRepository {}

class _MockSeedRepository extends Mock implements SeedRepository {}

const _kZeroMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const _kFingerprint = '73c5da0a';
// BIP-85 application 86, identity 1, account 1 from the zero mnemonic seed.
const _kExpectedZeroMnemonicPublicKeyHex =
    'b9c12c506ead6fb1982e4e461f67b0613561c0d76aeec72dc50f71260b78243c';

void main() {
  late _MockWalletRepository walletRepository;
  late _MockSeedRepository seedRepository;
  late GetPaidIdentityDerivation derivation;

  setUp(() {
    walletRepository = _MockWalletRepository();
    seedRepository = _MockSeedRepository();
    derivation = GetPaidIdentityDerivation(
      walletRepository: walletRepository,
      seedRepository: seedRepository,
    );
  });

  test(
    'derives the shared Get Paid Nostr identity from default wallet seed',
    () async {
      final wallet = _bitcoinDefault();
      final seed = _zeroSeed();
      when(
        () =>
            walletRepository.getWallets(onlyDefaults: true, onlyBitcoin: true),
      ).thenAnswer((_) async => [wallet]);
      when(
        () => seedRepository.get(_kFingerprint),
      ).thenAnswer((_) async => seed);

      final handle = await derivation.getSigningHandle();

      expect(handle?.publicKeyHex, _kExpectedZeroMnemonicPublicKeyHex);
      verify(
        () =>
            walletRepository.getWallets(onlyDefaults: true, onlyBitcoin: true),
      ).called(1);
      verify(() => seedRepository.get(_kFingerprint)).called(1);
    },
  );

  test('returns null when default Bitcoin wallet is missing', () async {
    when(
      () => walletRepository.getWallets(onlyDefaults: true, onlyBitcoin: true),
    ).thenAnswer((_) async => []);

    await expectLater(derivation.getSigningHandle(), completion(isNull));
    verifyNever(() => seedRepository.get(any()));
  });
}

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
