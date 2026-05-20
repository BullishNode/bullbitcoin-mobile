import 'dart:typed_data';

import 'package:bb_mobile/core/bip85/data/bip85_repository.dart';
import 'package:bb_mobile/core/bip85/domain/bip85_derivation_entity.dart';
import 'package:bb_mobile/core/bip85/domain/derive_next_bip85_mnemonic_from_default_wallet_usecase.dart';
import 'package:bb_mobile/core/bip85/domain/bip85_manual_index_reservations.dart';
import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBip85Repository extends Mock implements Bip85Repository {}

class _MockWalletRepository extends Mock implements WalletRepository {}

class _MockSeedRepository extends Mock implements SeedRepository {}

const _kMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const _kFingerprint = '73c5da0a';

MnemonicSeed _seed() {
  final mnemonic = bip39.Mnemonic.fromSentence(
    _kMnemonic,
    bip39.Language.english,
  );
  return Seed.mnemonic(
        mnemonicWords: _kMnemonic.split(' '),
        bytes: Uint8List.fromList(mnemonic.seed),
        masterFingerprint: _kFingerprint,
      )
      as MnemonicSeed;
}

Wallet _defaultBitcoinWallet() => Wallet(
  origin: 'default-bitcoin',
  network: Network.bitcoinMainnet,
  isDefault: true,
  masterFingerprint: _kFingerprint,
  xpubFingerprint: _kFingerprint,
  scriptType: ScriptType.bip84,
  xpub: 'xpub',
  externalPublicDescriptor: 'wpkh(xpub/0/*)',
  internalPublicDescriptor: 'wpkh(xpub/1/*)',
  signer: SignerEntity.local,
  signerDevice: null,
  balanceSat: BigInt.zero,
);

void main() {
  setUpAll(() {
    registerFallbackValue(Bip85Application.bip39);
    registerFallbackValue(Bip85Usage.manual);
    registerFallbackValue(bip39.MnemonicLength.words12);
  });

  test(
    'manual mnemonic auto-indexing skips reserved Get Paid indexes',
    () async {
      final bip85Repository = _MockBip85Repository();
      final walletRepository = _MockWalletRepository();
      final seedRepository = _MockSeedRepository();
      final seed = _seed();
      final mnemonic = bip39.Mnemonic.fromSentence(
        _kMnemonic,
        bip39.Language.english,
      );
      final usecase = DeriveNextBip85MnemonicFromDefaultWalletUsecase(
        bip85Repository: bip85Repository,
        walletRepository: walletRepository,
        seedRepository: seedRepository,
      );

      when(
        () =>
            walletRepository.getWallets(onlyDefaults: true, onlyBitcoin: true),
      ).thenAnswer((_) async => [_defaultBitcoinWallet()]);
      when(
        () => seedRepository.get(_kFingerprint),
      ).thenAnswer((_) async => seed);
      when(
        () => bip85Repository.fetchNextIndexForApplication(
          application: Bip85Application.bip39,
          xprvBase58: any(named: 'xprvBase58'),
          excludedIndexes: Bip85ManualIndexReservations.unavailable,
          usage: Bip85Usage.manual,
        ),
      ).thenAnswer((_) async => 78);
      when(
        () => bip85Repository.deriveMnemonic(
          xprvBase58: any(named: 'xprvBase58'),
          length: bip39.MnemonicLength.words12,
          index: 78,
          alias: null,
        ),
      ).thenAnswer(
        (_) async => (derivation: "39'/0'/12'/78'", mnemonic: mnemonic),
      );

      final result = await usecase.execute();

      expect(result.derivation, "39'/0'/12'/78'");
      verify(
        () => bip85Repository.fetchNextIndexForApplication(
          application: Bip85Application.bip39,
          xprvBase58: any(named: 'xprvBase58'),
          excludedIndexes: Bip85ManualIndexReservations.unavailable,
          usage: Bip85Usage.manual,
        ),
      ).called(1);
    },
  );
}
