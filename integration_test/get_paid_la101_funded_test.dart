import 'dart:convert';

import 'package:bb_mobile/core/blockchain/domain/usecases/broadcast_liquid_transaction_usecase.dart';
import 'package:bb_mobile/core/fees/domain/fees_entity.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/domain/entities/transaction_output.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/create_default_wallets_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_receive_address_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallet_transactions_usecase.dart';
import 'package:bb_mobile/features/test_wallet_backup/domain/usecases/get_mnemonic_from_fingerprint_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/send/domain/usecases/calculate_liquid_absolute_fees_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/prepare_liquid_send_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/sign_liquid_tx_usecase.dart';
import 'package:bb_mobile/features/wallet/domain/usecase/run_wallet_auto_sweep_usecase.dart';
import 'package:bb_mobile/locator.dart';
import 'package:bb_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/funded_la101_fixtures.dart';
import 'support/wipe_app_state.dart';

// S-REAL-PROD-LA101-FUNDED: production Bullnym + production Nostr + real
// seed-derived keys against the live network. Like the funded Page-102 lane
// this one MOVES REAL FUNDS, so it never executes a payment on its own: it
// registers a wallet-owned Lightning Address (activating wallet 101), publishes
// the Lightning Address + payable addresses to a handshake directory, WAITS for
// an external coordinator to pay the Lightning Address over Lightning, observes
// the receipt (the Boltz reverse-swap claim credit) + autosweep through the
// app's own wallet sync, then returns the funds via the app's real Liquid Send
// flow to an address the coordinator writes back. Every phase emits a
// machine-readable CHECKPOINT line so the coordinator can journal the run.
//
// A LN payment to a Bull Lightning Address settles L-BTC into wallet 101 via a
// Boltz REVERSE swap (not a chain swap — see funded_la101_fixtures.dart), so the
// amount that lands is `target - swap_fee`. Lightning leaves no independent
// chain artifact on the payer→receiver leg, so the coordinator grades the
// RESULTING Liquid credit (docs/CHAIN-ORACLE.md). Because the reverse-swap claim
// address is allocated server-side at claim time (bullnym `lnurl.rs`:
// "the cooperative MuSig2 claim path allocates the descriptor index at claim
// time"), the coordinator cannot know it a priori: this spec reports the ACTUAL
// credited address / outpoint / amount from the app's synced transaction list.

// Post-sweep the source wallet keeps at most the network dust it could not
// spend; treat anything at or below this as "drained".
const _drainedDustCeilingSat = 100;

Future<void> main({bool isInitialized = false}) async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!isInitialized) await Bull.init();

  late final FundedLa101Fixtures fixtures;

  setUpAll(() {
    // Fails fast with a clear refusal when the lane guard, mnemonic, or
    // handshake directory are missing (the smoke lane proves the last one).
    fixtures = FundedLa101Fixtures.fromEnvironment();
  });

  test('funded LA-101 journey: receive on 101 over the Lightning Address, '
      'autosweep to the default Liquid wallet, then return the balance via the '
      'real Send flow', () async {
    _checkpoint('env_check', data: {
      'run_id': fixtures.runId,
      'nym': fixtures.nym,
      'handshake_dir': fixtures.handshakeDir.path,
      'target_amount_sat': fixtures.targetAmountSat,
      'max_fee_sat': fixtures.maxFeeSat,
    });

    final settings = await locator<GetSettingsUsecase>().execute();
    final environment = settings.environment;
    final network = environment.isMainnet ? 'liquid-mainnet' : 'liquid-testnet';

    // (a) Drive the app's OWN wallet-creation flow: with no mnemonic supplied,
    // CreateDefaultWalletsUsecase generates the seed on-device, so the app owns
    // it exactly like a fresh-install customer (which the app then auto-backs-up
    // via the Nostr keychain). No externally-derived mnemonic is injected.
    await wipeAppState(locator);
    await locator<CreateDefaultWalletsUsecase>().execute();
    final defaultLiquid = await _defaultLiquidWallet(environment);
    _checkpoint('wallet_created', data: {
      'default_liquid_wallet_id': defaultLiquid.id,
      'network': network,
    });

    // FUND-SAFETY: before any funding, persist the app-generated recovery
    // material to the durable mode-0600 seed-carry dir so stranded funds are
    // always recoverable. All wallets (default Bitcoin/Liquid + the BIP85
    // wallet 101) derive from this one root seed, so a single backup covers the
    // whole run. The words are read via the app's own seed-export API and are
    // NEVER logged or checkpointed — only the export file path is surfaced.
    final (mnemonicWords, passphrase) =
        await locator<GetMnemonicFromFingerprintUsecase>()
            .execute(defaultLiquid.masterFingerprint);
    final seedBackupFile = await fixtures.writeSeedBackup(
      masterFingerprint: defaultLiquid.masterFingerprint,
      mnemonicWords: mnemonicWords,
      passphrase: passphrase,
      network: network,
    );
    _checkpoint('recovery_captured', data: {
      'master_fingerprint': defaultLiquid.masterFingerprint,
      'seed_backup_file': seedBackupFile,
    });

    // (b) Register a wallet-owned Lightning Address. This materializes wallet
    // 101 (Liquid) and publishes the registration to Bullnym/Nostr, matching the
    // production Get Paid onboarding order. Acknowledge the backup disclosure
    // first (same gate the Page-102 flow uses before an outward publish).
    await locator<GetPaidSettingsFacade>().acknowledgeBackupDisclosure(
      automatedBackupEnabled: true,
    );
    final registration = await locator<LightningAddressFacade>()
        .registerWalletOwned(nym: fixtures.nym);
    final lightningAddress = registration.registration.lightningAddress;
    expect(lightningAddress, contains('@'),
        reason: 'registration must yield a full nym@domain Lightning Address');
    final wallet101 = await _walletById(registration.walletId);
    expect(wallet101.autoSweepEnabled, isTrue,
        reason: 'wallet 101 must have autosweep enabled');
    expect(wallet101.isDefault, isFalse);
    _checkpoint('lightning_registered', data: {
      'nym': registration.registration.nym,
      'lightning_address': lightningAddress,
      'wallet101_wallet_id': wallet101.id,
      'wallet_created': registration.walletCreated,
    });

    // (c) Derive the addresses and publish the offer. The wallet-101 receive
    // address is informational only: the reverse-swap claim is paid to a
    // server-allocated address in the same wallet, so the coordinator grades the
    // credit against the ACTUAL received address this spec reports later, not
    // this one. The default-Liquid address backs the sweep-credit oracle.
    final wallet101Address = await locator<GetReceiveAddressUsecase>().execute(
      walletId: wallet101.id,
      generateNew: true,
    );
    final defaultLiquidAddress = await locator<GetReceiveAddressUsecase>()
        .execute(walletId: defaultLiquid.id, generateNew: true);
    _checkpoint('addresses_derived', data: {
      'wallet101_receive_address': wallet101Address.address,
      'default_liquid_address': defaultLiquidAddress.address,
    });

    await fixtures.writeJsonAtomic(fixtures.requestFile, {
      'schema': 'getpaid-la101-funded/v1',
      'run_id': fixtures.runId,
      'nym': fixtures.nym,
      'network': network,
      'lightning_address': lightningAddress,
      'wallet101_receive_address': wallet101Address.address,
      'default_liquid_address': defaultLiquidAddress.address,
      'target_amount_sat': fixtures.targetAmountSat,
      'max_fee_sat': fixtures.maxFeeSat,
      'status': 'awaiting_payment',
      'written_at': DateTime.now().toUtc().toIso8601String(),
    });
    _checkpoint('handshake_offer_written', data: {
      'request_file': fixtures.requestFile.path,
    });

    // (d) Wait for the payment to arrive via sync. The credit is `target -
    // swap_fee` so we cannot wait for the exact target; a fresh QA wallet 101
    // starts empty, so any positive balance is the reverse-swap claim.
    final fundedWallet101 = await _pollWallet(
      walletId: wallet101.id,
      timeout: fixtures.paymentTimeout,
      interval: fixtures.pollInterval,
      step: 'awaiting_payment',
      until: (w) => w.balanceSat > BigInt.zero,
    );
    _checkpoint('payment_detected', data: {
      'wallet101_balance_sat': fundedWallet101.balanceSat.toString(),
    });

    // (e) Resolve the actual receipt from the synced transaction list: the
    // incoming claim tx and its own output give the credited amount + the
    // outpoint the coordinator's oracle grades (expectCredit on the address,
    // expectSpent on the outpoint once the autosweep drains it).
    final receipt = await _resolveReceipt(wallet101.id);
    expect(receipt.amountSat, greaterThan(0));
    expect(receipt.amountSat, lessThanOrEqualTo(fixtures.targetAmountSat),
        reason: 'wallet-101 credit is target minus the reverse-swap fee');
    _checkpoint('receipt_asserted', data: {
      'wallet101_balance_sat': fundedWallet101.balanceSat.toString(),
      'receipt_txid': receipt.txId,
      'receipt_vout': receipt.vout,
      'receipt_address': receipt.address,
      'receipt_amount_sat': receipt.amountSat,
    });

    // (f) Autosweep fires on sync: 101 drains into the default Liquid wallet.
    final defaultBefore = (await _syncWallet(defaultLiquid.id)).balanceSat;
    final sweep = await locator<RunWalletAutoSweepUsecase>().execute(
      fundedWallet101,
    );
    final sweepTxid = switch (sweep) {
      AutosweepSwept(:final txid) => txid,
      AutosweepSkipped(:final reason) =>
        fail('autosweep skipped unexpectedly: $reason'),
      AutosweepFailed(:final error) =>
        fail('autosweep failed unexpectedly: $error'),
    };
    _checkpoint('autosweep_swept', data: {'autosweep_txid': sweepTxid});

    final drained101 = await _pollWallet(
      walletId: wallet101.id,
      timeout: fixtures.paymentTimeout,
      interval: fixtures.pollInterval,
      step: 'awaiting_sweep_drain',
      until: (w) => w.balanceSat <= BigInt.from(_drainedDustCeilingSat),
    );
    final defaultCredited = await _pollWallet(
      walletId: defaultLiquid.id,
      timeout: fixtures.paymentTimeout,
      interval: fixtures.pollInterval,
      step: 'awaiting_sweep_credit',
      until: (w) => w.balanceSat > defaultBefore,
    );
    expect(defaultCredited.balanceSat, greaterThan(defaultBefore));
    _checkpoint('sweep_asserted', data: {
      'wallet101_balance_sat': drained101.balanceSat.toString(),
      'default_liquid_balance_before_sat': defaultBefore.toString(),
      'default_liquid_balance_after_sat': defaultCredited.balanceSat.toString(),
    });

    // (g) Read the coordinator's return address, then drive the REAL Send flow
    // to drain the default Liquid wallet (remaining balance minus fee) back.
    final returnAddress = await _pollReturnAddress(fixtures);
    _checkpoint('return_address_read', data: {'return_address': returnAddress});

    final feeRate = NetworkFee.relativeFromSatPerVbyte(fixtures.feeRateSatPerVb);
    final pset = await locator<PrepareLiquidSendUsecase>().execute(
      walletId: defaultLiquid.id,
      address: returnAddress,
      feeRate: feeRate,
      drain: true,
    );
    final feeSat = await locator<CalculateLiquidAbsoluteFeesUsecase>().execute(
      pset: pset,
    );
    expect(feeSat, lessThanOrEqualTo(fixtures.maxFeeSat),
        reason: 'return fee must stay within the configured ceiling');
    _checkpoint('return_prepared', data: {'return_fee_sat': feeSat});

    final signed = await locator<SignLiquidTxUsecase>().execute(
      pset: pset,
      walletId: defaultLiquid.id,
    );
    final returnTxid = await locator<BroadcastLiquidTransactionUsecase>()
        .execute(signed, isTestnet: environment.isTestnet);
    _checkpoint('return_broadcast', data: {'return_txid': returnTxid});

    // (h) Publish the final observed state for the coordinator's journal.
    final finalDefault = await _syncWallet(defaultLiquid.id);
    final finalWallet101 = await _syncWallet(wallet101.id);
    await fixtures.writeJsonAtomic(fixtures.resultFile, {
      'schema': 'getpaid-la101-funded-result/v1',
      'run_id': fixtures.runId,
      'nym': fixtures.nym,
      'network': network,
      'lightning_address': lightningAddress,
      'receipt_txid': receipt.txId,
      'receipt_vout': receipt.vout,
      'receipt_address': receipt.address,
      'receipt_amount_sat': receipt.amountSat,
      'autosweep_txid': sweepTxid,
      'return_txid': returnTxid,
      'return_address': returnAddress,
      'return_fee_sat': feeSat,
      'final_wallet101_balance_sat': finalWallet101.balanceSat.toString(),
      'final_default_liquid_balance_sat': finalDefault.balanceSat.toString(),
      'status': 'complete',
      'written_at': DateTime.now().toUtc().toIso8601String(),
    });
    _checkpoint('result_written', data: {'result_file': fixtures.resultFile.path});
    _checkpoint('done', data: {
      'autosweep_txid': sweepTxid,
      'return_txid': returnTxid,
    });
  }, timeout: const Timeout(Duration(minutes: 45)));
}

Future<Wallet> _defaultLiquidWallet(Environment environment) async {
  final wallets = await locator<WalletRepository>().getWallets(
    environment: environment,
    onlyDefaults: true,
    onlyLiquid: true,
  );
  if (wallets.isEmpty) {
    throw StateError('no default Liquid wallet after restore');
  }
  return wallets.first;
}

Future<Wallet> _walletById(String walletId) async {
  final wallet = await locator<WalletRepository>().getWallet(walletId);
  if (wallet == null) {
    throw StateError('wallet $walletId (101) not found after registration');
  }
  return wallet;
}

/// The receipt outpoint the coordinator grades: the reverse-swap claim credit.
typedef _Receipt = ({String txId, int vout, String address, int amountSat});

/// Finds the incoming wallet-101 transaction (the Boltz reverse-swap claim) and
/// extracts its own-output outpoint + credited amount. This is what the
/// coordinator's oracle checks — the app never learns the address a priori
/// because bullnym allocates it at claim time.
Future<_Receipt> _resolveReceipt(String walletId) async {
  final txs = await locator<GetWalletTransactionsUsecase>().execute(
    walletId: walletId,
    sync: true,
  );
  final incoming = txs.where((t) => t.isIncoming && t.amountSat > 0).toList()
    ..sort((a, b) => b.amountSat.compareTo(a.amountSat));
  if (incoming.isEmpty) {
    throw StateError('no incoming transaction on wallet 101 after receipt');
  }
  final tx = incoming.first;
  final output = tx.destinationOutput;
  if (output is! TransactionOutput || output.address == null) {
    throw StateError(
      'incoming wallet-101 tx ${tx.txId} has no own destination output',
    );
  }
  return (
    txId: tx.txId,
    vout: output.vout,
    address: output.address!,
    amountSat: tx.amountSat,
  );
}

/// Syncs a single wallet and returns its fresh state (balance included). This is
/// the same repository path the wallet bloc drives on a real sync.
Future<Wallet> _syncWallet(String walletId) async {
  final wallet = await locator<WalletRepository>().getWallet(
    walletId,
    sync: true,
  );
  if (wallet == null) {
    throw StateError('wallet $walletId disappeared during sync');
  }
  return wallet;
}

Future<Wallet> _pollWallet({
  required String walletId,
  required Duration timeout,
  required Duration interval,
  required String step,
  required bool Function(Wallet) until,
}) async {
  final deadline = DateTime.now().add(timeout);
  var attempt = 0;
  while (true) {
    attempt++;
    final wallet = await _syncWallet(walletId);
    if (until(wallet)) return wallet;
    if (DateTime.now().isAfter(deadline)) {
      _checkpoint(step, status: 'timeout', data: {
        'wallet_id': walletId,
        'attempts': attempt,
        'last_balance_sat': wallet.balanceSat.toString(),
      });
      throw StateError(
        '$step timed out after ${timeout.inSeconds}s (last balance '
        '${wallet.balanceSat} sat on $walletId)',
      );
    }
    _checkpoint(step, status: 'waiting', data: {
      'attempt': attempt,
      'last_balance_sat': wallet.balanceSat.toString(),
    });
    await Future<void>.delayed(interval);
  }
}

Future<String> _pollReturnAddress(FundedLa101Fixtures fixtures) async {
  final deadline = DateTime.now().add(fixtures.returnTimeout);
  var attempt = 0;
  while (true) {
    attempt++;
    final response = await fixtures.readJson(fixtures.responseFile);
    final address = response?['return_address'];
    if (address is String && address.trim().isNotEmpty) {
      return address.trim();
    }
    if (DateTime.now().isAfter(deadline)) {
      _checkpoint('awaiting_return_address', status: 'timeout', data: {
        'attempts': attempt,
        'response_file': fixtures.responseFile.path,
      });
      throw StateError(
        'return address not provided within ${fixtures.returnTimeout.inSeconds}s'
        ' (expected `return_address` in ${fixtures.responseFile.path})',
      );
    }
    _checkpoint('awaiting_return_address', status: 'waiting', data: {
      'attempt': attempt,
    });
    await Future<void>.delayed(fixtures.pollInterval);
  }
}

/// Emits a single machine-readable checkpoint line. Only non-secret run
/// metadata (addresses, txids, amounts, balances) is ever included — never the
/// mnemonic or any signer material.
void _checkpoint(
  String step, {
  String status = 'ok',
  Map<String, Object?> data = const {},
}) {
  final payload = <String, Object?>{
    'step': step,
    'status': status,
    'ts': DateTime.now().toUtc().toIso8601String(),
    ...data,
  };
  // ignore: avoid_print
  print('CHECKPOINT ${jsonEncode(payload)}');
}
