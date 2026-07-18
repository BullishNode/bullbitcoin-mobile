import 'dart:convert';
import 'dart:io';

import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/ensure_swap_master_key_usecase.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/create_default_wallets_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/prepare_lightning_address_wallet_usecase.dart';
import 'package:bb_mobile/features/payment_page/domain/usecases/prepare_payment_page_wallet_usecase.dart';
import 'package:bb_mobile/features/pos/domain/usecases/prepare_pos_wallet_usecase.dart';
import 'package:bb_mobile/features/wallet/domain/usecase/run_wallet_auto_sweep_usecase.dart';
import 'package:bb_mobile/locator.dart';
import 'package:bb_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/return_liquid_to_bullstr.dart';
import 'support/wipe_app_state.dart';

const _lane = 'S-RECOVER-STRANDED-LIQUID';
const _drainedDustCeilingSat = 100;

Future<void> main({bool isInitialized = false}) async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!isInitialized) await Bull.init();

  test('captured funded-run seeds recover and return every spendable Liquid '
      'balance', () async {
    final manifest = await _RecoveryManifest.fromEnvironment();
    final results = <Map<String, Object?>>[];

    for (final recoveryCase in manifest.cases) {
      final result = await _recoverCase(manifest, recoveryCase);
      results.add(result);
    }

    await _writeJsonAtomic(manifest.resultFile, {
      'schema': 'getpaid-stranded-liquid-recovery-result/v1',
      'completed_at': DateTime.now().toUtc().toIso8601String(),
      'cases': results,
    });
  }, timeout: const Timeout(Duration(minutes: 45)));
}

Future<Map<String, Object?>> _recoverCase(
  _RecoveryManifest manifest,
  _RecoveryCase recoveryCase,
) async {
  final seed = await _readSeed(recoveryCase.seedFile);

  await wipeAppState(locator);
  await locator<CreateDefaultWalletsUsecase>().execute(
    mnemonicWords: seed.mnemonicWords,
    passphrase: seed.passphrase,
  );
  await locator<EnsureSwapMasterKeyUsecase>().execute();

  final defaultLiquid = await _defaultLiquidWallet();
  final productWalletId = await _prepareProductWallet(recoveryCase.product);

  var product = await _syncWallet(productWalletId);
  var defaultWallet = await _syncWallet(defaultLiquid.id);
  final openingProductSat = product.balanceSat;
  final openingDefaultSat = defaultWallet.balanceSat;
  String? autosweepTxid;

  if (product.balanceSat > BigInt.from(_drainedDustCeilingSat)) {
    final sweep = await locator<RunWalletAutoSweepUsecase>().execute(product);
    autosweepTxid = switch (sweep) {
      AutosweepSwept(:final txid) => txid,
      AutosweepSkipped(:final reason) => throw StateError(
        '${recoveryCase.id}: autosweep skipped: $reason',
      ),
      AutosweepFailed(:final error) => throw StateError(
        '${recoveryCase.id}: autosweep failed: $error',
      ),
    };
    product = await _pollWallet(
      productWalletId,
      until: (wallet) =>
          wallet.balanceSat <= BigInt.from(_drainedDustCeilingSat),
    );
    defaultWallet = await _pollWallet(
      defaultLiquid.id,
      until: (wallet) => wallet.balanceSat > openingDefaultSat,
    );
  }

  BullstrLiquidReturnResult? returnResult;
  if (defaultWallet.balanceSat > BigInt.from(_drainedDustCeilingSat)) {
    returnResult = await returnLiquidToBullstr(
      walletId: defaultLiquid.id,
      maxFeeSat: manifest.maxFeeSat,
      maximumResidualSat: _drainedDustCeilingSat,
    );
  }

  final finalProduct = await _syncWallet(productWalletId);
  final finalDefault = await _syncWallet(defaultLiquid.id);
  expect(
    finalProduct.balanceSat,
    lessThanOrEqualTo(BigInt.from(_drainedDustCeilingSat)),
    reason: '${recoveryCase.id}: product wallet was not drained',
  );
  expect(
    finalDefault.balanceSat,
    lessThanOrEqualTo(BigInt.from(_drainedDustCeilingSat)),
    reason: '${recoveryCase.id}: default wallet was not drained',
  );

  return {
    'id': recoveryCase.id,
    'product': recoveryCase.product.name,
    'opening_product_sat': openingProductSat.toString(),
    'opening_default_sat': openingDefaultSat.toString(),
    'autosweep_txid': autosweepTxid,
    'return_destination': bullstrReturnAddress,
    'return_swap_id': returnResult?.swapId,
    'return_lockup_txid': returnResult?.lockupTxid,
    'return_recipient_amount_sat': returnResult?.recipientAmountSat,
    'return_lockup_amount_sat': returnResult?.lockupAmountSat,
    'return_lockup_fee_sat': returnResult?.lockupFeeSat,
    'return_total_fee_sat': returnResult?.totalFeeSat,
    'return_residual_sat': returnResult?.residualSat,
    'return_status': returnResult?.terminalStatus.name,
    'return_recipient_paid_at': returnResult?.recipientPaidAt
        ?.toUtc()
        .toIso8601String(),
    'final_product_sat': finalProduct.balanceSat.toString(),
    'final_default_sat': finalDefault.balanceSat.toString(),
    'status': 'complete',
  };
}

Future<String> _prepareProductWallet(_Product product) async {
  return switch (product) {
    _Product.lightningAddress =>
      (await locator<PrepareLightningAddressWalletUsecase>().execute(
        scheduleBackup: false,
      )).walletId,
    _Product.paymentPage =>
      (await locator<PreparePaymentPageWalletUsecase>().execute()).walletId,
    _Product.pos =>
      (await locator<PreparePosWalletUsecase>().execute()).walletId,
  };
}

Future<Wallet> _defaultLiquidWallet() async {
  final settings = await locator<GetSettingsUsecase>().execute();
  final wallets = await locator<WalletRepository>().getWallets(
    environment: settings.environment,
    onlyDefaults: true,
    onlyLiquid: true,
  );
  if (wallets.isEmpty) throw StateError('default Liquid wallet is missing');
  return wallets.single;
}

Future<Wallet> _syncWallet(String walletId) async {
  final wallet = await locator<WalletRepository>().getWallet(
    walletId,
    sync: true,
  );
  if (wallet == null) throw StateError('wallet disappeared during recovery');
  return wallet;
}

Future<Wallet> _pollWallet(
  String walletId, {
  required bool Function(Wallet wallet) until,
}) async {
  final deadline = DateTime.now().add(const Duration(minutes: 5));
  while (true) {
    final wallet = await _syncWallet(walletId);
    if (until(wallet)) return wallet;
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('wallet recovery sync timed out');
    }
    await Future<void>.delayed(const Duration(seconds: 5));
  }
}

Future<_SeedMaterial> _readSeed(File file) async {
  final stat = await file.stat();
  if (stat.type != FileSystemEntityType.file || stat.mode & 0x3f != 0) {
    throw StateError('seed capture must be a mode-600 regular file');
  }
  final body = jsonDecode(await file.readAsString());
  if (body is! Map<String, dynamic>) {
    throw StateError('seed capture must contain a JSON object');
  }
  final rawWords = body['mnemonic_words'];
  if (rawWords is! List || rawWords.any((word) => word is! String)) {
    throw StateError('seed capture omitted mnemonic_words');
  }
  final words = rawWords.cast<String>();
  if (words.length != 12 && words.length != 24) {
    throw StateError('seed capture has an unsupported mnemonic length');
  }
  final passphrase = body['passphrase'];
  if (passphrase != null && passphrase is! String) {
    throw StateError('seed capture passphrase must be a string');
  }
  return _SeedMaterial(words, passphrase as String?);
}

Future<void> _writeJsonAtomic(File destination, Object body) async {
  await destination.parent.create(recursive: true);
  final temporary = File('${destination.path}.tmp');
  await temporary.writeAsString('${jsonEncode(body)}\n', flush: true);
  await temporary.setLastModified(DateTime.now());
  await temporary.rename(destination.path);
}

enum _Product { lightningAddress, paymentPage, pos }

class _RecoveryManifest {
  final int maxFeeSat;
  final List<_RecoveryCase> cases;
  final File resultFile;

  const _RecoveryManifest({
    required this.maxFeeSat,
    required this.cases,
    required this.resultFile,
  });

  static Future<_RecoveryManifest> fromEnvironment() async {
    if (Platform.environment['GETPAID_E2E_LANE'] != _lane) {
      throw StateError('GETPAID_E2E_LANE must be $_lane');
    }
    final path = Platform.environment['GETPAID_RECOVERY_MANIFEST'];
    if (path == null || path.isEmpty) {
      throw StateError('GETPAID_RECOVERY_MANIFEST is required');
    }
    final file = File(path);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file || stat.mode & 0x3f != 0) {
      throw StateError('recovery manifest must be a mode-600 regular file');
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw StateError('recovery manifest must contain a JSON object');
    }
    final maxFeeSat = decoded['max_fee_sat'];
    final resultFile = decoded['result_file'];
    final rawCases = decoded['cases'];
    if (maxFeeSat is! int || maxFeeSat <= 0 || maxFeeSat > 5000) {
      throw StateError('max_fee_sat must be between 1 and 5000');
    }
    if (resultFile is! String || resultFile.isEmpty) {
      throw StateError('recovery manifest omitted result_file');
    }
    if (rawCases is! List || rawCases.isEmpty) {
      throw StateError('recovery manifest omitted cases');
    }
    return _RecoveryManifest(
      maxFeeSat: maxFeeSat,
      cases: rawCases.map(_RecoveryCase.fromJson).toList(growable: false),
      resultFile: File(resultFile),
    );
  }
}

class _RecoveryCase {
  final String id;
  final _Product product;
  final File seedFile;

  const _RecoveryCase({
    required this.id,
    required this.product,
    required this.seedFile,
  });

  factory _RecoveryCase.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw StateError('recovery case must be a JSON object');
    }
    final id = value['id'];
    final productName = value['product'];
    final seedFile = value['seed_file'];
    if (id is! String ||
        id.isEmpty ||
        seedFile is! String ||
        seedFile.isEmpty) {
      throw StateError('recovery case omitted id or seed_file');
    }
    final product = switch (productName) {
      'lightning_address' => _Product.lightningAddress,
      'payment_page' => _Product.paymentPage,
      'pos' => _Product.pos,
      _ => throw StateError('unsupported recovery product'),
    };
    return _RecoveryCase(id: id, product: product, seedFile: File(seedFile));
  }
}

class _SeedMaterial {
  final List<String> mnemonicWords;
  final String? passphrase;

  const _SeedMaterial(this.mnemonicWords, this.passphrase);
}
