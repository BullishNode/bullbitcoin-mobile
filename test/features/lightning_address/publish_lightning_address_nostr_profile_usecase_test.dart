import 'dart:typed_data';

import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_errors.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/nostr_publish_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/publish_lightning_address_nostr_profile_usecase.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockNostrPublish extends Mock implements NostrPublishPort {}

class _MockWalletRepository extends Mock implements WalletRepository {}

class _MockSeedRepository extends Mock implements SeedRepository {}

const _kZeroMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const _kFingerprint = '73c5da0a';
const _kExpectedNip05PublicKeyHex =
    'bb2823fcf6f9187227c5ed4f89730228e32412ca89e9b96a2c190bddb9e525ea';

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
  late _MockNostrPublish nostrPublish;
  late _MockWalletRepository walletRepo;
  late _MockSeedRepository seedRepo;
  late PublishLightningAddressNostrProfileUsecase usecase;

  setUp(() {
    nostrPublish = _MockNostrPublish();
    walletRepo = _MockWalletRepository();
    seedRepo = _MockSeedRepository();
    usecase = PublishLightningAddressNostrProfileUsecase(
      walletRepository: walletRepo,
      seedRepository: seedRepo,
      nostrPublish: nostrPublish,
    );

    when(
      () => walletRepo.getWallets(
        onlyDefaults: any(named: 'onlyDefaults'),
        onlyBitcoin: any(named: 'onlyBitcoin'),
      ),
    ).thenAnswer((_) async => [_bitcoinDefault()]);
    when(() => seedRepo.get(any())).thenAnswer((_) async => _zeroSeed());
    when(
      () => nostrPublish.publishProfile(
        handle: any(named: 'handle'),
        name: any(named: 'name'),
        nip05: any(named: 'nip05'),
        lud16: any(named: 'lud16'),
      ),
    ).thenAnswer((_) async {});
  });

  setUpAll(() {
    registerFallbackValue(NostrKeychainHandle.fromSecretKeyHex('01' * 32));
  });

  test('calls port with name=nym, nip05=lud16=nym@bullpay.ca', () async {
    await usecase.execute(nym: 'alice');

    final captured = verify(
      () => nostrPublish.publishProfile(
        handle: captureAny(named: 'handle'),
        name: captureAny(named: 'name'),
        nip05: captureAny(named: 'nip05'),
        lud16: captureAny(named: 'lud16'),
      ),
    ).captured;
    expect(captured[1], 'alice');
    expect(captured[2], 'alice@bullpay.ca');
    expect(captured[3], 'alice@bullpay.ca');
    final handle = captured[0] as NostrKeychainHandle;
    expect(handle.publicKeyHex, _kExpectedNip05PublicKeyHex);
  });

  test(
    'port throws → propagates as LightningAddressNostrPublishFailedException',
    () async {
      when(
        () => nostrPublish.publishProfile(
          handle: any(named: 'handle'),
          name: any(named: 'name'),
          nip05: any(named: 'nip05'),
          lud16: any(named: 'lud16'),
        ),
      ).thenThrow(
        LightningAddressNostrPublishFailedException('all relays unreachable'),
      );

      await expectLater(
        usecase.execute(nym: 'alice'),
        throwsA(isA<LightningAddressNostrPublishFailedException>()),
      );
    },
  );

  test(
    'non-publish dependency error wraps into the publish exception',
    () async {
      when(
        () => walletRepo.getWallets(
          onlyDefaults: any(named: 'onlyDefaults'),
          onlyBitcoin: any(named: 'onlyBitcoin'),
        ),
      ).thenThrow(StateError('wallet repo blew up'));

      await expectLater(
        usecase.execute(nym: 'alice'),
        throwsA(isA<LightningAddressNostrPublishFailedException>()),
      );
    },
  );
}
