import 'package:bb_mobile/features/wallet_manifest/application/ports/wallet_manifest_origin_store.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/record_wallet_manifest_origin_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/bip85_derivation_path.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_network.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_origin.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_wallet_type.dart';
import 'package:bb_mobile/features/wallet_manifest/wallet_manifest_errors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockOriginStore extends Mock implements WalletManifestOriginStore {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      WalletManifestOrigin(
        walletId: 'wallet',
        rootFingerprint: 'abcd1234',
        bip85DerivationPath: Bip85DerivationPath.mnemonic12(index: 75),
        network: WalletManifestNetwork.liquid,
        createdAt: 0,
        updatedAt: 0,
      ),
    );
  });

  test('records a typed origin after local wallet creation', () async {
    final store = _MockOriginStore();
    final usecase = RecordWalletManifestOriginUsecase(originStore: store);
    when(() => store.upsert(any())).thenAnswer((_) async {});

    await usecase.execute(
      walletId: 'payment-page-wallet',
      network: WalletManifestNetwork.liquid,
      rootFingerprint: 'ABCD1234',
      bip85DerivationPath: "m/83696968'/39'/0'/12'/76'",
      now: DateTime.fromMillisecondsSinceEpoch(100000),
    );

    final origin =
        verify(() => store.upsert(captureAny())).captured.single
            as WalletManifestOrigin;
    expect(origin.walletId, 'payment-page-wallet');
    expect(origin.rootFingerprint, 'abcd1234');
    expect(origin.network, WalletManifestNetwork.liquid);
    expect(origin.bip85Index, 76);
    expect(origin.walletType, WalletManifestWalletType.paymentPage);
    expect(origin.createdAt, 100);
    expect(origin.updatedAt, 100);
  });

  test('wraps persistence failures in a typed exception', () async {
    final store = _MockOriginStore();
    final usecase = RecordWalletManifestOriginUsecase(originStore: store);
    when(() => store.upsert(any())).thenThrow(Exception('db locked'));

    await expectLater(
      usecase.execute(
        walletId: 'wallet',
        network: WalletManifestNetwork.bitcoin,
        rootFingerprint: 'abcd1234',
        bip85DerivationPath: "m/83696968'/39'/0'/12'/77'",
      ),
      throwsA(isA<WalletManifestOriginPersistenceException>()),
    );
  });

  test('rejects unsupported BIP85 derivation paths before storage', () async {
    final store = _MockOriginStore();
    final usecase = RecordWalletManifestOriginUsecase(originStore: store);

    await expectLater(
      usecase.execute(
        walletId: 'wallet',
        network: WalletManifestNetwork.liquid,
        rootFingerprint: 'abcd1234',
        bip85DerivationPath: "m/83696968'/2'/0'",
      ),
      throwsA(isA<WalletManifestInvalidOriginException>()),
    );
    verifyNever(() => store.upsert(any()));
  });

  test('maps invalid origin fields to a typed validation exception', () async {
    final store = _MockOriginStore();
    final usecase = RecordWalletManifestOriginUsecase(originStore: store);

    await expectLater(
      usecase.execute(
        walletId: '   ',
        network: WalletManifestNetwork.liquid,
        rootFingerprint: 'abcd1234',
        bip85DerivationPath: "m/83696968'/39'/0'/12'/76'",
      ),
      throwsA(isA<WalletManifestInvalidOriginException>()),
    );
    verifyNever(() => store.upsert(any()));
  });
}
