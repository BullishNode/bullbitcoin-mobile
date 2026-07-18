import 'dart:convert';

import 'package:bb_mobile/core/blockchain/domain/usecases/broadcast_liquid_transaction_usecase.dart';
import 'package:bb_mobile/core/fees/domain/fees_entity.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/create_default_wallets_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_receive_address_usecase.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_connection.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_wallet.dart';
import 'package:bb_mobile/features/btcpay/domain/usecases/complete_btcpay_samrock_pairing_usecase.dart';
import 'package:bb_mobile/features/btcpay/domain/usecases/get_btcpay_connection_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/send/domain/usecases/calculate_liquid_absolute_fees_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/prepare_liquid_send_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/sign_liquid_tx_usecase.dart';
import 'package:bb_mobile/features/test_wallet_backup/domain/usecases/get_mnemonic_from_fingerprint_usecase.dart';
import 'package:bb_mobile/features/wallet/domain/usecase/run_wallet_auto_sweep_usecase.dart';
import 'package:bb_mobile/locator.dart';
import 'package:bb_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/funded_btcpay100_fixtures.dart';
import 'support/wipe_app_state.dart';

const _dustCeilingSat = 100;

Future<void> main({bool isInitialized = false}) async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!isInitialized) await Bull.init();

  late final FundedBtcpay100Fixtures fixtures;
  setUpAll(() => fixtures = FundedBtcpay100Fixtures.fromEnvironment());

  test(
    'funded BTCPay-100 Liquid journey receives, autosweeps, and returns funds',
    () async {
      final settings = await locator<GetSettingsUsecase>().execute();
      final environment = settings.environment;
      if (!fixtures.reusePaired) await wipeAppState(locator);
      await locator<CreateDefaultWalletsUsecase>().execute();

      final defaultLiquid = await _defaultLiquidWallet(environment);
      final (
        mnemonicWords,
        _,
      ) = await locator<GetMnemonicFromFingerprintUsecase>().execute(
        defaultLiquid.masterFingerprint,
      );
      final carryPath = await fixtures.captureRecoveryMaterial(
        mnemonicWords,
        masterFingerprint: defaultLiquid.masterFingerprint,
      );
      _checkpoint(fixtures, 'recovery_captured', {
        'seed_carry_file': carryPath,
        'master_fingerprint': defaultLiquid.masterFingerprint,
      });

      await locator<GetPaidSettingsFacade>().setAutomatedBackupEnabled(true);
      final BtcpayConnection connection;
      if (fixtures.reusePaired) {
        connection = switch (await locator<GetBtcpayConnectionUsecase>()
            .execute()) {
          Ok(value: final value?) => value,
          Ok() => throw TestFailure('no persisted BTCPay connection'),
          Err(:final failure) => throw TestFailure(
            'BTCPay connection lookup failed: ${failure.runtimeType}',
          ),
        };
      } else {
        connection =
            switch (await locator<CompleteBtcpaySamRockPairingUsecase>()
                .execute(pairingUrl: fixtures.pairingUrl)) {
              Ok(:final value) => value,
              Err(:final failure) => throw TestFailure(
                'BTCPay pairing failed: ${failure.runtimeType}',
              ),
            };
      }
      expect(connection.isPaired, isTrue);
      expect(connection.supportsLiquidChain, isTrue);

      final wallet100 = await _btcpayLiquidWallet(environment);
      expect(
        wallet100.autoSweepEnabled,
        isTrue,
        reason: 'BTCPay Liquid ships with autosweep enabled',
      );
      final walletAddress = await locator<GetReceiveAddressUsecase>().execute(
        walletId: wallet100.id,
        generateNew: true,
      );
      final defaultAddress = await locator<GetReceiveAddressUsecase>().execute(
        walletId: defaultLiquid.id,
        generateNew: true,
      );
      await fixtures.writeJsonAtomic(fixtures.requestFile, {
        'schema': 'getpaid-btcpay100-funded/v2',
        'run_id': fixtures.runId,
        'rail': 'liquid',
        'network': environment.isMainnet ? 'liquid-mainnet' : 'liquid-testnet',
        'btcpay100_receive_address': walletAddress.address,
        'default_liquid_address': defaultAddress.address,
        'target_amount_sat': fixtures.targetAmountSat,
        'max_fee_sat': fixtures.maxFeeSat,
        'status': 'awaiting_payment',
      });
      _checkpoint(fixtures, 'handshake_offer_written', {
        'request_file': fixtures.requestFile.path,
        'rail': 'liquid',
      });

      final target = BigInt.from(fixtures.targetAmountSat);
      final funded = await _pollWallet(
        fixtures,
        walletId: wallet100.id,
        until: (wallet) => wallet.balanceSat >= target,
        step: 'awaiting_payment',
      );
      final defaultBefore = (await _syncWallet(defaultLiquid.id)).balanceSat;
      final sweep = await locator<RunWalletAutoSweepUsecase>().execute(funded);
      final sweepTxid = switch (sweep) {
        AutosweepSwept(:final txid) => txid,
        AutosweepSkipped(:final reason) => throw TestFailure(
          'Liquid autosweep skipped: $reason',
        ),
        AutosweepFailed(:final error) => throw TestFailure(
          'Liquid autosweep failed: $error',
        ),
      };
      final drained = await _pollWallet(
        fixtures,
        walletId: wallet100.id,
        until: (wallet) => wallet.balanceSat <= BigInt.from(_dustCeilingSat),
        step: 'awaiting_sweep_drain',
      );
      final defaultCredited = await _pollWallet(
        fixtures,
        walletId: defaultLiquid.id,
        until: (wallet) => wallet.balanceSat > defaultBefore,
        step: 'awaiting_sweep_credit',
      );
      _checkpoint(fixtures, 'sweep_asserted', {
        'autosweep_txid': sweepTxid,
        'btcpay100_balance_sat': drained.balanceSat.toString(),
        'default_liquid_balance_before_sat': defaultBefore.toString(),
        'default_liquid_balance_after_sat': defaultCredited.balanceSat
            .toString(),
      });

      final returnAddress = await _pollReturnAddress(fixtures);
      final pset = await locator<PrepareLiquidSendUsecase>().execute(
        walletId: defaultLiquid.id,
        address: returnAddress,
        feeRate: NetworkFee.relativeFromSatPerVbyte(0.1),
        drain: true,
      );
      final feeSat = await locator<CalculateLiquidAbsoluteFeesUsecase>()
          .execute(pset: pset);
      expect(feeSat, lessThanOrEqualTo(fixtures.maxFeeSat));
      final signed = await locator<SignLiquidTxUsecase>().execute(
        pset: pset,
        walletId: defaultLiquid.id,
      );
      final returnTxid = await locator<BroadcastLiquidTransactionUsecase>()
          .execute(signed, isTestnet: environment.isTestnet);

      await fixtures.writeJsonAtomic(fixtures.resultFile, {
        'schema': 'getpaid-btcpay100-funded-result/v2',
        'run_id': fixtures.runId,
        'rail': 'liquid',
        'autosweep_txid': sweepTxid,
        'return_txid': returnTxid,
        'return_address': returnAddress,
        'return_fee_sat': feeSat,
        'final_btcpay100_balance_sat': (await _syncWallet(
          wallet100.id,
        )).balanceSat.toString(),
        'final_default_liquid_balance_sat': (await _syncWallet(
          defaultLiquid.id,
        )).balanceSat.toString(),
        'status': 'complete',
      });
      _checkpoint(fixtures, 'done', {
        'autosweep_txid': sweepTxid,
        'return_txid': returnTxid,
      });
    },
    timeout: const Timeout(Duration(minutes: 90)),
  );
}

Future<Wallet> _defaultLiquidWallet(Environment environment) async {
  final wallets = await locator<WalletRepository>().getWallets(
    environment: environment,
    onlyDefaults: true,
    onlyLiquid: true,
  );
  if (wallets.isEmpty) throw StateError('default Liquid wallet is missing');
  return wallets.first;
}

Future<Wallet> _btcpayLiquidWallet(Environment environment) async {
  final wallets = await locator<WalletRepository>().getWallets(
    environment: environment,
    onlyLiquid: true,
  );
  return wallets.firstWhere(
    (wallet) =>
        wallet.label == BtcpayWalletConstants.liquidLabel && !wallet.isDefault,
    orElse: () => throw StateError('BTCPay Liquid wallet 100 is missing'),
  );
}

Future<Wallet> _syncWallet(String walletId) async {
  final wallet = await locator<WalletRepository>().getWallet(
    walletId,
    sync: true,
  );
  if (wallet == null) throw StateError('wallet $walletId disappeared');
  return wallet;
}

Future<Wallet> _pollWallet(
  FundedBtcpay100Fixtures fixtures, {
  required String walletId,
  required bool Function(Wallet wallet) until,
  required String step,
}) async {
  final deadline = DateTime.now().add(fixtures.paymentTimeout);
  while (true) {
    final wallet = await _syncWallet(walletId);
    if (until(wallet)) return wallet;
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('$step timed out with ${wallet.balanceSat} sat');
    }
    await Future<void>.delayed(fixtures.pollInterval);
  }
}

Future<String> _pollReturnAddress(FundedBtcpay100Fixtures fixtures) async {
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

void _checkpoint(
  FundedBtcpay100Fixtures fixtures,
  String step,
  Map<String, Object?> data,
) {
  final line =
      'CHECKPOINT ${jsonEncode({'step': step, 'status': 'ok', 'ts': DateTime.now().toUtc().toIso8601String(), ...data})}';
  print(fixtures.redact(line));
}
