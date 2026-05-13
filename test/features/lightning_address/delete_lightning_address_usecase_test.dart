import 'dart:typed_data';

import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/value_objects/nym_quota.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/delete_lightning_address_usecase.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
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
  final m = bip39.Mnemonic.fromSentence(_kZeroMnemonic, bip39.Language.english);
  return Seed.mnemonic(
    mnemonicWords: _kZeroMnemonic.split(' '),
    bytes: Uint8List.fromList(m.seed),
    masterFingerprint: _kFingerprint,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(NostrKeychainHandle.fromSecretKeyHex('01' * 32));
  });

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

    when(
      () => walletRepo.getWallets(
        onlyDefaults: any(named: 'onlyDefaults'),
        onlyBitcoin: any(named: 'onlyBitcoin'),
      ),
    ).thenAnswer((_) async => [_bitcoinDefault()]);
    when(() => seedRepo.get(any())).thenAnswer((_) async => _zeroSeed());
    when(
      () => payService.deleteRegistration(
        nym: any(named: 'nym'),
        handle: any(named: 'handle'),
      ),
    ).thenAnswer((_) async => const NymQuota(used: 1, cap: 3));
  });

  ({String nym, NostrKeychainHandle handle}) captureDelete() {
    final captured = verify(
      () => payService.deleteRegistration(
        nym: captureAny(named: 'nym'),
        handle: captureAny(named: 'handle'),
      ),
    ).captured;
    return (
      nym: captured[0] as String,
      handle: captured[1] as NostrKeychainHandle,
    );
  }

  test('passes nym and derived Nostr handle to the pay service', () async {
    await usecase.execute(nym: 'alice');
    final c = captureDelete();

    expect(c.nym, 'alice');
    expect(c.handle.publicKeyHex, hasLength(64));
  });

  test(
    'PayServiceException maps to LightningAddressRegistrationException',
    () async {
      when(
        () => payService.deleteRegistration(
          nym: any(named: 'nym'),
          handle: any(named: 'handle'),
        ),
      ).thenThrow(PayServiceException('NotFound'));

      await expectLater(
        usecase.execute(nym: 'alice'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString().contains('NotFound'),
            'wraps server message',
            isTrue,
          ),
        ),
      );
    },
  );
}
