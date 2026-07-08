import 'dart:io';

import 'package:bb_mobile/core/fees/domain/fees_entity.dart';
import 'package:bb_mobile/core/seed/data/models/seed_model.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/datasources/bdk_wallet_datasource.dart'
    show NoSpendableUtxoException;
import 'package:bb_mobile/core/wallet/data/repositories/wallet_address_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet_utxo.dart';
import 'package:bb_mobile/core/wallet/domain/repositories/wallet_utxo_repository.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/prepare_bitcoin_send_usecase.dart';
import 'package:bb_mobile/features/settings/domain/usecases/set_environment_usecase.dart';
import 'package:bb_mobile/locator.dart';
import 'package:bb_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';

// Live funded-testnet Coins / UTXO checks for issue #760.
//
// This file is deliberately excluded from the default single-process aggregate:
// it needs TEST_ALICE_MNEMONIC with spendable bitcoin testnet UTXOs. Run it
// explicitly via `make coins-funded-testnet-test`. Missing or unfunded fixtures
// are hard failures, not skips, so CI cannot silently lose this coverage.
Future<void> main({bool isInitialized = false}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!isInitialized) await Bull.init();

  group('Coins / freeze enforcement (funded testnet)', () {
    late final WalletRepository walletRepository;
    late final WalletAddressRepository addressRepository;
    late final WalletUtxoRepository utxoRepository;
    late final PrepareBitcoinSendUsecase prepareBitcoinSendUsecase;
    late Wallet wallet;

    setUpAll(() async {
      final mnemonic = Platform.environment['TEST_ALICE_MNEMONIC'];
      if (mnemonic == null || mnemonic.isEmpty) {
        throw StateError(
          'TEST_ALICE_MNEMONIC is required for coins-funded-testnet-test',
        );
      }

      walletRepository = locator<WalletRepository>();
      addressRepository = locator<WalletAddressRepository>();
      utxoRepository = locator<WalletUtxoRepository>();
      prepareBitcoinSendUsecase = locator<PrepareBitcoinSendUsecase>();

      await locator<SetEnvironmentUsecase>().execute(Environment.testnet);
      final seed = SeedModel.mnemonic(
        mnemonicWords: mnemonic.split(' '),
      ).toEntity();
      wallet = await walletRepository.createWallet(
        seed: seed,
        network: Network.bitcoinTestnet,
        scriptType: ScriptType.bip84,
      );
      await walletRepository.getWallets(sync: true);
    });

    // Restore the shared app environment so this explicit lane never leaves the
    // process on testnet if more tests are appended later.
    tearDownAll(
      () => locator<SetEnvironmentUsecase>().execute(Environment.mainnet),
    );

    Future<List<WalletUtxo>> requireUtxos() async {
      final utxos = await utxoRepository.getWalletUtxos(walletId: wallet.id);
      if (utxos.isEmpty) {
        fail('testnet wallet ${wallet.id} is unfunded');
      }
      return utxos;
    }

    test('list surfaces confirmations and labels per UTXO', () async {
      final utxos = await requireUtxos();

      // Confirmations are intrinsic per-UTXO data (D2); confirmed coins carry a
      // positive count and isConfirmed mirrors it.
      for (final utxo in utxos) {
        expect(utxo.confirmations, greaterThanOrEqualTo(0));
        expect(utxo.isConfirmed, utxo.confirmations > 0);
        // Labels are read-only BIP329 strings the tile renders; the field is
        // always present (possibly empty) — assert the contract, not content.
        expect(utxo.labels, isNotNull);
      }
    });

    test('frozen coins are excluded from every PSBT build (D7)', () async {
      final utxos = await requireUtxos();

      // Freeze EVERY coin. A decode-free way to prove D7 exclusion is real: if
      // frozen coins were still selectable, a drain would build fine; with all
      // coins in the unspendable set, BDK has nothing to pick and the build must
      // fail with NoSpendableUtxoException. This proves the same guarantee
      // without PSBT input decoding machinery.
      final allOutpoints = utxos
          .map((u) => (txId: u.txId, vout: u.vout))
          .toList();
      await utxoRepository.freezeUtxos(
        walletId: wallet.id,
        outpoints: allOutpoints,
      );
      addTearDown(
        () => utxoRepository.unfreezeUtxos(
          walletId: wallet.id,
          outpoints: allOutpoints,
        ),
      );

      final receive = await addressRepository.generateNewReceiveAddress(
        walletId: wallet.id,
      );

      // Drain to self: selection would otherwise sweep every coin. With all
      // frozen, the prepare must throw NoSpendableUtxoException.
      await expectLater(
        prepareBitcoinSendUsecase.execute(
          walletId: wallet.id,
          address: receive.address,
          drain: true,
          networkFee: NetworkFee.relativeFromSatPerVbyte(2),
        ),
        throwsA(isA<NoSpendableUtxoException>()),
      );
    });
  });
}
