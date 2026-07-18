import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/create_default_wallets_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_receive_address_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/update_wallet_behavior_usecase.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_connection.dart';
import 'package:bb_mobile/features/btcpay/domain/usecases/complete_btcpay_samrock_pairing_usecase.dart';
import 'package:bb_mobile/features/btcpay/domain/usecases/get_btcpay_connection_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/test_wallet_backup/domain/usecases/get_mnemonic_from_fingerprint_usecase.dart';
import 'package:bb_mobile/features/wallet/domain/usecase/run_wallet_auto_sweep_usecase.dart';
import 'package:bb_mobile/locator.dart';
import 'package:bb_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/funded_btcpay100_fixtures.dart';
import 'support/return_liquid_to_bullstr.dart';
import 'support/wipe_app_state.dart';

// S-REAL-PROD-BTCPAY100-FUNDED: production SamRock pairing against the live
// BITCOIN mainnet, into a wallet the APP CREATES AND OWNS (the app generates the
// seed on-device — nothing is injected or restored). Unlike every other lane
// this one MOVES REAL FUNDS, so it never executes a payment on its own: it
// creates the wallet, captures its recovery material to a mode-600 fund-safety
// carry BEFORE any funds move, drives the app's real SamRock pairing to activate
// the BTCPay on-chain BTC wallet (BIP85 wallet index 100), publishes the
// wallet-100 receive address to a handshake directory, WAITS for an external
// coordinator to fund it, observes the receipt + autosweep through the app's own
// wallet sync, then returns the funds through the app's Bitcoin-to-Lightning
// flow to the fixed Bullstr address. Recovery of a crashed run is via the
// captured seed (and the app's own automated backup). Every phase emits a
// machine-readable CHECKPOINT line — always redaction-scrubbed — so the
// coordinator can journal the run.
//
// Two BTCPay-specific invariants this witness proves, verified against
// f6eec5127:
//
//  * btc-chain SamRock receive is a PLAIN on-chain BTC receive into the
//    dedicated "BTCPay Bitcoin" wallet — not a Boltz chain swap. The autosweep
//    drains that Bitcoin wallet to the DEFAULT BITCOIN wallet (not Liquid).
//  * The BTCPay Bitcoin wallet ships with auto-sweep DISABLED
//    (CompleteBtcpaySamRockPairingUsecase sets autoSweepEnabled only for the
//    Liquid wallet; RunAutoSweepUsecase documents "BTCPay's Bitcoin wallet is
//    created with auto-sweep off"). So the witness first ASSERTS the default-off
//    posture, then ENABLES auto-sweep on wallet 100 (the editable BTCPay details
//    setting) before the sweep can fire — the app-observed half of the proof.
//
// The credential (the SamRock pairing URL, carrying a short-lived OTP) is read
// ONLY from GETPAID_BTCPAY_PAIRING_URL at run time and never printed, written,
// or embedded. Fixtures fail-closed if it (or the handshake dir) is unset.
const _btcpayBitcoinWalletLabel = 'BTCPay Bitcoin';

// A full on-chain drain leaves no change output, so the source settles to 0.
// Treat anything at or below the standard relay dust floor as "drained".
const _drainedDustCeilingSat = 546;

Future<void> main({bool isInitialized = false}) async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!isInitialized) await Bull.init();

  late final FundedBtcpay100Fixtures fixtures;

  setUpAll(() {
    // Fails fast with a clear refusal when the lane guard, mnemonic, pairing
    // URL, or handshake directory are missing (the smoke lane proves these).
    fixtures = FundedBtcpay100Fixtures.fromEnvironment();
  });

  test('funded BTCPay-100 journey: pair SamRock, receive on-chain BTC on wallet '
      '100, enable + fire autosweep to the default BTC wallet, then return the '
      'balance via the real Bitcoin Send flow', () async {
    _checkpoint(fixtures, 'env_check', data: {
      'run_id': fixtures.runId,
      'handshake_dir': fixtures.handshakeDir?.path,
      'target_amount_sat': fixtures.targetAmountSat,
      'max_fee_sat': fixtures.maxFeeSat,
    });

    final settings = await locator<GetSettingsUsecase>().execute();
    final environment = settings.environment;
    final network = environment.isMainnet ? 'bitcoin-mainnet' : 'bitcoin-testnet';

    // (a) The recipient wallet is OWNED BY THE APP. In the default (fresh) mode
    // we wipe and let the app generate a new seed on-device (no mnemonic
    // injected). In REUSE mode (attaching to a pairing armed by the pair-only
    // "preserve" lane) we do NOT wipe, so the persisted wallet + pairing in the
    // durable data dir / keyring survive. CreateDefaultWallets is idempotent: it
    // returns the existing default wallets when they are already present.
    if (!fixtures.reusePaired) {
      await wipeAppState(locator);
    }
    await locator<CreateDefaultWalletsUsecase>().execute();
    final defaultBitcoin = await _defaultBitcoinWallet(environment);
    _checkpoint(fixtures, 'wallet_created', data: {
      'default_bitcoin_wallet_id': defaultBitcoin.id,
      'master_fingerprint': defaultBitcoin.masterFingerprint,
      'network': network,
    });

    // (a.1) FUND-SAFETY: before ANY funds move, capture the app-generated
    // recovery material to a per-run mode-600 file. The same seed derives the
    // BTCPay wallet 100 (BIP85) and the default wallet, so this one capture
    // recovers everything. The words are read back through the app's own seed
    // store (the path RecoverBull uses) and are NEVER printed, logged, or
    // written to the handshake — only the file PATH and the public fingerprint
    // are checkpointed. This secret is kept entirely separate from the pairing
    // OTP and its redaction rules.
    final (mnemonicWords, _) = await locator<GetMnemonicFromFingerprintUsecase>()
        .execute(defaultBitcoin.masterFingerprint);
    final carryPath = await fixtures.captureRecoveryMaterial(
      mnemonicWords,
      masterFingerprint: defaultBitcoin.masterFingerprint,
    );
    _checkpoint(fixtures, 'recovery_captured', data: {
      'seed_carry_file': carryPath,
      'master_fingerprint': defaultBitcoin.masterFingerprint,
    });

    // Production Get Paid runs the shared automated-backup consent gate before
    // any pairing submission; mirror that ordering.
    await locator<GetPaidSettingsFacade>().setAutomatedBackupEnabled(true);

    // (b) Obtain the BTCPay connection. In REUSE mode, resolve the pairing the
    // pair-only lane already persisted (do NOT re-pair — a fresh OTP would be
    // required). Otherwise drive the REAL SamRock pairing with the credential
    // from the environment, which prepares the BTCPay Bitcoin + Liquid wallets
    // (BIP85 100) and submits the descriptors. The pairing URL is passed
    // straight into the usecase and never captured anywhere loggable.
    final BtcpayConnection connection;
    if (fixtures.reusePaired) {
      switch (await locator<GetBtcpayConnectionUsecase>().execute()) {
        case Ok(:final value):
          if (value == null) {
            fail('GETPAID_BTCPAY_REUSE_PAIRED is set but no persisted BTCPay '
                'connection was found; run the pair-only lane first under the '
                'same user/HOME (same data dir + keyring)');
          }
          connection = value;
        case Err(:final failure):
          fail(fixtures.redact('could not load the persisted BTCPay '
              'connection: ${failure.runtimeType}'));
      }
    } else {
      final pairing = await locator<CompleteBtcpaySamRockPairingUsecase>()
          .execute(pairingUrl: fixtures.pairingUrl);
      switch (pairing) {
        case Ok(:final value):
          connection = value;
        case Err(:final failure):
          // Only the failure TYPE is surfaced (never server text or the URL);
          // still routed through redact() as belt-and-braces.
          fail(fixtures.redact('BTCPay SamRock pairing failed: '
              '${failure.runtimeType}'));
      }
    }
    expect(connection.isPaired, isTrue,
        reason: 'pairing must reach the paired state');
    expect(connection.supportsBitcoinChain, isTrue,
        reason: 'the setup must include the btc-chain capability for wallet 100');
    _checkpoint(fixtures, 'paired', data: {
      'is_paired': connection.isPaired,
      'supports_bitcoin_chain': connection.supportsBitcoinChain,
    });

    // (c) Resolve wallet 100 (the BTCPay Bitcoin wallet). It is a plain on-chain
    // Bitcoin wallet and — per the RC default — ships with auto-sweep OFF.
    var wallet100 = await _btcpayBitcoinWallet(environment);
    if (!fixtures.reusePaired) {
      expect(wallet100.autoSweepEnabled, isFalse,
          reason: 'RC default: the BTCPay Bitcoin wallet is created with '
              'auto-sweep disabled (only the BTCPay Liquid wallet defaults on)');
    }
    if (!wallet100.autoSweepEnabled) {
      // The editable BTCPay details setting a user toggles to route BTCPay
      // Bitcoin receipts to their default wallet. In reuse mode the pair-only
      // lane already enabled + persisted this, so this is skipped.
      await locator<UpdateWalletBehaviorUsecase>().execute(
        walletId: wallet100.id,
        autoSweepEnabled: true,
      );
      wallet100 = await _btcpayBitcoinWallet(environment);
    }
    expect(wallet100.autoSweepEnabled, isTrue,
        reason: 'auto-sweep must be enabled on wallet 100 before the sweep');

    final wallet100Address = await locator<GetReceiveAddressUsecase>().execute(
      walletId: wallet100.id,
      generateNew: true,
    );
    final defaultBitcoinAddress = await locator<GetReceiveAddressUsecase>()
        .execute(walletId: defaultBitcoin.id, generateNew: true);
    _checkpoint(fixtures, 'wallet100_activated', data: {
      'btcpay100_wallet_id': wallet100.id,
      'auto_sweep_enabled': wallet100.autoSweepEnabled,
    });
    _checkpoint(fixtures, 'addresses_derived', data: {
      'btcpay100_receive_address': wallet100Address.address,
      'default_bitcoin_address': defaultBitcoinAddress.address,
    });

    // (d) Publish the offer (NO credential — only the derived on-chain
    // addresses + amounts), then wait for the payment to arrive via sync.
    await fixtures.writeJsonAtomic(fixtures.requestFile, {
      'schema': 'getpaid-btcpay100-funded/v1',
      'run_id': fixtures.runId,
      'network': network,
      'btcpay100_receive_address': wallet100Address.address,
      'default_bitcoin_address': defaultBitcoinAddress.address,
      'target_amount_sat': fixtures.targetAmountSat,
      'max_fee_sat': fixtures.maxFeeSat,
      'status': 'awaiting_payment',
      'written_at': DateTime.now().toUtc().toIso8601String(),
    });
    _checkpoint(fixtures, 'handshake_offer_written', data: {
      'request_file': fixtures.requestFile.path,
    });

    final target = BigInt.from(fixtures.targetAmountSat);
    final fundedWallet100 = await _pollWallet(
      fixtures,
      walletId: wallet100.id,
      timeout: fixtures.paymentTimeout,
      interval: fixtures.pollInterval,
      step: 'awaiting_payment',
      until: (w) => w.balanceSat >= target,
    );
    _checkpoint(fixtures, 'payment_detected', data: {
      'btcpay100_balance_sat': fundedWallet100.balanceSat.toString(),
    });

    // (e) The app's wallet state reflects the on-chain receipt on wallet 100.
    expect(fundedWallet100.balanceSat, greaterThanOrEqualTo(target));
    _checkpoint(fixtures, 'receipt_asserted', data: {
      'btcpay100_balance_sat': fundedWallet100.balanceSat.toString(),
    });

    // (f) Autosweep fires on sync: wallet 100 (BTC) drains into the default
    // BITCOIN wallet. The BTC sweep enforces a 3% fee cap, so a feePolicy skip
    // means the funded amount was too small for the prevailing fee rate — fail
    // loud so the operator re-funds with a larger amount.
    final defaultBefore = (await _syncWallet(defaultBitcoin.id)).balanceSat;
    final sweep = await locator<RunWalletAutoSweepUsecase>().execute(
      fundedWallet100,
    );
    final sweepTxid = switch (sweep) {
      AutosweepSwept(:final txid) => txid,
      AutosweepSkipped(:final reason) =>
        fail('autosweep skipped unexpectedly: $reason (a feePolicy skip means '
            'the funded amount is too small for the current BTC fee rate at the '
            '3% autosweep cap — re-fund with a larger amount)'),
      AutosweepFailed(:final error) =>
        fail(fixtures.redact('autosweep failed unexpectedly: $error')),
    };
    _checkpoint(fixtures, 'autosweep_swept', data: {'autosweep_txid': sweepTxid});

    final drained100 = await _pollWallet(
      fixtures,
      walletId: wallet100.id,
      timeout: fixtures.paymentTimeout,
      interval: fixtures.pollInterval,
      step: 'awaiting_sweep_drain',
      until: (w) => w.balanceSat <= BigInt.from(_drainedDustCeilingSat),
    );
    final defaultCredited = await _pollWallet(
      fixtures,
      walletId: defaultBitcoin.id,
      timeout: fixtures.paymentTimeout,
      interval: fixtures.pollInterval,
      step: 'awaiting_sweep_credit',
      until: (w) => w.balanceSat > defaultBefore,
    );
    expect(defaultCredited.balanceSat, greaterThan(defaultBefore));
    _checkpoint(fixtures, 'sweep_asserted', data: {
      'btcpay100_balance_sat': drained100.balanceSat.toString(),
      'default_bitcoin_balance_before_sat': defaultBefore.toString(),
      'default_bitcoin_balance_after_sat': defaultCredited.balanceSat.toString(),
    });

    final returnResult = await returnBitcoinToBullstr(
      walletId: defaultBitcoin.id,
      maxFeeSat: fixtures.maxFeeSat,
    );
    _checkpoint(fixtures, 'return_completed',
        data: returnResult.toEvidenceJson());

    // (h) Publish the final observed state for the coordinator's journal.
    final finalDefault = await _syncWallet(defaultBitcoin.id);
    final finalWallet100 = await _syncWallet(wallet100.id);
    await fixtures.writeJsonAtomic(fixtures.resultFile, {
      'schema': 'getpaid-btcpay100-funded-result/v1',
      'run_id': fixtures.runId,
      'network': network,
      'autosweep_txid': sweepTxid,
      ...returnResult.toEvidenceJson(),
      'final_btcpay100_balance_sat': finalWallet100.balanceSat.toString(),
      'final_default_bitcoin_balance_sat': finalDefault.balanceSat.toString(),
      'status': 'complete',
      'written_at': DateTime.now().toUtc().toIso8601String(),
    });
    _checkpoint(fixtures, 'result_written',
        data: {'result_file': fixtures.resultFile.path});
    _checkpoint(fixtures, 'done', data: {
      'autosweep_txid': sweepTxid,
      'return_txid': returnResult.lockupTxid,
    });
  }, timeout: const Timeout(Duration(minutes: 90)));
}

Future<Wallet> _defaultBitcoinWallet(Environment environment) async {
  final wallets = await locator<WalletRepository>().getWallets(
    environment: environment,
    onlyDefaults: true,
    onlyBitcoin: true,
  );
  if (wallets.isEmpty) {
    throw StateError('no default Bitcoin wallet after restore');
  }
  return wallets.first;
}

Future<Wallet> _btcpayBitcoinWallet(Environment environment) async {
  final wallets = await locator<WalletRepository>().getWallets(
    environment: environment,
    onlyBitcoin: true,
  );
  return wallets.firstWhere(
    (w) => w.label == _btcpayBitcoinWalletLabel && !w.isDefault,
    orElse: () => throw StateError(
      'BTCPay Bitcoin wallet 100 ($_btcpayBitcoinWalletLabel) not found after '
      'pairing',
    ),
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

Future<Wallet> _pollWallet(
  FundedBtcpay100Fixtures fixtures, {
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
      _checkpoint(fixtures, step, status: 'timeout', data: {
        'wallet_id': walletId,
        'attempts': attempt,
        'last_balance_sat': wallet.balanceSat.toString(),
      });
      throw StateError(
        '$step timed out after ${timeout.inSeconds}s (last balance '
        '${wallet.balanceSat} sat on $walletId)',
      );
    }
    _checkpoint(fixtures, step, status: 'waiting', data: {
      'attempt': attempt,
      'last_balance_sat': wallet.balanceSat.toString(),
    });
    await Future<void>.delayed(interval);
  }
}

/// Emits a single machine-readable checkpoint line, ALWAYS routed through the
/// fixtures' redactor so the pairing URL / OTP / merchant token can never appear
/// in the stream — even if a value here accidentally embedded one. Only
/// non-secret run metadata (addresses, txids, amounts, balances) is included.
void _checkpoint(
  FundedBtcpay100Fixtures fixtures,
  String step, {
  String status = 'ok',
  Map<String, Object?> data = const {},
}) {
  // ignore: avoid_print
  print(btcpayCheckpointLine(
    step,
    status: status,
    data: data,
    redactor: fixtures.redact,
  ));
}
