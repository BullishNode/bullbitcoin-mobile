import 'dart:convert';

import 'package:bb_mobile/core/blockchain/domain/usecases/broadcast_liquid_transaction_usecase.dart';
import 'package:bb_mobile/core/fees/domain/fees_entity.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/create_default_wallets_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_receive_address_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/payment_page/public/payment_page_facade.dart';
import 'package:bb_mobile/features/send/domain/usecases/calculate_liquid_absolute_fees_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/prepare_liquid_send_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/sign_liquid_tx_usecase.dart';
import 'package:bb_mobile/features/wallet/domain/usecase/run_wallet_auto_sweep_usecase.dart';
import 'package:bb_mobile/locator.dart';
import 'package:bb_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/funded_page102_fixtures.dart';
import 'support/wipe_app_state.dart';

// S-REAL-PROD-PAGE102-FUNDED: production Bullnym + production Nostr + real
// seed-derived keys against the live network. Unlike every other lane this one
// MOVES REAL FUNDS, so it never executes a payment on its own: it publishes the
// payable addresses to a handshake directory, WAITS for an external coordinator
// to fund wallet 102, observes the receipt + autosweep through the app's own
// wallet sync, then returns the funds via the app's real Liquid Send flow to an
// address the coordinator writes back. Every phase emits a machine-readable
// CHECKPOINT line so the coordinator can journal the run.
//
// The wallet-102 payment page wallet is created with the reserved label below;
// resolving it by label is the deterministic contract the app itself sets in
// PreparePaymentPageWalletUsecase.
const _paymentPageWalletLabel = 'Payment Page Liquid';

// Post-sweep the source wallet keeps at most the network dust it could not
// spend; treat anything at or below this as "drained".
const _drainedDustCeilingSat = 100;

Future<void> main({bool isInitialized = false}) async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!isInitialized) await Bull.init();

  late final FundedPage102Fixtures fixtures;

  setUpAll(() {
    // Fails fast with a clear refusal when the lane guard, mnemonic, or
    // handshake directory are missing (the smoke lane proves the last one).
    fixtures = FundedPage102Fixtures.fromEnvironment();
  });

  test('funded Page-102 journey: receive on 102, autosweep to the default '
      'Liquid wallet, then return the balance via the real Send flow', () async {
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

    // (a) Restore/create the QA wallet from the funded mnemonic. The mnemonic
    // never leaves this call — it is not logged or written to the handshake.
    await wipeAppState(locator);
    await locator<CreateDefaultWalletsUsecase>().execute(
      mnemonicWords: fixtures.mnemonicWords,
    );
    final defaultLiquid = await _defaultLiquidWallet(environment);
    _checkpoint('wallet_restored', data: {
      'default_liquid_wallet_id': defaultLiquid.id,
      'network': network,
    });

    // Payment page save reuses the shared Lightning Address nym, so register it
    // first (matches the production Get Paid onboarding order).
    await locator<GetPaidSettingsFacade>().acknowledgeBackupDisclosure(
      automatedBackupEnabled: true,
    );
    final registration = await locator<LightningAddressFacade>()
        .registerWalletOwned(nym: fixtures.nym);
    _checkpoint('lightning_registered', data: {
      'nym': registration.registration.nym,
    });

    // (b) Create the Payment Page; saving provisions wallet 102 (Liquid).
    final page = await locator<PaymentPageFacade>().save(
      SavePaymentPageCommand(
        header: 'Funded Page-102 ${fixtures.runId}',
        description: 'Authorized funded end-to-end coverage',
        displayCurrency: 'CAD',
        website: 'https://bullbitcoin.com',
      ),
    );
    expect(page.isActive, isTrue);
    expect(page.publicUrl, isNotEmpty);

    final page102 = await _paymentPageWallet(environment);
    expect(page102.autoSweepEnabled, isTrue,
        reason: 'wallet 102 must have autosweep enabled');
    final page102Address = await locator<GetReceiveAddressUsecase>().execute(
      walletId: page102.id,
      generateNew: true,
    );
    final defaultLiquidAddress = await locator<GetReceiveAddressUsecase>()
        .execute(walletId: defaultLiquid.id, generateNew: true);
    _checkpoint('page_created', data: {
      'page_public_url': page.publicUrl,
      'page102_wallet_id': page102.id,
    });
    _checkpoint('addresses_derived', data: {
      'page102_receive_address': page102Address.address,
      'default_liquid_address': defaultLiquidAddress.address,
    });

    // (c) Publish the offer, then wait for the payment to arrive via sync.
    await fixtures.writeJsonAtomic(fixtures.requestFile, {
      'schema': 'getpaid-page102-funded/v1',
      'run_id': fixtures.runId,
      'nym': fixtures.nym,
      'network': network,
      'page_public_url': page.publicUrl,
      'page102_receive_address': page102Address.address,
      'default_liquid_address': defaultLiquidAddress.address,
      'target_amount_sat': fixtures.targetAmountSat,
      'max_fee_sat': fixtures.maxFeeSat,
      'status': 'awaiting_payment',
      'written_at': DateTime.now().toUtc().toIso8601String(),
    });
    _checkpoint('handshake_offer_written', data: {
      'request_file': fixtures.requestFile.path,
    });

    final target = BigInt.from(fixtures.targetAmountSat);
    final fundedWallet102 = await _pollWallet(
      walletId: page102.id,
      timeout: fixtures.paymentTimeout,
      interval: fixtures.pollInterval,
      step: 'awaiting_payment',
      until: (w) => w.balanceSat >= target,
    );
    _checkpoint('payment_detected', data: {
      'page102_balance_sat': fundedWallet102.balanceSat.toString(),
    });

    // (d) The app's wallet state reflects the receipt on wallet 102.
    expect(fundedWallet102.balanceSat, greaterThanOrEqualTo(target));
    _checkpoint('receipt_asserted', data: {
      'page102_balance_sat': fundedWallet102.balanceSat.toString(),
    });

    // (e) Autosweep fires on sync: 102 drains into the default Liquid wallet.
    final defaultBefore =
        (await _syncWallet(defaultLiquid.id)).balanceSat;
    final sweep = await locator<RunWalletAutoSweepUsecase>().execute(
      fundedWallet102,
    );
    final sweepTxid = switch (sweep) {
      AutosweepSwept(:final txid) => txid,
      AutosweepSkipped(:final reason) =>
        fail('autosweep skipped unexpectedly: $reason'),
      AutosweepFailed(:final error) =>
        fail('autosweep failed unexpectedly: $error'),
    };
    _checkpoint('autosweep_swept', data: {'autosweep_txid': sweepTxid});

    final drained102 = await _pollWallet(
      walletId: page102.id,
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
      'page102_balance_sat': drained102.balanceSat.toString(),
      'default_liquid_balance_before_sat': defaultBefore.toString(),
      'default_liquid_balance_after_sat': defaultCredited.balanceSat.toString(),
    });

    // (f) Read the coordinator's return address, then drive the REAL Send flow
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

    // (g) Publish the final observed state for the coordinator's journal.
    final finalDefault = await _syncWallet(defaultLiquid.id);
    final finalPage102 = await _syncWallet(page102.id);
    await fixtures.writeJsonAtomic(fixtures.resultFile, {
      'schema': 'getpaid-page102-funded-result/v1',
      'run_id': fixtures.runId,
      'nym': fixtures.nym,
      'network': network,
      'autosweep_txid': sweepTxid,
      'return_txid': returnTxid,
      'return_address': returnAddress,
      'return_fee_sat': feeSat,
      'final_page102_balance_sat': finalPage102.balanceSat.toString(),
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

Future<Wallet> _paymentPageWallet(Environment environment) async {
  final wallets = await locator<WalletRepository>().getWallets(
    environment: environment,
    onlyLiquid: true,
  );
  return wallets.firstWhere(
    (w) => w.label == _paymentPageWalletLabel && !w.isDefault,
    orElse: () => throw StateError(
      'payment page wallet 102 ($_paymentPageWalletLabel) not found after save',
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

Future<String> _pollReturnAddress(FundedPage102Fixtures fixtures) async {
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
