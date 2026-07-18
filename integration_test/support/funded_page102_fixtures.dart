import 'dart:convert';
import 'dart:io';

/// Lane guard for the funded Page-102 journey. This lane MOVES REAL FUNDS on
/// Liquid mainnet and is driven by an external coordinator through the handshake
/// directory; it is never part of the default aggregate integration run.
///
/// Page-102 is the Payment Page product (BIP85 wallet-seed index 102, a Liquid
/// wallet). Funds arrive by REAL Bullnym settlement over the page's Lightning
/// rail: the coordinator pays the page's server-hosted checkout, Bullnym does a
/// Boltz REVERSE submarine swap (LN->L-BTC) and claims the output into a
/// wallet-102 address derived from the page's (nym, donation) descriptor — not
/// by the payer sending directly to a pre-known app-derived address. A reverse
/// swap is NOT a Boltz CHAIN swap, so the 25,000-sat chain-swap minimum does NOT
/// apply — only the server's LNURL min_sendable bounds it from below.
///
/// The recipient wallet is CREATED and OWNED by the app itself (a fresh
/// on-device seed via the normal wallet-creation flow, auto-backed-up over
/// Nostr). No mnemonic is injected. Before any funding the app's own
/// show-mnemonic/backup-export path captures the recovery words to a durable
/// mode-0600 file (fund-safety) so an interrupted run is always recoverable; the
/// words are NEVER logged, printed, committed, or emitted on the handshake.
const fundedPage102LaneName = 'S-REAL-PROD-PAGE102-FUNDED';

/// Default durable location for the fund-safety recovery capture. One file per
/// run. Overridable with GETPAID_FUNDED_SEED_CAPTURE_DIR.
const _defaultSeedCaptureDir =
    '/home/francis/bull-bitcoin-workspace/.secrets-carry/getpaid-qa-seeds';

// Scenario defaults. 2,000 sats is the minimum practical value for the
// three-Liquid-hop journey (LN reverse-swap settlement onto 102, autosweep drain
// 102 -> default, return default -> coordinator), matching the POS-103 witness.
// At f6eec5127 each app-driven hop pays 0.1 sat/vByte against a 100-sat autosweep
// dust floor (RunAutoSweepUsecase._dustThresholdSat), so the final-hop output
// stays well above the dust edge. The reverse swap deducts a service fee, so
// wallet 102 receives slightly less than target; amount integrity is proven by
// the coordinator's known payer debit + global conservation, not by inspecting
// the confidential Liquid output amount on-chain.
const _defaultAmountSat = 2000;
const _defaultMaxFeeSat = 10000;
const _defaultFeeRateSatPerVb = 0.1;
const _defaultPaymentTimeoutSec = 900; // 15 minutes
const _defaultReturnTimeoutSec = 900; // 15 minutes
const _defaultPollIntervalSec = 15;

/// Run configuration for the funded Page-102 spec, resolved from the process
/// environment (operator-provided) with `--dart-define` fallbacks for device
/// runs. The environment variable names are the shared `GETPAID_FUNDED_*` set
/// (the coordinator reuses one contract across the funded witnesses); only the
/// lane guard value differs. NO mnemonic is injected — the app creates and owns
/// its own seed.
class FundedPage102Fixtures {
  static const _laneDefine = String.fromEnvironment('GETPAID_E2E_LANE');
  static const _nymDefine = String.fromEnvironment('GETPAID_FUNDED_NYM');
  static const _runIdDefine = String.fromEnvironment('GETPAID_FUNDED_RUN_ID');
  static const _handshakeDefine = String.fromEnvironment(
    'GETPAID_FUNDED_HANDSHAKE_DIR',
  );
  static const _seedCaptureDefine = String.fromEnvironment(
    'GETPAID_FUNDED_SEED_CAPTURE_DIR',
  );

  final String runId;
  final String nym;
  final Directory handshakeDir;
  final Directory seedCaptureDir;
  final bool fiatDenominated;
  final int fiatAmountMinor;
  final String fiatCurrency;
  final int targetAmountSat;
  final int maxFeeSat;
  final double feeRateSatPerVb;
  final Duration paymentTimeout;
  final Duration returnTimeout;
  final Duration pollInterval;

  const FundedPage102Fixtures._({
    required this.runId,
    required this.nym,
    required this.handshakeDir,
    required this.seedCaptureDir,
    required this.fiatDenominated,
    required this.fiatAmountMinor,
    required this.fiatCurrency,
    required this.targetAmountSat,
    required this.maxFeeSat,
    required this.feeRateSatPerVb,
    required this.paymentTimeout,
    required this.returnTimeout,
    required this.pollInterval,
  });

  factory FundedPage102Fixtures.fromEnvironment() {
    final env = Platform.environment;

    final lane = _firstNonEmpty([env['GETPAID_E2E_LANE'], _laneDefine]);
    if (lane != fundedPage102LaneName) {
      throw StateError(
        'GETPAID_E2E_LANE must be $fundedPage102LaneName for the funded '
        'Page-102 run (got: ${lane ?? '<unset>'})',
      );
    }

    // Handshake-channel refusal. This is deliberately checked BEFORE any wallet
    // or network work: a funded journey with no channel back to the coordinator
    // must fail fast and loud rather than move funds it cannot report on. The
    // smoke lane proves exactly this refusal.
    final handshakePath = _firstNonEmpty([
      env['GETPAID_FUNDED_HANDSHAKE_DIR'],
      _handshakeDefine,
    ]);
    if (handshakePath == null) {
      throw StateError(
        'GETPAID_FUNDED_HANDSHAKE_DIR is not set; refusing to run a funded '
        'Page-102 journey with no handshake directory to publish addresses to '
        'or read the return address from',
      );
    }
    final handshakeDir = Directory(handshakePath);
    if (!handshakeDir.existsSync()) {
      throw StateError(
        'GETPAID_FUNDED_HANDSHAKE_DIR ($handshakePath) does not exist; the '
        'coordinator must create the handshake directory before launch',
      );
    }

    // Fund-safety refusal: the app creates its own seed, so the ONLY durable
    // copy of the recovery words is the capture file this run writes before
    // funding. Refuse to proceed unless we can create/reach the capture dir.
    final seedCapturePath = _firstNonEmpty([
          env['GETPAID_FUNDED_SEED_CAPTURE_DIR'],
          _seedCaptureDefine,
        ]) ??
        _defaultSeedCaptureDir;
    final seedCaptureDir = Directory(seedCapturePath);
    try {
      seedCaptureDir.createSync(recursive: true);
    } catch (e) {
      throw StateError(
        'GETPAID_FUNDED_SEED_CAPTURE_DIR ($seedCapturePath) is not creatable; '
        'refusing to create + fund an app-owned wallet with nowhere durable to '
        'capture its recovery material: $e',
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
        ? 'bbe2epage102$runId'
        : _cleanNymPart(configuredNym);
    if (nym.isEmpty) {
      throw StateError('GETPAID_FUNDED_NYM produced an empty nym');
    }

    return FundedPage102Fixtures._(
      runId: runId,
      nym: nym,
      handshakeDir: handshakeDir,
      seedCaptureDir: seedCaptureDir,
      fiatDenominated: env['GETPAID_FUNDED_PRICING_MODE'] == 'fiat',
      fiatAmountMinor: _intFromEnv(
        env['GETPAID_FUNDED_FIAT_AMOUNT_MINOR'],
        'GETPAID_FUNDED_FIAT_AMOUNT_MINOR',
        100,
      ),
      fiatCurrency:
          _firstNonEmpty([env['GETPAID_FUNDED_FIAT_CURRENCY']]) ?? 'CAD',
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

  /// Spec -> coordinator: the page's Lightning checkout surface (public URL) and
  /// the run parameters. Written once the Payment Page and wallet 102 exist,
  /// before the spec starts waiting for the payment. The pay TARGET is the page
  /// checkout URL (the server mints the invoice and derives the wallet-102
  /// settlement address over the reverse swap), not a pre-known 102 address.
  File get requestFile => _fileIn('page102_request.json');

  /// Coordinator -> spec: at minimum `return_address`; optionally `payment_txid`
  /// for the coordinator's own journal. Polled after the receipt/autosweep.
  File get responseFile => _fileIn('page102_response.json');

  /// Spec -> coordinator: the final observed state (the discovered wallet-102
  /// receipt outpoint + app-read amount, autosweep + return txids, and closing
  /// balances). Written last, atomically.
  File get resultFile => _fileIn('page102_result.json');

  /// The durable, mode-0600 fund-safety recovery capture for THIS run. One file
  /// per run so a re-run never clobbers a prior wallet's material.
  File get seedCaptureFile =>
      File('${seedCaptureDir.path}${Platform.pathSeparator}$runId.seed.json');

  File _fileIn(String name) =>
      File('${handshakeDir.path}${Platform.pathSeparator}$name');

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

  /// Writes the fund-safety recovery capture with owner-only (0600) permissions,
  /// BEFORE funding. The content is the recovery material; it is written only to
  /// this local durable file and NEVER logged, printed, or sent on the
  /// handshake. Returns the absolute path (safe to reference in a checkpoint).
  Future<String> writeSeedCapture(Map<String, Object?> secret) async {
    final file = seedCaptureFile;
    // Create empty, lock down the mode, THEN write, so the secret bytes never
    // exist on disk under a world-readable mode even briefly.
    await file.create(recursive: true);
    await _chmod('600', file.path);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(secret),
      flush: true,
    );
    await _chmod('600', file.path);
    return file.path;
  }

  static Future<void> _chmod(String mode, String path) async {
    final result = await Process.run('chmod', [mode, path]);
    if (result.exitCode != 0) {
      throw StateError('chmod $mode $path failed: ${result.stderr}');
    }
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
