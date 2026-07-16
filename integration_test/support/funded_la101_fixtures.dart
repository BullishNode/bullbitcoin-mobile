import 'dart:convert';
import 'dart:io';

/// Lane guard for the funded Lightning-Address (wallet 101) journey. This lane
/// MOVES REAL FUNDS on Liquid mainnet and is driven by an external coordinator
/// through the handshake directory; it is never part of the default aggregate
/// integration run.
const fundedLa101LaneName = 'S-REAL-PROD-LA101-FUNDED';

// Scenario defaults.
//
// ROUTING FINDING (verified at f6eec5127 + the paired bullnym server): a payment
// to a Bull Lightning Address over the LIGHTNING rail settles into wallet 101
// via a Boltz **REVERSE submarine swap** (server source `lightning_boltz_reverse`,
// bullnym `db/invoices.rs`; the swap is created by the LNURL callback's
// `create_lightning_swap` → `create_reverse_swap {from:"BTC", to:"L-BTC"}`,
// bullnym `lnurl.rs`/`boltz.rs`). It is NOT a chain swap — a chain swap
// (`bitcoin_boltz_chain`) is only used when the LA is paid over the on-chain
// BITCOIN rail. The Boltz 25,000-sat CHAIN-swap minimum therefore does NOT bind
// on this witness; the only floors are the LNURL `min_sendable_msat`
// (100 sats on the paired server config) and Boltz's dynamic reverse-pair
// minimum (well below 2,000 sats on Liquid). So 2,000 sats is usable, exactly
// as on the direct-Liquid Page-102 witness.
//
// Unlike a direct-Liquid receive, the amount the payer sends over Lightning is
// reduced by the reverse-swap service + claim fee before it lands on wallet 101,
// so wallet 101 is credited `target - swap_fee`, not `target`. The spec reports
// the ACTUAL credited amount/outpoint from the app's wallet sync (the coordinator
// grades the resulting Liquid credit — LN leaves no independent chain artifact on
// the payer→receiver leg; see docs/CHAIN-ORACLE.md).
//
// Dust-margin (three Liquid hops after settlement: claim→wallet 101, autosweep
// drain 101→default, Mobile return default→coordinator), against the app's
// 100-sat autosweep dust floor (`RunAutoSweepUsecase._dustThresholdSat`) at the
// 0.1 sat/vByte min-relay rate: starting from ~1,850 sats credited (2,000 less a
// ~150-sat reverse-swap/claim cost), each ~100–150-sat hop leaves the final
// output near ~1,550 sats — ~15x the dust floor, well above the ≥3x margin we
// want. GETPAID_FUNDED_AMOUNT_SAT overrides it; raise the amount if a live Boltz
// reverse minimum or a fatter swap fee ever leaves too little margin.
const _defaultAmountSat = 2000;
const _defaultMaxFeeSat = 10000;
const _defaultFeeRateSatPerVb = 0.1;
const _defaultPaymentTimeoutSec = 900; // 15 minutes
const _defaultReturnTimeoutSec = 900; // 15 minutes
const _defaultPollIntervalSec = 15;

/// Run configuration for the funded LA-101 spec, resolved from the process
/// environment (operator-provided) with `--dart-define` fallbacks for device
/// runs.
///
/// The recipient wallet is NOT restored from an injected mnemonic: the spec
/// drives the app's own wallet-creation flow so the app GENERATES and OWNS its
/// seed on-device (matching a real customer, who is then auto-backed-up via the
/// Nostr keychain). As a fund-safety measure, before any funding the spec
/// captures that app-generated recovery material to [seedExportDir] (mode 0600,
/// uniquely named per run) so stranded funds are always recoverable. The
/// recovery words are NEVER logged, checkpointed, or written to the handshake
/// channel — only the export file path is surfaced.
class FundedLa101Fixtures {
  static const _laneDefine = String.fromEnvironment('GETPAID_E2E_LANE');
  static const _nymDefine = String.fromEnvironment('GETPAID_FUNDED_NYM');
  static const _runIdDefine = String.fromEnvironment('GETPAID_FUNDED_RUN_ID');
  static const _handshakeDefine = String.fromEnvironment(
    'GETPAID_FUNDED_HANDSHAKE_DIR',
  );
  static const _seedExportDefine = String.fromEnvironment(
    'GETPAID_FUNDED_SEED_EXPORT_DIR',
  );

  final String runId;
  final String nym;
  final Directory handshakeDir;
  final Directory seedExportDir;
  final int targetAmountSat;
  final int maxFeeSat;
  final double feeRateSatPerVb;
  final Duration paymentTimeout;
  final Duration returnTimeout;
  final Duration pollInterval;

  const FundedLa101Fixtures._({
    required this.runId,
    required this.nym,
    required this.handshakeDir,
    required this.seedExportDir,
    required this.targetAmountSat,
    required this.maxFeeSat,
    required this.feeRateSatPerVb,
    required this.paymentTimeout,
    required this.returnTimeout,
    required this.pollInterval,
  });

  factory FundedLa101Fixtures.fromEnvironment() {
    final env = Platform.environment;

    final lane = _firstNonEmpty([env['GETPAID_E2E_LANE'], _laneDefine]);
    if (lane != fundedLa101LaneName) {
      throw StateError(
        'GETPAID_E2E_LANE must be $fundedLa101LaneName for the funded '
        'LA-101 run (got: ${lane ?? '<unset>'})',
      );
    }

    // Handshake-channel refusal. Checked BEFORE any wallet or network work: a
    // funded journey with no channel back to the coordinator must fail fast and
    // loud rather than move funds it cannot report on. The smoke lane proves it.
    final handshakePath = _firstNonEmpty([
      env['GETPAID_FUNDED_HANDSHAKE_DIR'],
      _handshakeDefine,
    ]);
    if (handshakePath == null) {
      throw StateError(
        'GETPAID_FUNDED_HANDSHAKE_DIR is not set; refusing to run a funded '
        'LA-101 journey with no handshake directory to publish the Lightning '
        'Address to or read the return address from',
      );
    }
    final handshakeDir = Directory(handshakePath);
    if (!handshakeDir.existsSync()) {
      throw StateError(
        'GETPAID_FUNDED_HANDSHAKE_DIR ($handshakePath) does not exist; the '
        'coordinator must create the handshake directory before launch',
      );
    }

    // Fund-safety refusal. The app generates its OWN seed, so if we cannot
    // persist that seed's recovery material to a durable location we must NOT
    // fund the wallet — the funds would be unrecoverable if the ephemeral app
    // state is lost. Checked (like the handshake dir) before any wallet work.
    final seedExportPath = _firstNonEmpty([
      env['GETPAID_FUNDED_SEED_EXPORT_DIR'],
      _seedExportDefine,
    ]);
    if (seedExportPath == null) {
      throw StateError(
        'GETPAID_FUNDED_SEED_EXPORT_DIR is not set; refusing to create + fund '
        'an app-generated wallet with nowhere durable to persist its recovery '
        'material (fund-safety, fail-closed)',
      );
    }
    final seedExportDir = Directory(seedExportPath);
    if (!seedExportDir.existsSync()) {
      throw StateError(
        'GETPAID_FUNDED_SEED_EXPORT_DIR ($seedExportPath) does not exist; the '
        'operator must create the mode-0700 seed-carry directory before launch',
      );
    }

    final runId = _cleanNymPart(
      _firstNonEmpty([env['GETPAID_FUNDED_RUN_ID'], _runIdDefine]) ??
          DateTime.now().millisecondsSinceEpoch.toRadixString(36),
    );
    final configuredNym = _firstNonEmpty([
      env['GETPAID_FUNDED_NYM'],
      _nymDefine,
    ]);
    final nym = configuredNym == null
        ? 'bbe2ela101$runId'
        : _cleanNymPart(configuredNym);
    if (nym.isEmpty) {
      throw StateError('GETPAID_FUNDED_NYM produced an empty nym');
    }

    return FundedLa101Fixtures._(
      runId: runId,
      nym: nym,
      handshakeDir: handshakeDir,
      seedExportDir: seedExportDir,
      targetAmountSat: _intFromEnv(
        env['GETPAID_FUNDED_AMOUNT_SAT'],
        'GETPAID_FUNDED_AMOUNT_SAT',
        _defaultAmountSat,
      ),
      maxFeeSat: _intFromEnv(
        env['GETPAID_FUNDED_MAX_FEE_SAT'],
        'GETPAID_FUNDED_MAX_FEE_SAT',
        _defaultMaxFeeSat,
      ),
      feeRateSatPerVb: _doubleFromEnv(
        env['GETPAID_FUNDED_FEE_RATE'],
        'GETPAID_FUNDED_FEE_RATE',
        _defaultFeeRateSatPerVb,
      ),
      paymentTimeout: _durationFromEnvSec(
        env['GETPAID_FUNDED_PAYMENT_TIMEOUT_SEC'],
        'GETPAID_FUNDED_PAYMENT_TIMEOUT_SEC',
        _defaultPaymentTimeoutSec,
      ),
      returnTimeout: _durationFromEnvSec(
        env['GETPAID_FUNDED_RETURN_TIMEOUT_SEC'],
        'GETPAID_FUNDED_RETURN_TIMEOUT_SEC',
        _defaultReturnTimeoutSec,
      ),
      pollInterval: _durationFromEnvSec(
        env['GETPAID_FUNDED_POLL_INTERVAL_SEC'],
        'GETPAID_FUNDED_POLL_INTERVAL_SEC',
        _defaultPollIntervalSec,
      ),
    );
  }

  /// Spec -> coordinator: the Lightning Address + addresses + run parameters.
  /// Written once the LA is registered and wallet 101 exists, before the spec
  /// starts waiting for the payment.
  File get requestFile => _fileIn('la101_request.json');

  /// Coordinator -> spec: at minimum `return_address`; optionally `payment_txid`
  /// for the coordinator's own journal. Polled after the receipt/autosweep.
  File get responseFile => _fileIn('la101_response.json');

  /// Spec -> coordinator: the final observed state (receipt, autosweep + return
  /// txids and closing balances). Written last, atomically.
  File get resultFile => _fileIn('la101_result.json');

  File _fileIn(String name) =>
      File('${handshakeDir.path}${Platform.pathSeparator}$name');

  /// The durable, mode-0600 file this run's app-generated recovery material is
  /// written to (uniquely named per run + seed fingerprint). It lives OUTSIDE
  /// the repos and the handshake channel and is never committed.
  File seedBackupFile(String masterFingerprint) => File(
        '${seedExportDir.path}${Platform.pathSeparator}'
        'la101-$runId-$masterFingerprint.seed.json',
      );

  /// FUND-SAFETY: persist the app-generated recovery material so stranded funds
  /// are always recoverable. Writes atomically, then tightens the file to owner
  /// read/write only (0600). Returns the file path (the ONLY thing the caller
  /// may surface — never the words). The caller must ensure this runs BEFORE any
  /// funding.
  Future<String> writeSeedBackup({
    required String masterFingerprint,
    required List<String> mnemonicWords,
    String? passphrase,
    required String network,
  }) async {
    final file = seedBackupFile(masterFingerprint);
    final tmp = File('${file.path}.tmp');
    final payload = <String, Object?>{
      'schema': 'getpaid-la101-seed-backup/v1',
      'run_id': runId,
      'nym': nym,
      'network': network,
      'master_fingerprint': masterFingerprint,
      'mnemonic_words': mnemonicWords,
      'passphrase': passphrase,
      'captured_at': DateTime.now().toUtc().toIso8601String(),
      '_warning': 'SECRET recovery material. Do not print, commit, or share.',
    };
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    await tmp.rename(file.path);
    // dart:io has no chmod; use the platform tool to fence the secret to 0600.
    final chmod = await Process.run('chmod', ['600', file.path]);
    if (chmod.exitCode != 0) {
      throw StateError(
        'failed to chmod 600 the seed backup ${file.path}: ${chmod.stderr}',
      );
    }
    return file.path;
  }

  /// Atomic publish: write to a sibling temp file then rename over the target so
  /// the coordinator never observes a half-written document.
  Future<void> writeJsonAtomic(File file, Map<String, Object?> data) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
    await tmp.rename(file.path);
  }

  /// Reads and decodes a handshake file, or null when it is absent/unparseable
  /// (the caller keeps polling).
  Future<Map<String, Object?>?> readJson(File file) async {
    if (!file.existsSync()) return null;
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static String? _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  static String _cleanNymPart(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static int _intFromEnv(String? raw, String name, int fallback) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return fallback;
    final parsed = int.tryParse(value);
    if (parsed == null || parsed <= 0) {
      throw StateError('$name must be a positive integer (got: $value)');
    }
    return parsed;
  }

  static double _doubleFromEnv(String? raw, String name, double fallback) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return fallback;
    final parsed = double.tryParse(value);
    if (parsed == null || parsed <= 0) {
      throw StateError('$name must be a positive number (got: $value)');
    }
    return parsed;
  }

  static Duration _durationFromEnvSec(String? raw, String name, int fallback) {
    return Duration(seconds: _intFromEnv(raw, name, fallback));
  }
}
