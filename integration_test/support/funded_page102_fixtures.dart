import 'dart:convert';
import 'dart:io';

/// Lane guard for the funded Page-102 journey. This lane MOVES REAL FUNDS on
/// Liquid mainnet and is driven by an external coordinator through the handshake
/// directory; it is never part of the default aggregate integration run.
const fundedPage102LaneName = 'S-REAL-PROD-PAGE102-FUNDED';

// Scenario defaults. This first witness funds wallet 102 by a DIRECT Liquid
// send (no Boltz chain swap), so the Boltz 25,000-sat swap minimum does NOT
// apply here — it binds only on the later BTC-rail witness. The amount is
// therefore the minimum practical value for the three-Liquid-hop journey
// (receipt on 102 -> autosweep drain -> Mobile return). At f6eec5127 each
// app-driven hop pays the 0.1 sat/vByte min-relay rate (RunAutoSweepUsecase +
// this spec's return send) — roughly 100-150 sats for a 1-in/2-out confidential
// tx — against a 100-sat autosweep dust floor
// (RunAutoSweepUsecase._dustThresholdSat). 2,000 sats leaves the final hop's
// output near ~1,700 sats, ~17x the dust floor (well above the 3x margin we
// want) without probing dust-edge behaviour. The max-fee ceiling stays well
// above any single hop's fee.
const _defaultAmountSat = 2000;
const _defaultMaxFeeSat = 10000;
const _defaultFeeRateSatPerVb = 0.1;
const _defaultPaymentTimeoutSec = 900; // 15 minutes
const _defaultReturnTimeoutSec = 900; // 15 minutes
const _defaultPollIntervalSec = 15;

/// Run configuration for the funded Page-102 spec, resolved from the process
/// environment (operator-provided) with `--dart-define` fallbacks for device
/// runs. The mnemonic is held only in memory and is NEVER logged or written to
/// the handshake channel.
class FundedPage102Fixtures {
  static const _laneDefine = String.fromEnvironment('GETPAID_E2E_LANE');
  static const _nymDefine = String.fromEnvironment('GETPAID_FUNDED_NYM');
  static const _runIdDefine = String.fromEnvironment('GETPAID_FUNDED_RUN_ID');
  static const _handshakeDefine = String.fromEnvironment(
    'GETPAID_FUNDED_HANDSHAKE_DIR',
  );

  final List<String> mnemonicWords;
  final String runId;
  final String nym;
  final Directory handshakeDir;
  final int targetAmountSat;
  final int maxFeeSat;
  final double feeRateSatPerVb;
  final Duration paymentTimeout;
  final Duration returnTimeout;
  final Duration pollInterval;

  const FundedPage102Fixtures._({
    required this.mnemonicWords,
    required this.runId,
    required this.nym,
    required this.handshakeDir,
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

    final mnemonic = _requiredMnemonic(
      env['GETPAID_FUNDED_MNEMONIC'],
      'GETPAID_FUNDED_MNEMONIC',
    );

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
      mnemonicWords: mnemonic,
      runId: runId,
      nym: nym,
      handshakeDir: handshakeDir,
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

  /// Spec -> coordinator: the payable addresses and the run parameters. Written
  /// once the Payment Page and wallet 102 exist, before the spec starts waiting
  /// for the payment.
  File get requestFile => _fileIn('page102_request.json');

  /// Coordinator -> spec: at minimum `return_address`; optionally `payment_txid`
  /// for the coordinator's own journal. Polled after the receipt/autosweep.
  File get responseFile => _fileIn('page102_response.json');

  /// Spec -> coordinator: the final observed state (autosweep + return txids and
  /// closing balances). Written last, atomically.
  File get resultFile => _fileIn('page102_result.json');

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

  static List<String> _requiredMnemonic(String? raw, String name) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) {
      throw StateError('$name must be set for the funded Page-102 run');
    }
    final words = value.split(RegExp(r'\s+'));
    if (words.length < 12) {
      throw StateError('$name must contain a complete mnemonic');
    }
    return words;
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
