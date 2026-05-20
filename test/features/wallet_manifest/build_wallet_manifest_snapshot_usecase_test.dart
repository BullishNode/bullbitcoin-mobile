import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallets_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/build_wallet_manifest_snapshot_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/fetch_wallet_manifest_origins_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/bip85_derivation_path.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_network.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_origin.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_wallet_type.dart';
import 'package:bb_mobile/features/wallet_manifest/wallet_manifest_errors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockFetchOrigins extends Mock
    implements FetchWalletManifestOriginsUsecase {}

class _MockGetWallets extends Mock implements GetWalletsUsecase {}

void main() {
  test('builds a local snapshot from origins and current wallets', () async {
    final fetchOrigins = _MockFetchOrigins();
    final getWallets = _MockGetWallets();
    final usecase = BuildWalletManifestSnapshotUsecase(
      fetchOrigins: fetchOrigins,
      getWallets: getWallets,
    );

    when(() => fetchOrigins.execute()).thenAnswer(
      (_) async => [
        _origin(
          walletId: 'la-wallet',
          index: 75,
          network: WalletManifestNetwork.liquid,
          updatedAt: 101,
        ),
        _origin(
          walletId: 'payment-page-wallet',
          index: 76,
          network: WalletManifestNetwork.liquid,
          updatedAt: 102,
        ),
        _origin(
          walletId: 'btcpay-btc-wallet',
          index: 77,
          network: WalletManifestNetwork.bitcoin,
          updatedAt: 103,
        ),
      ],
    );
    when(() => getWallets.execute(allEnvironments: true)).thenAnswer(
      (_) async => [
        _wallet(
          id: 'la-wallet',
          label: 'Renamed Lightning Address',
          network: Network.liquidMainnet,
          externalDescriptor: 'ct(slip77(...),elwpkh([abcd1234]xpub/0/*))',
          internalDescriptor: 'ct(slip77(...),elwpkh([abcd1234]xpub/1/*))',
        ),
        _wallet(
          id: 'payment-page-wallet',
          label: 'Payment Page-LBTC',
          network: Network.liquidMainnet,
        ),
        _wallet(
          id: 'btcpay-btc-wallet',
          label: 'BTCPay BTC',
          network: Network.bitcoinMainnet,
        ),
      ],
    );

    final snapshot = await usecase.execute(
      now: DateTime.fromMillisecondsSinceEpoch(200000),
    );

    expect(snapshot.createdAt, 200);
    expect(snapshot.accounts, hasLength(3));
    final account = snapshot.accounts.first;
    expect(account.rootFingerprint, 'abcd1234');
    expect(account.bip85Index, 75);
    expect(account.network, WalletManifestNetwork.liquid);
    expect(account.walletType, WalletManifestWalletType.lightningAddress);
    expect(account.name, 'Renamed Lightning Address');
    expect(account.descriptor, isNull);
    expect(account.changeDescriptor, isNull);
    expect(account.timestamp, 101);
  });

  test('does not load wallets when there are no origins', () async {
    final fetchOrigins = _MockFetchOrigins();
    final getWallets = _MockGetWallets();
    final usecase = BuildWalletManifestSnapshotUsecase(
      fetchOrigins: fetchOrigins,
      getWallets: getWallets,
    );
    when(() => fetchOrigins.execute()).thenAnswer((_) async => []);

    final snapshot = await usecase.execute(
      now: DateTime.fromMillisecondsSinceEpoch(300000),
    );

    expect(snapshot.createdAt, 300);
    expect(snapshot.accounts, isEmpty);
    verifyNever(() => getWallets.execute(allEnvironments: true));
  });

  test('filters accounts by root fingerprint when requested', () async {
    final fetchOrigins = _MockFetchOrigins();
    final getWallets = _MockGetWallets();
    final usecase = BuildWalletManifestSnapshotUsecase(
      fetchOrigins: fetchOrigins,
      getWallets: getWallets,
    );
    when(() => fetchOrigins.execute()).thenAnswer(
      (_) async => [
        _origin(
          walletId: 'active-root-wallet',
          index: 76,
          network: WalletManifestNetwork.liquid,
          rootFingerprint: 'abcd1234',
        ),
        _origin(
          walletId: 'other-root-wallet',
          index: 77,
          network: WalletManifestNetwork.liquid,
          rootFingerprint: 'ffffeeee',
        ),
      ],
    );
    when(() => getWallets.execute(allEnvironments: true)).thenAnswer(
      (_) async => [
        _wallet(
          id: 'active-root-wallet',
          label: 'Payment Page-LBTC',
          network: Network.liquidMainnet,
        ),
        _wallet(
          id: 'other-root-wallet',
          label: 'Other Root',
          network: Network.liquidMainnet,
        ),
      ],
    );

    final snapshot = await usecase.execute(rootFingerprint: 'ABCD1234');

    expect(snapshot.accounts, hasLength(1));
    expect(snapshot.accounts.single.rootFingerprint, 'abcd1234');
    expect(snapshot.accounts.single.name, 'Payment Page-LBTC');
  });

  test('wraps wallet loading failures in a snapshot build exception', () async {
    final fetchOrigins = _MockFetchOrigins();
    final getWallets = _MockGetWallets();
    final usecase = BuildWalletManifestSnapshotUsecase(
      fetchOrigins: fetchOrigins,
      getWallets: getWallets,
    );
    when(() => fetchOrigins.execute()).thenAnswer(
      (_) async => [
        _origin(
          walletId: 'wallet',
          index: 1,
          network: WalletManifestNetwork.liquid,
        ),
      ],
    );
    when(
      () => getWallets.execute(allEnvironments: true),
    ).thenThrow(Exception('wallet db failed'));

    await expectLater(
      usecase.execute(),
      throwsA(isA<WalletManifestSnapshotBuildException>()),
    );
  });

  test('skips stale origins when the origin wallet is missing', () async {
    final fetchOrigins = _MockFetchOrigins();
    final getWallets = _MockGetWallets();
    final usecase = BuildWalletManifestSnapshotUsecase(
      fetchOrigins: fetchOrigins,
      getWallets: getWallets,
    );
    when(() => fetchOrigins.execute()).thenAnswer(
      (_) async => [
        _origin(
          walletId: 'missing-wallet',
          index: 76,
          network: WalletManifestNetwork.liquid,
        ),
      ],
    );
    when(
      () => getWallets.execute(allEnvironments: true),
    ).thenAnswer((_) async => []);

    final snapshot = await usecase.execute();

    expect(snapshot.accounts, isEmpty);
  });

  test('fails closed when an origin network mismatches the wallet', () async {
    final fetchOrigins = _MockFetchOrigins();
    final getWallets = _MockGetWallets();
    final usecase = BuildWalletManifestSnapshotUsecase(
      fetchOrigins: fetchOrigins,
      getWallets: getWallets,
    );
    when(() => fetchOrigins.execute()).thenAnswer(
      (_) async => [
        _origin(
          walletId: 'wallet',
          index: 77,
          network: WalletManifestNetwork.bitcoin,
        ),
      ],
    );
    when(() => getWallets.execute(allEnvironments: true)).thenAnswer(
      (_) async => [
        _wallet(
          id: 'wallet',
          label: 'BTCPay Liquid',
          network: Network.liquidMainnet,
        ),
      ],
    );

    await expectLater(
      usecase.execute(),
      throwsA(isA<WalletManifestSnapshotBuildException>()),
    );
  });
}

WalletManifestOrigin _origin({
  required String walletId,
  required int index,
  required WalletManifestNetwork network,
  String rootFingerprint = 'ABCD1234',
  int updatedAt = 100,
}) {
  return WalletManifestOrigin(
    walletId: walletId,
    rootFingerprint: rootFingerprint,
    bip85DerivationPath: Bip85DerivationPath.mnemonic12(index: index),
    network: network,
    createdAt: 100,
    updatedAt: updatedAt,
  );
}

Wallet _wallet({
  required String id,
  required String label,
  required Network network,
  String externalDescriptor = 'external',
  String internalDescriptor = 'internal',
}) {
  return Wallet(
    origin: id,
    label: label,
    network: network,
    xpubFingerprint: 'abcd1234',
    scriptType: ScriptType.bip84,
    xpub: 'xpub',
    externalPublicDescriptor: externalDescriptor,
    internalPublicDescriptor: internalDescriptor,
    signer: SignerEntity.local,
    signerDevice: null,
    balanceSat: BigInt.zero,
  );
}
