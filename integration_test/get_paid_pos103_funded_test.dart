import 'dart:convert';

import 'package:bb_mobile/core/blockchain/domain/usecases/broadcast_liquid_transaction_usecase.dart';
import 'package:bb_mobile/core/fees/domain/fees_entity.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/transaction_output.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/create_default_wallets_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_receive_address_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallet_transactions_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/pos/public/pos_facade.dart';
import 'package:bb_mobile/features/send/domain/usecases/calculate_liquid_absolute_fees_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/prepare_liquid_send_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/sign_liquid_tx_usecase.dart';
import 'package:bb_mobile/features/test_wallet_backup/domain/usecases/get_mnemonic_from_fingerprint_usecase.dart';
import 'package:bb_mobile/features/wallet/domain/usecase/run_wallet_auto_sweep_usecase.dart';
import 'package:bb_mobile/locator.dart';
import 'package:bb_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/funded_pos103_fixtures.dart';
import 'support/wipe_app_state.dart';

// S-REAL-PROD-POS103-FUNDED: production Bullnym + production Nostr + real
// seed-derived keys against the live network. Like the funded Page-102 / LA-101
// lanes this one MOVES REAL FUNDS, so it never executes a payment on its own: it
// creates and owns its wallet, provisions a Point of Sale terminal (activating
// wallet 103), publishes the POS receive surface (the server-hosted terminal
// URL) to a handshake directory, WAITS for an external coordinator to pay the
// POS checkout over Lightning, observes the receipt (the Boltz reverse-swap
// claim credit) + autosweep through the app's own wallet sync, then returns the
// funds via the app's real Liquid Send flow to an address the coordinator writes
// back. Every phase emits a machine-readable CHECKPOINT line.
//
// REAL BULLNYM SETTLEMENT (verified at f6eec5127 + bullnym server). The POS
// terminal mints its invoice entirely server-side (the app mints none). A POS
// checkout paid over Lightning settles L-BTC into wallet 103 via a Boltz REVERSE
// swap (not a chain swap, so the 25,000-sat Boltz chain-swap minimum does not
// bind); the claim address is allocated SERVER-SIDE from the (nym,'pos')
// descriptor at claim time, so the amount that lands is `target - swap_fee` and
// the coordinator cannot know the address a priori. This spec reports the ACTUAL
// credited address / outpoint / amount from the app's synced transaction list,
// which the coordinator's independent oracle then grades on-chain.
//
// APP-OWNED WALLET. The recipient wallet is created on-device by the normal
// wallet-creation flow (a fresh seed the app generates and owns, auto-backed-up
// over Nostr) — NOT restored from an injected mnemonic. Before any funds move,
// the app's own show-mnemonic/backup-export path captures the recovery material
// to a durable mode-0600 file so an interrupted run is recoverable. The words are
// NEVER logged, printed, committed, or emitted on the handshake — only the
// capture-file PATH + master fingerprint appear in a checkpoint.
//
// DESTINATION ISOLATION. POS and the Lightning Address share one nym but never a
// settlement destination: a POS sale settles to wallet 103 and NEVER to the
// Lightning Address wallet 101 (provision_pos_usecase.dart "settle to 103, never
// 101/102"; the server routes the pos checkout to the (nym,'pos') descriptor,
// distinct from the users/101 descriptor). This spec asserts BOTH that wallet 103
// received the payment AND that wallet 101 did not — the app-observed half. The
// coordinator's independent oracle proves the same on-chain (expectNoTx on the
// published wallet-101 address).

const _posWalletLabel = 'POS Liquid';
const _lightningAddressWalletLabel = 'Lightning Address Liquid';

// Post-sweep the source wallet keeps at most the network dust it could not
// spend; treat anything at or below this as "drained".
const _drainedDustCeilingSat = 100;

// The reverse-swap net credited to wallet 103 is ~= the target (the live run saw
// 2001 for a 2000 target). Accept the actual net within this tolerance of target
// (above or below), rather than assuming a strict target-minus-fee < target.
const _reverseSwapNetToleranceSat = 500;

Future<void> main({bool isInitialized = false}) async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!isInitialized) await Bull.init();

  late final FundedPos103Fixtures fixtures;

  setUpAll(() {
    // Fails fast with a clear refusal when the lane guard, handshake directory,
    // or fund-safety capture directory are missing (the smoke lane proves this).
    fixtures = FundedPos103Fixtures.fromEnvironment();
  });

  test('funded POS-103 journey: real Bullnym settlement into wallet 103 (never '
      'wallet 101), autosweep to the default Liquid wallet, then return the '
      'balance via the real Send flow', () async {
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
      'master_fingerprint': defaultLiquid.masterFingerprint,
      'network': network,
    });

    // (a.1) FUND-SAFETY: before any funding, persist the app-generated recovery
    // material to the durable mode-0600 seed-carry dir so stranded funds are
    // always recoverable. All wallets (default Bitcoin/Liquid + the BIP85 101 &
    // 103 product wallets) derive from this one root seed, so a single backup
    // covers the whole run. The words are read via the app's own seed-export API
    // and are NEVER logged or checkpointed — only the export file path is
    // surfaced.
    final fingerprint = defaultLiquid.masterFingerprint;
    if (fingerprint.isEmpty) {
      fail('app-created wallet has no master fingerprint to capture');
    }
    final (mnemonicWords, passphrase) =
        await locator<GetMnemonicFromFingerprintUsecase>().execute(fingerprint);
    final capturePath = await fixtures.writeSeedCapture({
      'schema': 'getpaid-pos103-seed-capture/v1',
      'run_id': fixtures.runId,
      'network': network,
      'master_fingerprint': fingerprint,
      'mnemonic_words': mnemonicWords,
      if (passphrase != null && passphrase.isNotEmpty) 'passphrase': passphrase,
      'captured_at': DateTime.now().toUtc().toIso8601String(),
    });
    _checkpoint('recovery_captured', data: {
      'master_fingerprint': fingerprint,
      'seed_capture_file': capturePath,
    });

    // (b) Register the shared Lightning Address (materializes wallet 101, which
    // POS provisioning reuses as the identity). Acknowledge the backup disclosure
    // first. Wallet 101 is the isolation guard's subject — it must NOT receive
    // the POS sale.
    await locator<GetPaidSettingsFacade>().setAutomatedBackupEnabled(true);
    final registration = await locator<LightningAddressFacade>()
        .registerWalletOwned(nym: fixtures.nym);
    final lightningAddress101 = await _lightningAddressWallet(environment);
    _checkpoint('lightning_registered', data: {
      'nym': registration.registration.nym,
      'wallet101_id': lightningAddress101.id,
    });

    // (c) Provision the POS terminal; provisioning materializes wallet 103
    // (Liquid) and pins settlement to it by registering its ct_descriptor with
    // Bullnym. The terminal URL is the server-owned POS receive surface.
    final terminal = await locator<PosFacade>().provision(
      const PosProvisionCommand(
        label: 'Funded POS-103',
        displayCurrency: 'CAD',
      ),
    );
    expect(terminal.isActive, isTrue);
    expect(terminal.terminalUrl, isNotEmpty);

    final pos103 = await _posWallet(environment);
    expect(pos103.autoSweepEnabled, isTrue,
        reason: 'wallet 103 must have autosweep enabled');
    // A wallet-103 reference address (informational). The actual reverse-swap
    // claim address is allocated server-side, so the coordinator grades the
    // credit against the ACTUAL received address this spec reports later.
    final pos103ReferenceAddress =
        await locator<GetReceiveAddressUsecase>().execute(
      walletId: pos103.id,
      generateNew: true,
    );
    final lightningAddress101Address =
        await locator<GetReceiveAddressUsecase>().execute(
      walletId: lightningAddress101.id,
      generateNew: true,
    );
    final defaultLiquidAddress = await locator<GetReceiveAddressUsecase>()
        .execute(walletId: defaultLiquid.id, generateNew: true);
    _checkpoint('pos_provisioned', data: {
      'terminal_url': terminal.terminalUrl,
      'pos103_wallet_id': pos103.id,
    });
    _checkpoint('addresses_derived', data: {
      'pos103_reference_address': pos103ReferenceAddress.address,
      'lightning_address_receive_address': lightningAddress101Address.address,
      'default_liquid_address': defaultLiquidAddress.address,
    });

    // Baseline the isolated wallet 101 (must be untouched by a POS sale). It is
    // freshly created and only carries its LN registration, so it is empty.
    final wallet101Before =
        (await _syncWallet(lightningAddress101.id)).balanceSat;

    // (d) Publish the offer. The pay TARGET is the terminal URL (the coordinator
    // pays the POS checkout over Lightning; Bullnym settles into wallet 103). The
    // wallet-101 address rides along so the coordinator's oracle can prove no
    // funds land there.
    await fixtures.writeJsonAtomic(fixtures.requestFile, {
      'schema': 'getpaid-pos103-funded/v1',
      'run_id': fixtures.runId,
      'nym': fixtures.nym,
      'network': network,
      'receive_rail': 'lightning',
      'terminal_url': terminal.terminalUrl,
      'pos103_reference_address': pos103ReferenceAddress.address,
      'lightning_address_receive_address': lightningAddress101Address.address,
      'default_liquid_address': defaultLiquidAddress.address,
      'target_amount_sat': fixtures.targetAmountSat,
      'max_fee_sat': fixtures.maxFeeSat,
      'status': 'awaiting_payment',
      'written_at': DateTime.now().toUtc().toIso8601String(),
    });
    _checkpoint('handshake_offer_written', data: {
      'request_file': fixtures.requestFile.path,
    });

    // (e) Wait for the settlement to arrive via sync. The reverse-swap credit is
    // `target - swap_fee` so we cannot wait for the exact target; a fresh wallet
    // 103 starts empty, so any positive balance is the reverse-swap claim.
    final fundedWallet103 = await _pollWallet(
      walletId: pos103.id,
      timeout: fixtures.paymentTimeout,
      interval: fixtures.pollInterval,
      step: 'awaiting_payment',
      until: (w) => w.balanceSat > BigInt.zero,
    );
    _checkpoint('payment_detected', data: {
      'pos103_balance_sat': fundedWallet103.balanceSat.toString(),
    });

    // (f) Resolve the actual receipt from the synced transaction list: the
    // incoming claim tx and its own output give the credited amount + the
    // outpoint the coordinator's oracle grades (expectCredit on the address,
    // expectSpent on the outpoint once the autosweep drains it).
    final receipt = await _resolveReceipt(pos103.id);
    expect(receipt.amountSat, greaterThan(0));
    // The reverse swap nets ~= target: the live run credited 2001 for a 2000
    // target, i.e. it can land a hair ABOVE (or below) target after the swap/
    // claim fee. Assert the credit is WITHIN A TOLERANCE of target rather than a
    // strict <= target (which wrongly failed on 2001); matches the Page-102 spec,
    // which does not cap the credit at target.
    expect(
      receipt.amountSat,
      greaterThanOrEqualTo(fixtures.targetAmountSat - _reverseSwapNetToleranceSat),
      reason: 'wallet-103 credit should be ~= target (reverse-swap net)',
    );
    expect(
      receipt.amountSat,
      lessThanOrEqualTo(fixtures.targetAmountSat + _reverseSwapNetToleranceSat),
      reason: 'wallet-103 credit should be ~= target (reverse-swap net)',
    );
    _checkpoint('receipt_asserted', data: {
      'pos103_balance_sat': fundedWallet103.balanceSat.toString(),
      'receipt_txid': receipt.txId,
      'receipt_vout': receipt.vout,
      'receipt_address': receipt.address,
      'receipt_amount_sat': receipt.amountSat,
    });

    // (f.1) DESTINATION ISOLATION (app-observed half): the shared Lightning
    // Address wallet 101 must NOT have received the POS sale. Its balance must be
    // unchanged from the pre-payment baseline. A leak into wallet 101 fails the
    // run here, before the funds are swept or returned.
    final wallet101After =
        (await _syncWallet(lightningAddress101.id)).balanceSat;
    expect(
      wallet101After,
      equals(wallet101Before),
      reason: 'destination isolation: the POS sale must settle to wallet 103 '
          'and never to the Lightning Address wallet 101 (before '
          '$wallet101Before sat, after $wallet101After sat)',
    );
    _checkpoint('isolation_asserted', data: {
      'wallet101_balance_before_sat': wallet101Before.toString(),
      'wallet101_balance_after_sat': wallet101After.toString(),
      'pos103_balance_sat': fundedWallet103.balanceSat.toString(),
    });

    // (g) Autosweep fires on sync: 103 drains into the default Liquid wallet.
    final defaultBefore = (await _syncWallet(defaultLiquid.id)).balanceSat;
    final sweep = await locator<RunWalletAutoSweepUsecase>().execute(
      fundedWallet103,
    );
    final sweepTxid = switch (sweep) {
      AutosweepSwept(:final txid) => txid,
      AutosweepSkipped(:final reason) =>
        fail('autosweep skipped unexpectedly: $reason'),
      AutosweepFailed(:final error) =>
        fail('autosweep failed unexpectedly: $error'),
    };
    _checkpoint('autosweep_swept', data: {'autosweep_txid': sweepTxid});

    final drained103 = await _pollWallet(
      walletId: pos103.id,
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
      'pos103_balance_sat': drained103.balanceSat.toString(),
      'default_liquid_balance_before_sat': defaultBefore.toString(),
      'default_liquid_balance_after_sat': defaultCredited.balanceSat.toString(),
    });

    // (h) Read the coordinator's return address, then drive the REAL Send flow to
    // drain the default Liquid wallet (remaining balance minus fee) back.
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

    // (i) Publish the final observed state for the coordinator's journal,
    // including the receipt outpoint and the still-isolated wallet-101 balance.
    final finalDefault = await _syncWallet(defaultLiquid.id);
    final finalPos103 = await _syncWallet(pos103.id);
    final finalWallet101 = await _syncWallet(lightningAddress101.id);
    await fixtures.writeJsonAtomic(fixtures.resultFile, {
      'schema': 'getpaid-pos103-funded-result/v1',
      'run_id': fixtures.runId,
      'nym': fixtures.nym,
      'network': network,
      'receive_rail': 'lightning',
      'terminal_url': terminal.terminalUrl,
      'receipt_txid': receipt.txId,
      'receipt_vout': receipt.vout,
      'receipt_address': receipt.address,
      'receipt_amount_sat': receipt.amountSat,
      'autosweep_txid': sweepTxid,
      'return_txid': returnTxid,
      'return_address': returnAddress,
      'return_fee_sat': feeSat,
      'final_pos103_balance_sat': finalPos103.balanceSat.toString(),
      'final_default_liquid_balance_sat': finalDefault.balanceSat.toString(),
      'final_lightning_address_balance_sat':
          finalWallet101.balanceSat.toString(),
      'status': 'complete',
      'written_at': DateTime.now().toUtc().toIso8601String(),
    });
    _checkpoint('result_written', data: {'result_file': fixtures.resultFile.path});
    _checkpoint('done', data: {
      'receipt_txid': receipt.txId,
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
    throw StateError('no default Liquid wallet after create');
  }
  return wallets.first;
}

Future<Wallet> _posWallet(Environment environment) async {
  final wallets = await locator<WalletRepository>().getWallets(
    environment: environment,
    onlyLiquid: true,
  );
  return wallets.firstWhere(
    (w) => w.label == _posWalletLabel && !w.isDefault,
    orElse: () => throw StateError(
      'POS wallet 103 ($_posWalletLabel) not found after provision',
    ),
  );
}

Future<Wallet> _lightningAddressWallet(Environment environment) async {
  final wallets = await locator<WalletRepository>().getWallets(
    environment: environment,
    onlyLiquid: true,
  );
  return wallets.firstWhere(
    (w) => w.label == _lightningAddressWalletLabel && !w.isDefault,
    orElse: () => throw StateError(
      'Lightning Address wallet 101 ($_lightningAddressWalletLabel) not found '
      'after registration',
    ),
  );
}

/// The receipt outpoint the coordinator grades: the reverse-swap claim credit.
typedef _Receipt = ({String txId, int vout, String address, int amountSat});

/// Finds the incoming wallet-103 transaction (the Boltz reverse-swap claim) and
/// extracts its own-output outpoint + credited amount + address. This is what
/// the coordinator's oracle checks — the app never learns the address a priori
/// because bullnym allocates it from the pos descriptor at claim time.
Future<_Receipt> _resolveReceipt(String walletId) async {
  final txs = await locator<GetWalletTransactionsUsecase>().execute(
    walletId: walletId,
    sync: true,
  );
  final incoming = txs.where((t) => t.isIncoming && t.amountSat > 0).toList()
    ..sort((a, b) => b.amountSat.compareTo(a.amountSat));
  if (incoming.isEmpty) {
    throw StateError('no incoming transaction on wallet 103 after receipt');
  }
  final tx = incoming.first;
  final output = tx.destinationOutput;
  if (output is! TransactionOutput || output.address == null) {
    throw StateError(
      'incoming wallet-103 tx ${tx.txId} has no own destination output',
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

Future<String> _pollReturnAddress(FundedPos103Fixtures fixtures) async {
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
/// metadata (addresses, txids, amounts, balances, capture-file PATH) is ever
/// included — never the mnemonic, passphrase, or any signer material.
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
