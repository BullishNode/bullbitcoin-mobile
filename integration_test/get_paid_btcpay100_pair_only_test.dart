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
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/test_wallet_backup/domain/usecases/get_mnemonic_from_fingerprint_usecase.dart';
import 'package:bb_mobile/locator.dart';
import 'package:bb_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/funded_btcpay100_fixtures.dart';

// S-REAL-PROD-BTCPAY100-FUNDED (PAIR-ONLY "preserve" variant): arms a live
// SamRock pairing and STOPS. It creates a wallet the app owns, captures its
// recovery material to the durable mode-0600 seed store, drives the REAL
// SamRock pairing against production (credential from GETPAID_BTCPAY_PAIRING_URL,
// never logged), asserts the pairing succeeded and the BTCPay Bitcoin wallet 100
// is present, enables auto-sweep on wallet 100 (a persisted setting — NO sweep
// is run), and stops. It NEVER funds, never invokes the payer, never runs the
// autosweep, and never returns funds.
//
// STATE PRESERVATION (the point of this lane): it does NOT wipe app state. The
// app's SQLite lives at a stable getApplicationDocumentsDirectory() path and the
// seeds + BTCPay connection live in the per-user secure-storage keyring, both of
// which persist across separate `flutter test` invocations. A later funded
// BTCPay run, launched under the same user/HOME (same data dir + same keyring)
// and WITHOUT wiping, therefore reuses this exact paired wallet + connection.
//
// This lane is excluded from the aggregate integration run and is launched only
// by its orchestration script.

const _btcpayBitcoinWalletLabel = 'BTCPay Bitcoin';

Future<void> main({bool isInitialized = false}) async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!isInitialized) await Bull.init();

  late final FundedBtcpay100Fixtures fixtures;

  setUpAll(() {
    // Fails fast when the lane guard or the pairing URL are missing.
    fixtures = FundedBtcpay100Fixtures.pairingOnly();
  });

  test('BTCPay-100 PAIR-ONLY: app-create wallet, capture recovery, LIVE SamRock '
      'pairing, enable wallet-100 auto-sweep, PERSIST — no funding', () async {
    _checkpoint(fixtures, 'env_check', data: {
      'run_id': fixtures.runId,
      'seed_carry_dir': fixtures.seedCarryDir.path,
    });

    final settings = await locator<GetSettingsUsecase>().execute();
    final environment = settings.environment;
    final network = environment.isMainnet ? 'bitcoin-mainnet' : 'bitcoin-testnet';

    // STATE PRESERVATION: deliberately DO NOT wipe. Passing no mnemonic makes
    // the app generate the seed on-device if none exists yet (and return the
    // existing default wallets if this durable store was already armed).
    await locator<CreateDefaultWalletsUsecase>().execute();
    final defaultBitcoin = await _defaultBitcoinWallet(environment);
    _checkpoint(fixtures, 'wallet_created', data: {
      'default_bitcoin_wallet_id': defaultBitcoin.id,
      'master_fingerprint': defaultBitcoin.masterFingerprint,
      'network': network,
    });

    // FUND-SAFETY: capture the app-generated recovery material to the per-run
    // mode-0600 carry BEFORE any later funding. Read through the app's own
    // GetMnemonicFromFingerprintUsecase; the words are written only to the carry
    // file, never printed/logged/checkpointed. Only the path + public
    // fingerprint are checkpointed.
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
    // any pairing submission; mirror that so the app's own automated backup is
    // also armed (the second recovery path).
    await locator<GetPaidSettingsFacade>().setAutomatedBackupEnabled(true);

    // LIVE SamRock pairing. The URL is passed straight into the usecase and
    // never captured anywhere loggable.
    final pairing = await locator<CompleteBtcpaySamRockPairingUsecase>()
        .execute(pairingUrl: fixtures.pairingUrl);
    final BtcpayConnection connection;
    switch (pairing) {
      case Ok(:final value):
        connection = value;
      case Err(:final failure):
        fail(fixtures.redact('BTCPay SamRock pairing failed: '
            '${failure.runtimeType}'));
    }
    expect(connection.isPaired, isTrue,
        reason: 'pairing must reach the paired state');
    expect(connection.supportsBitcoinChain, isTrue,
        reason: 'the setup must include the btc-chain capability for wallet 100');
    _checkpoint(fixtures, 'paired', data: {
      'is_paired': connection.isPaired,
      'supports_bitcoin_chain': connection.supportsBitcoinChain,
    });

    // Wallet 100 (the BTCPay Bitcoin wallet) is present/active after pairing.
    var wallet100 = await _btcpayBitcoinWallet(environment);
    // Enable auto-sweep on wallet 100 — a PERSISTED wallet-behavior flag, so the
    // later funded run inherits it. This does NOT run a sweep and moves no funds.
    await locator<UpdateWalletBehaviorUsecase>().execute(
      walletId: wallet100.id,
      autoSweepEnabled: true,
    );
    wallet100 = await _btcpayBitcoinWallet(environment);
    expect(wallet100.autoSweepEnabled, isTrue,
        reason: 'auto-sweep must be enabled + persisted on wallet 100 for the '
            'later funded run');

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

    // PRESERVE + STOP. No funding, no payer, no autosweep run, no return. The
    // paired wallet + connection now live in the durable app data dir + keyring.
    _checkpoint(fixtures, 'pair_preserved', data: {
      'note': 'paired state persisted in the durable app data dir + secure '
          'keyring; a later funded run under the same user/HOME reuses it',
    });
    _checkpoint(fixtures, 'pair_only_done', data: {
      'btcpay100_wallet_id': wallet100.id,
      'master_fingerprint': defaultBitcoin.masterFingerprint,
    });
  }, timeout: const Timeout(Duration(minutes: 10)));
}

Future<Wallet> _defaultBitcoinWallet(Environment environment) async {
  final wallets = await locator<WalletRepository>().getWallets(
    environment: environment,
    onlyDefaults: true,
    onlyBitcoin: true,
  );
  if (wallets.isEmpty) {
    throw StateError('no default Bitcoin wallet after create');
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

/// Emits a single machine-readable checkpoint line, ALWAYS routed through the
/// fixtures' redactor so the pairing URL / OTP / merchant token can never appear
/// in the stream. The recovery mnemonic is never placed here — only its file
/// path and the public fingerprint.
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
