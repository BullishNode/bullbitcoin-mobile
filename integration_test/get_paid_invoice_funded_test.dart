import 'dart:convert';

import 'package:bb_mobile/core/blockchain/domain/usecases/broadcast_bitcoin_transaction_usecase.dart';
import 'package:bb_mobile/core/blockchain/domain/usecases/broadcast_liquid_transaction_usecase.dart';
import 'package:bb_mobile/core/fees/domain/fees_entity.dart';
import 'package:bb_mobile/core/fees/domain/get_network_fees_usecase.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/wallet/data/repositories/bitcoin_wallet_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/create_default_wallets_usecase.dart';
import 'package:bb_mobile/features/invoices/public/invoices_facade.dart';
import 'package:bb_mobile/features/send/domain/usecases/calculate_liquid_absolute_fees_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/prepare_liquid_send_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/sign_bitcoin_tx_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/sign_liquid_tx_usecase.dart';
import 'package:bb_mobile/features/test_wallet_backup/domain/usecases/get_mnemonic_from_fingerprint_usecase.dart';
import 'package:bb_mobile/locator.dart';
import 'package:bb_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/funded_invoice_fixtures.dart';
import 'support/wipe_app_state.dart';

T _unwrap<T>(Result<T, InvoicesFailure> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final failure) => throw TestFailure(
    'Invoice operation failed: $failure',
  ),
};

Future<void> main({bool isInitialized = false}) async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!isInitialized) await Bull.init();

  late final FundedInvoiceFixtures fixtures;
  setUpAll(() => fixtures = FundedInvoiceFixtures.fromEnvironment());

  test('wallet-origin invoice settles exactly once over the selected rail and '
      'returns the received funds', () async {
    _checkpoint('env_check', {
      'run_id': fixtures.runId,
      'rail': fixtures.rail.name,
      'amount_sat': fixtures.amountSat,
    });

    final settings = await locator<GetSettingsUsecase>().execute();
    final environment = settings.environment;
    await wipeAppState(locator);
    await locator<CreateDefaultWalletsUsecase>().execute();

    final receivingWallet = await _defaultWallet(
      environment,
      bitcoin: fixtures.rail == FundedInvoiceRail.bitcoin,
    );
    final (
      mnemonicWords,
      passphrase,
    ) = await locator<GetMnemonicFromFingerprintUsecase>().execute(
      receivingWallet.masterFingerprint,
    );
    final seedCapture = await fixtures.writeSeedCapture({
      'schema': 'getpaid-invoice-seed-capture/v1',
      'run_id': fixtures.runId,
      'master_fingerprint': receivingWallet.masterFingerprint,
      'mnemonic_words': mnemonicWords,
      if (passphrase != null && passphrase.isNotEmpty) 'passphrase': passphrase,
      'captured_at': DateTime.now().toUtc().toIso8601String(),
    });
    _checkpoint('seed_captured', {'seed_capture_file': seedCapture});

    final balanceBefore = (await _syncWallet(receivingWallet.id)).balanceSat;
    final rail = fixtures.rail;
    final created = _unwrap(
      await locator<InvoicesFacade>().create(
        CreateInvoiceCommand(
          amountSat: fixtures.amountSat,
          acceptBtc: rail == FundedInvoiceRail.bitcoin,
          acceptLn: rail == FundedInvoiceRail.lightning,
          acceptLiquid: rail == FundedInvoiceRail.liquid,
          publicDescription: 'Funded invoice ${fixtures.runId}',
          privateMemo: 'QA funded invoice ${fixtures.runId}',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
        ),
      ),
    );
    final initial = _unwrap(
      await locator<InvoicesFacade>().status(created.invoiceId),
    );
    expect(initial.status, InvoiceStatus.unpaid);
    expect(created.shareUrl.value, contains('/invoice/'));
    final listedUnpaid = _unwrap(
      await locator<InvoicesFacade>().list(
        const ListInvoicesCommand(status: InvoiceStatus.unpaid),
      ),
    );
    expect(
      listedUnpaid.invoices.map((invoice) => invoice.id),
      contains(created.invoiceId),
    );
    final instruction = _paymentInstruction(initial, rail);
    expect(instruction.target, isNotEmpty);
    expect(instruction.amountSat, greaterThanOrEqualTo(fixtures.amountSat));

    await fixtures.writeJsonAtomic(fixtures.requestFile, {
      'schema': 'getpaid-invoice-funded/v1',
      'run_id': fixtures.runId,
      'rail': rail.name,
      'invoice_id': created.invoiceId.value,
      'share_url': created.shareUrl.value,
      'payment_target': instruction.target,
      'payer_amount_sat': instruction.amountSat,
      'merchant_amount_sat': fixtures.amountSat,
      'receiving_wallet_id': receivingWallet.id,
      'balance_before_sat': balanceBefore.toString(),
      'status': 'awaiting_payment',
    });
    _checkpoint('handshake_offer_written', {
      'request_file': fixtures.requestFile.path,
      'invoice_id': created.invoiceId.value,
    });

    final settled = await _pollInvoice(fixtures, created.invoiceId);
    expect(settled.status, InvoiceStatus.paid);
    expect(settled.paidVia, _paymentMethod(rail));
    expect(settled.paidAmountSat, fixtures.amountSat);
    expect(settled.paymentEvents, hasLength(1));
    final paymentEvent = settled.paymentEvents.single;
    expect(paymentEvent.rail, _paymentMethod(rail));
    expect(paymentEvent.amountSat, fixtures.amountSat);
    expect(paymentEvent.state, InvoicePaymentEventState.settled);
    final listedPaid = _unwrap(
      await locator<InvoicesFacade>().list(
        const ListInvoicesCommand(status: InvoiceStatus.paid),
      ),
    );
    expect(
      listedPaid.invoices.map((invoice) => invoice.id),
      contains(created.invoiceId),
    );

    final funded = await _pollWalletCredit(
      fixtures,
      walletId: receivingWallet.id,
      balanceBefore: balanceBefore,
    );
    _checkpoint('settlement_asserted', {
      'invoice_status': settled.status.wire,
      'paid_via': settled.paidVia!.name,
      'payment_event_count': settled.paymentEvents.length,
      'payment_txid': paymentEvent.transactionId,
      'wallet_balance_sat': funded.balanceSat.toString(),
    });

    final returnAddress = await _pollReturnAddress(fixtures);
    final (:txid, :feeSat) = rail == FundedInvoiceRail.bitcoin
        ? await _returnBitcoin(
            walletId: receivingWallet.id,
            address: returnAddress,
            maxFeeSat: fixtures.maxFeeSat,
          )
        : await _returnLiquid(
            walletId: receivingWallet.id,
            address: returnAddress,
            environment: environment,
            feeRateSatPerVb: fixtures.liquidFeeRateSatPerVb,
            maxFeeSat: fixtures.maxFeeSat,
          );

    final finalWallet = await _syncWallet(receivingWallet.id);
    await fixtures.writeJsonAtomic(fixtures.resultFile, {
      'schema': 'getpaid-invoice-funded-result/v1',
      'run_id': fixtures.runId,
      'rail': rail.name,
      'invoice_id': created.invoiceId.value,
      'paid_amount_sat': settled.paidAmountSat,
      'payment_event_count': settled.paymentEvents.length,
      'payment_txid': paymentEvent.transactionId,
      'return_txid': txid,
      'return_fee_sat': feeSat,
      'return_address': returnAddress,
      'final_wallet_balance_sat': finalWallet.balanceSat.toString(),
      'status': 'complete',
    });
    _checkpoint('done', {'return_txid': txid, 'return_fee_sat': feeSat});
  }, timeout: const Timeout(Duration(minutes: 90)));
}

({String target, int amountSat}) _paymentInstruction(
  InvoiceStatusSnapshot status,
  FundedInvoiceRail rail,
) => switch (rail) {
  FundedInvoiceRail.lightning => (
    target: status.lightningPr ?? '',
    amountSat: status.lightningPayerAmount?.payerAmountSat ?? 0,
  ),
  FundedInvoiceRail.liquid => (
    target: status.liquidAddress ?? '',
    amountSat: status.liquidPayerAmount?.payerAmountSat ?? 0,
  ),
  FundedInvoiceRail.bitcoin => (
    target: status.bitcoinChainBip21 ?? '',
    amountSat: status.bitcoinChainPayerAmount?.payerAmountSat ?? 0,
  ),
};

PaymentMethod _paymentMethod(FundedInvoiceRail rail) => switch (rail) {
  FundedInvoiceRail.bitcoin => PaymentMethod.btc,
  FundedInvoiceRail.lightning => PaymentMethod.lightning,
  FundedInvoiceRail.liquid => PaymentMethod.liquid,
};

Future<Wallet> _defaultWallet(
  Environment environment, {
  required bool bitcoin,
}) async {
  final wallets = await locator<WalletRepository>().getWallets(
    environment: environment,
    onlyDefaults: true,
    onlyBitcoin: bitcoin,
    onlyLiquid: !bitcoin,
  );
  if (wallets.isEmpty) throw StateError('default receiving wallet is missing');
  return wallets.first;
}

Future<Wallet> _syncWallet(String walletId) async {
  final wallet = await locator<WalletRepository>().getWallet(
    walletId,
    sync: true,
  );
  if (wallet == null) throw StateError('wallet $walletId disappeared');
  return wallet;
}

Future<InvoiceStatusSnapshot> _pollInvoice(
  FundedInvoiceFixtures fixtures,
  InvoiceId invoiceId,
) async {
  final deadline = DateTime.now().add(fixtures.paymentTimeout);
  while (true) {
    final status = _unwrap(await locator<InvoicesFacade>().status(invoiceId));
    if (status.isMonitoringComplete && status.hasPaymentEvidence) return status;
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('invoice settlement timed out at ${status.status.wire}');
    }
    await Future<void>.delayed(fixtures.pollInterval);
  }
}

Future<Wallet> _pollWalletCredit(
  FundedInvoiceFixtures fixtures, {
  required String walletId,
  required BigInt balanceBefore,
}) async {
  final deadline = DateTime.now().add(fixtures.paymentTimeout);
  while (true) {
    final wallet = await _syncWallet(walletId);
    if (wallet.balanceSat > balanceBefore) return wallet;
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('wallet credit did not arrive before timeout');
    }
    await Future<void>.delayed(fixtures.pollInterval);
  }
}

Future<String> _pollReturnAddress(FundedInvoiceFixtures fixtures) async {
  final deadline = DateTime.now().add(fixtures.returnTimeout);
  while (true) {
    final response = await fixtures.readJson(fixtures.responseFile);
    final address = response?['return_address'];
    if (address is String && address.trim().isNotEmpty) return address.trim();
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('coordinator did not provide a return address');
    }
    await Future<void>.delayed(fixtures.pollInterval);
  }
}

Future<({String txid, int feeSat})> _returnBitcoin({
  required String walletId,
  required String address,
  required int maxFeeSat,
}) async {
  final repository = locator<BitcoinWalletRepository>();
  final fees = await locator<GetNetworkFeesUsecase>().execute(isLiquid: false);
  final psbt = await repository.buildPsbt(
    walletId: walletId,
    address: address,
    networkFee: fees.economic,
    drain: true,
  );
  final feeSat = await repository.getTxFeeAmount(psbt: psbt);
  expect(feeSat, lessThanOrEqualTo(maxFeeSat));
  final signed = await locator<SignBitcoinTxUsecase>().execute(
    psbt: psbt,
    walletId: walletId,
  );
  final txid = await locator<BroadcastBitcoinTransactionUsecase>().execute(
    signed.signedPsbt,
    isPsbt: true,
  );
  return (txid: txid, feeSat: feeSat);
}

Future<({String txid, int feeSat})> _returnLiquid({
  required String walletId,
  required String address,
  required Environment environment,
  required double feeRateSatPerVb,
  required int maxFeeSat,
}) async {
  final pset = await locator<PrepareLiquidSendUsecase>().execute(
    walletId: walletId,
    address: address,
    feeRate: NetworkFee.relativeFromSatPerVbyte(feeRateSatPerVb),
    drain: true,
  );
  final feeSat = await locator<CalculateLiquidAbsoluteFeesUsecase>().execute(
    pset: pset,
  );
  expect(feeSat, lessThanOrEqualTo(maxFeeSat));
  final signed = await locator<SignLiquidTxUsecase>().execute(
    pset: pset,
    walletId: walletId,
  );
  final txid = await locator<BroadcastLiquidTransactionUsecase>().execute(
    signed,
    isTestnet: environment.isTestnet,
  );
  return (txid: txid, feeSat: feeSat);
}

void _checkpoint(String step, Map<String, Object?> data) {
  print(
    'CHECKPOINT ${jsonEncode({'step': step, 'status': 'ok', 'ts': DateTime.now().toUtc().toIso8601String(), ...data})}',
  );
}
