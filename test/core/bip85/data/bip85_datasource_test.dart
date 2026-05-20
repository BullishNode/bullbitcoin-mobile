import 'dart:typed_data';

import 'package:bb_mobile/core/bip85/data/bip85_datasource.dart';
import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/core/storage/tables/bip85_derivations_table.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bip32_keys/bip32_keys.dart' as bip32;
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:convert/convert.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _zeroMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

void main() {
  late SqliteDatabase sqlite;
  late Bip85Datasource datasource;

  setUp(() {
    sqlite = SqliteDatabase(NativeDatabase.memory());
    datasource = Bip85Datasource(sqlite: sqlite);
  });

  tearDown(() async {
    await sqlite.close();
  });

  test('next index returns the lowest free non-reserved gap', () async {
    final xprv = _zeroMnemonicXprv();
    final fingerprint = _fingerprintFromXprv(xprv);

    await datasource.recordMnemonicDerivation(
      xprvBase58: xprv,
      derivationPath: "39'/0'/12'/0'",
      usage: Bip85UsageColumn.manual,
    );
    await datasource.recordMnemonicDerivation(
      xprvBase58: xprv,
      derivationPath: "39'/0'/12'/75'",
      usage: Bip85UsageColumn.manual,
    );

    final nextIndex = await datasource.fetchNextIndexForApplication(
      Bip85ApplicationColumn.bip39,
      fingerprint,
      excludedIndexes: const {75, 76, 77},
      usage: Bip85UsageColumn.manual,
    );

    expect(nextIndex, 1);
  });

  test('record mnemonic derivation preserves existing rows', () async {
    final xprv = _zeroMnemonicXprv();
    final fingerprint = _fingerprintFromXprv(xprv);

    await datasource.recordMnemonicDerivation(
      xprvBase58: xprv,
      derivationPath: "39'/0'/12'/75'",
      alias: 'Manual',
      usage: Bip85UsageColumn.manual,
    );
    await datasource.recordMnemonicDerivation(
      xprvBase58: xprv,
      derivationPath: "39'/0'/12'/75'",
      alias: 'System',
      usage: Bip85UsageColumn.system,
    );

    final row = await datasource.fetch(
      xprvFingerprint: fingerprint,
      path: "39'/0'/12'/75'",
    );

    expect(row?.alias, 'Manual');
    expect(row?.usage, Bip85UsageColumn.manual);
  });
}

String _zeroMnemonicXprv() {
  final mnemonic = bip39.Mnemonic.fromSentence(
    _zeroMnemonic,
    bip39.Language.english,
  );
  return Bip32Derivation.getXprvFromSeed(
    Uint8List.fromList(mnemonic.seed),
    Network.bitcoinMainnet,
  );
}

String _fingerprintFromXprv(String xprvBase58) {
  return hex.encode(bip32.Bip32Keys.fromBase58(xprvBase58).fingerprint);
}
