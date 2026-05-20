import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/bip85_derivation_path.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_network.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_origin.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_wallet_type.dart';
import 'package:bb_mobile/features/wallet_manifest/interface_adapters/wallet_manifest_origin_datasource.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SqliteDatabase sqlite;
  late WalletManifestOriginDatasource datasource;

  setUp(() {
    sqlite = SqliteDatabase(NativeDatabase.memory());
    datasource = WalletManifestOriginDatasource(sqlite: sqlite);
  });

  tearDown(() async {
    await sqlite.close();
  });

  test('stores and fetches wallet origins', () async {
    final origin = WalletManifestOrigin(
      walletId: 'wallet-lbtc',
      rootFingerprint: 'ABCD1234',
      bip85DerivationPath: Bip85DerivationPath.mnemonic12(index: 76),
      network: WalletManifestNetwork.liquid,
      createdAt: 100,
      updatedAt: 100,
    );

    await datasource.upsert(origin);

    final origins = await datasource.fetchAll();
    expect(origins, hasLength(1));
    expect(origins.single.walletId, 'wallet-lbtc');
    expect(origins.single.rootFingerprint, 'abcd1234');
    expect(
      origins.single.bip85DerivationPath.value,
      "m/83696968'/39'/0'/12'/76'",
    );
    expect(origins.single.network, WalletManifestNetwork.liquid);
    expect(origins.single.walletType, WalletManifestWalletType.paymentPage);
  });

  test('supports BTC and LBTC wallet origins at the same BIP85 path', () async {
    final path = Bip85DerivationPath.mnemonic12(index: 77);

    await datasource.upsert(
      WalletManifestOrigin(
        walletId: 'btcpay-lbtc',
        rootFingerprint: 'abcd1234',
        bip85DerivationPath: path,
        network: WalletManifestNetwork.liquid,
        createdAt: 100,
        updatedAt: 100,
      ),
    );
    await datasource.upsert(
      WalletManifestOrigin(
        walletId: 'btcpay-btc',
        rootFingerprint: 'abcd1234',
        bip85DerivationPath: path,
        network: WalletManifestNetwork.bitcoin,
        createdAt: 101,
        updatedAt: 101,
      ),
    );

    final origins = await datasource.fetchAll();

    expect(origins.map((origin) => origin.walletId).toSet(), {
      'btcpay-lbtc',
      'btcpay-btc',
    });
    expect(origins.map((origin) => origin.identity).toSet(), hasLength(2));
  });

  test('re-points duplicate manifest identity to the latest wallet', () async {
    final path = Bip85DerivationPath.mnemonic12(index: 77);
    final first = WalletManifestOrigin(
      walletId: 'btcpay-lbtc',
      rootFingerprint: 'abcd1234',
      bip85DerivationPath: path,
      network: WalletManifestNetwork.liquid,
      createdAt: 100,
      updatedAt: 100,
    );
    final duplicateIdentity = WalletManifestOrigin(
      walletId: 'other-wallet',
      rootFingerprint: 'abcd1234',
      bip85DerivationPath: path,
      network: WalletManifestNetwork.liquid,
      createdAt: 101,
      updatedAt: 101,
    );

    await datasource.upsert(first);
    await datasource.upsert(duplicateIdentity);

    final origins = await datasource.fetchAll();
    expect(origins, hasLength(1));
    expect(origins.single.walletId, 'other-wallet');
    expect(origins.single.identity, first.identity);
  });
}
