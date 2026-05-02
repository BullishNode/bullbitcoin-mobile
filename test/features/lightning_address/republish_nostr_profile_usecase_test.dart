import 'dart:typed_data';

import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/nostr/nostr_relay_client.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/lightning_address/domain/entities/lookup_result.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_errors.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/nostr_publish_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/republish_nostr_profile_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/value_objects/nym_quota.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
// ignore: unused_import
import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPayService extends Mock implements PayServicePort {}

class _MockNostrPublish extends Mock implements NostrPublishPort {}

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
  final m = bip39.Mnemonic.fromSentence(_kZeroMnemonic, bip39.Language.english);
  return Seed.mnemonic(
    mnemonicWords: _kZeroMnemonic.split(' '),
    bytes: Uint8List.fromList(m.seed),
    masterFingerprint: _kFingerprint,
  );
}

void main() {
  late _MockPayService payService;
  late _MockWalletRepository walletRepo;
  late _MockSeedRepository seedRepo;
  late _MockNostrPublish nostrPublish;
  late RepublishNostrProfileUsecase usecase;

  setUp(() {
    payService = _MockPayService();
    walletRepo = _MockWalletRepository();
    seedRepo = _MockSeedRepository();
    nostrPublish = _MockNostrPublish();
    usecase = RepublishNostrProfileUsecase(
      walletRepository: walletRepo,
      seedRepository: seedRepo,
      payService: payService,
      nostrPublish: nostrPublish,
    );

    when(() => walletRepo.getWallets(
          onlyDefaults: any(named: 'onlyDefaults'),
          onlyBitcoin: any(named: 'onlyBitcoin'),
        )).thenAnswer((_) async => [_bitcoinDefault()]);
    when(() => seedRepo.get(any())).thenAnswer((_) async => _zeroSeed());
    when(() => nostrPublish.publishProfile(
          privateKeyHex: any(named: 'privateKeyHex'),
          name: any(named: 'name'),
          nip05: any(named: 'nip05'),
          lud16: any(named: 'lud16'),
        )).thenAnswer((_) async {});
    when(() => nostrPublish.clearProfile(
        privateKeyHex: any(named: 'privateKeyHex'))).thenAnswer((_) async {});
  });

  test('Active lookup → publishes profile with nym fields', () async {
    when(() => payService.lookupByNpub(any())).thenAnswer(
      (_) async => const ActiveLookupResult(
        nym: 'alice',
        quota: NymQuota(used: 1, cap: 3),
      ),
    );

    await usecase.execute();

    final captured = verify(() => nostrPublish.publishProfile(
          privateKeyHex: any(named: 'privateKeyHex'),
          name: captureAny(named: 'name'),
          nip05: captureAny(named: 'nip05'),
          lud16: captureAny(named: 'lud16'),
        )).captured;
    expect(captured[0], 'alice');
    expect(captured[1], 'alice@bullpay.ca');
    expect(captured[2], 'alice@bullpay.ca');
    verifyNever(() =>
        nostrPublish.clearProfile(privateKeyHex: any(named: 'privateKeyHex')));
  });

  test('Inactive lookup → clears profile', () async {
    when(() => payService.lookupByNpub(any())).thenAnswer(
      (_) async => const InactiveLookupResult(
        nym: 'alice',
        quota: NymQuota(used: 1, cap: 3),
      ),
    );

    await usecase.execute();

    verify(() => nostrPublish.clearProfile(
        privateKeyHex: any(named: 'privateKeyHex'))).called(1);
    verifyNever(() => nostrPublish.publishProfile(
          privateKeyHex: any(named: 'privateKeyHex'),
          name: any(named: 'name'),
          nip05: any(named: 'nip05'),
          lud16: any(named: 'lud16'),
        ));
  });

  test('null lookup (npub never registered) → clears profile', () async {
    when(() => payService.lookupByNpub(any())).thenAnswer((_) async => null);

    await usecase.execute();

    verify(() => nostrPublish.clearProfile(
        privateKeyHex: any(named: 'privateKeyHex'))).called(1);
  });

  test(
      'NostrPublishFailedException is rethrown as '
      'LightningAddressNostrPublishFailedException', () async {
    when(() => payService.lookupByNpub(any())).thenAnswer(
      (_) async => const ActiveLookupResult(
        nym: 'alice',
        quota: NymQuota(used: 1, cap: 3),
      ),
    );
    when(() => nostrPublish.publishProfile(
          privateKeyHex: any(named: 'privateKeyHex'),
          name: any(named: 'name'),
          nip05: any(named: 'nip05'),
          lud16: any(named: 'lud16'),
        )).thenThrow(NostrPublishFailedException('all relays unreachable'));

    await expectLater(
      usecase.execute(),
      throwsA(isA<LightningAddressNostrPublishFailedException>()),
    );
  });
}
