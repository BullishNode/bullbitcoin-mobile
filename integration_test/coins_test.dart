import 'dart:io';

import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/core/wallet/data/datasources/frozen_wallet_utxo_datasource.dart';
import 'package:bb_mobile/core/wallet/domain/repositories/wallet_utxo_repository.dart';
import 'package:bb_mobile/locator.dart';
import 'package:bb_mobile/main.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

// Integration tests for the Coins / UTXO view + freeze (issue #760).
//
// Covers the §7.1 acceptance criteria:
//   1. Freeze persists across restart — freeze an outpoint, re-init the
//      locator/SqliteDatabase, the outpoint is still frozen. Funds-free: this
//      is the load-bearing persistence guarantee and runs anywhere.
//   2. Funded live-testnet enforcement lives in
//      coins_funded_testnet_test.dart and is run explicitly via
//      `make coins-funded-testnet-test`; that lane fails fast when the funded
//      TEST_ALICE_MNEMONIC fixture is absent or unfunded instead of skipping.
//
// Run via `make integration-test` (auto-aggregated by tools/gen_all_test.dart).
Future<void> main({bool isInitialized = false}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!isInitialized) await Bull.init();

  final frozenDatasource = locator<FrozenWalletUtxoDatasource>();
  final utxoRepository = locator<WalletUtxoRepository>();

  group('Coins / freeze persistence (funds-free)', () {
    const walletId = 'coins-integration-test-wallet';
    const outpoint = (
      txId: '0000000000000000000000000000000000000000000000000000000000000001',
      vout: 0,
    );

    Future<void> clear() async {
      await frozenDatasource.unfreezeOutpoints(
        walletId: walletId,
        outpoints: [outpoint],
      );
    }

    setUp(clear);
    tearDown(clear);

    test('freeze is durable across a database restart', () async {
      // Use a dedicated on-disk database, fully isolated from the locator's
      // shared SqliteDatabase singleton. Closing that singleton (the previous
      // approach) killed the connection for every other test in the aggregated
      // integration run. Here: write through one handle, close it, then reopen
      // a SECOND handle on the SAME file — a fresh connection only sees
      // committed-to-disk rows, which is exactly what "survives a restart"
      // means.
      // This test deliberately opens a second SqliteDatabase on the same file
      // to simulate a restart, on top of the locator's existing singleton.
      // Drift's "multiple databases" warning targets instances SHARING a
      // QueryExecutor (a real race) — not our case: `before` and `after` use
      // separate NativeDatabase executors and never overlap. Silence the
      // debug-only false positive for the duration of this test only, so the
      // warning still guards genuine misuse in the rest of the run.
      final previousWarnFlag =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(
        () => driftRuntimeOptions.dontWarnAboutMultipleDatabases =
            previousWarnFlag,
      );

      final dir = await Directory.systemTemp.createTemp('coins_restart');
      addTearDown(() => dir.delete(recursive: true));
      final dbFile = File('${dir.path}/restart.sqlite');

      final before = SqliteDatabase(NativeDatabase(dbFile));
      await FrozenWalletUtxoDatasource(
        db: before,
      ).freezeOutpoints(walletId: walletId, outpoints: [outpoint]);
      await before.close();

      final after = SqliteDatabase(NativeDatabase(dbFile));
      addTearDown(after.close);
      final afterRestart = await FrozenWalletUtxoDatasource(
        db: after,
      ).getFrozenOutpoints(walletId: walletId);

      expect(
        afterRestart,
        contains(outpoint),
        reason: 'a user-frozen outpoint must persist across an app restart',
      );
    });

    test('unfreeze removes the freeze row', () async {
      await utxoRepository.freezeUtxos(
        walletId: walletId,
        outpoints: [outpoint],
      );
      await utxoRepository.unfreezeUtxos(
        walletId: walletId,
        outpoints: [outpoint],
      );

      // Freeze is matched by outpoint across all wallets — the global set must
      // no longer carry it after unfreeze.
      final remaining = await utxoRepository.getAllFrozenOutpoints();
      expect(remaining, isNot(contains(outpoint)));
    });
  });
}
