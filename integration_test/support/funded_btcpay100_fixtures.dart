import 'dart:convert';
import 'dart:io';

/// Lane guard for the funded BTCPay-100 journey. This lane MOVES REAL FUNDS on
/// Bitcoin mainnet and is driven by an external coordinator through the
/// handshake directory; it is never part of the default aggregate integration
/// run.
const fundedBtcpay100LaneName = 'S-REAL-PROD-BTCPAY100-FUNDED';

// Scenario defaults for the BTCPay on-chain BTC witness (BIP85 wallet index
// 100, the "BTCPay Bitcoin" wallet). Unlike the Page-102 / POS-103 Liquid
// witnesses this journey is on-chain BITCOIN, which changes the amount math in
// two ways verified against f6eec5127:
//
//  1. btc-chain SamRock receive is a PLAIN on-chain BTC receive into the
//     dedicated BTCPay Bitcoin wallet — NOT a Boltz chain swap (only btc-ln
//     uses a Boltz descriptor). So the 25,000-sat Boltz chain-swap minimum does
//     NOT bind here.
//  2. The BTC autosweep (RunAutoSweepUsecase._sweepBitcoin) enforces a 3% fee
//     cap (AutosweepFeePolicy.defaultBitcoinMaxFeePercent = 3.0): it SKIPS the
//     sweep when the drain fee exceeds 3% of the wallet balance. A ~110-vByte
//     1-in/1-out drain costs ~110 * feeRate sats, so the amount must satisfy
//     `0.03 * amount >= 110 * feeRate`. At 20,000 sats that only tolerates
//     ~5.4 sat/vByte; at 50,000 sats it tolerates ~13.6 sat/vByte. The default
//     is therefore 50,000 sats — comfortably above the BTC dust floor and large
//     enough that the autosweep is not fee-policy-skipped at realistic mainnet
//     economic fee rates. Raise it further before a run if mempool fees are
//     high (the spec fails loud with `autosweep skipped: feePolicy` if the
//     amount is too small for the prevailing rate).
const _defaultAmountSat = 50000;
// Ceiling asserted on the app's on-chain BTC return-send fee. This is the app's
// own Send (NOT the guarded payer), so it is NOT bound by the payer's
// MAX_INTENT_FEE_SAT = 5,000 hard cap; a BTC return tx can legitimately cost
// more than 5,000 sats during a fee spike, so the default headroom is generous.
const _defaultMaxFeeSat = 20000;
const _defaultPaymentTimeoutSec = 3600; // 60 minutes (on-chain confirmation)
const _defaultReturnTimeoutSec = 3600; // 60 minutes
const _defaultPollIntervalSec = 30;

/// Redacts URL-shaped pairing secrets from any text before it is emitted to a
/// log, CHECKPOINT line, handshake file, report, or error message.
///
/// It scrubs, in order: every explicitly-known secret (the runtime pairing URL
/// and any operator-supplied secret), any `otp=...` query value, any bearer /
/// token-like `token=...` value, and — defence in depth — any absolute `https`
/// URL that carries a SamRock protocol path or an `otp` parameter. The function
/// is pure and takes its secrets as an argument so it can be unit-tested with a
/// SAMPLE secret that is never the real credential.
String redactBtcpaySecrets(String input, {Iterable<String> secrets = const []}) {
  var out = input;
  for (final secret in secrets) {
    final trimmed = secret.trim();
    if (trimmed.isNotEmpty) {
      out = out.replaceAll(trimmed, _redactedMarker);
    }
  }
  // Query-parameter secrets (otp / token / access_token / secret / apikey).
  out = out.replaceAllMapped(
    RegExp(
      r'((?:otp|token|access_token|secret|apikey|api_key)=)[^&\s"' r"'" r']+',
      caseSensitive: false,
    ),
    (m) => '${m.group(1)}$_redactedMarker',
  );
  // Any https URL that looks like a SamRock pairing URL (has the protocol path
  // or an otp query) — replaced whole so no fragment of it can survive.
  out = out.replaceAllMapped(
    RegExp(
      r'https://[^\s"' r"'" r']*(?:/samrock/protocol|[?&]otp=)[^\s"' r"'" r']*',
      caseSensitive: false,
    ),
    (_) => _redactedMarker,
  );
  return out;
}

const _redactedMarker = '[REDACTED]';

/// Builds the single machine-readable `CHECKPOINT {json}` line the coordinator
/// journals. When a [redactor] is supplied the whole line is scrubbed through it
/// before it is returned, so a pairing secret can never survive into the emitted
/// stream even if a caller mistakenly puts one in [data]. Shared by the live
/// spec (which prints it) and the redaction test (which asserts a sample secret
/// never appears in the output).
String btcpayCheckpointLine(
  String step, {
  String status = 'ok',
  Map<String, Object?> data = const {},
  String Function(String)? redactor,
}) {
  final payload = <String, Object?>{
    'step': step,
    'status': status,
    'ts': DateTime.now().toUtc().toIso8601String(),
    ...data,
  };
  final line = 'CHECKPOINT ${jsonEncode(payload)}';
  return redactor == null ? line : redactor(line);
}

/// Run configuration for the funded BTCPay-100 spec, resolved from the process
/// environment (operator-provided) with `--dart-define` fallbacks for the lane
/// guard and handshake wiring. The mnemonic and the pairing URL are held only in
/// memory and are NEVER logged or written to the handshake channel.
class FundedBtcpay100Fixtures {
  static const _laneDefine = String.fromEnvironment('GETPAID_E2E_LANE');
  static const _runIdDefine = String.fromEnvironment('GETPAID_FUNDED_RUN_ID');
  static const _handshakeDefine = String.fromEnvironment(
    'GETPAID_FUNDED_HANDSHAKE_DIR',
  );

  final List<String> mnemonicWords;

  /// The real SamRock pairing URL. SECRET: read only from
  /// `GETPAID_BTCPAY_PAIRING_URL` at run time, never printed, never written to
  /// any handshake file, and always passed through [redact] before it could
  /// appear in a log or error.
  final String pairingUrl;

  final String runId;
  final Directory handshakeDir;
  final int targetAmountSat;
  final int maxFeeSat;
  final Duration paymentTimeout;
  final Duration returnTimeout;
  final Duration pollInterval;

  const FundedBtcpay100Fixtures._({
    required this.mnemonicWords,
    required this.pairingUrl,
    required this.runId,
    required this.handshakeDir,
    required this.targetAmountSat,
    required this.maxFeeSat,
    required this.paymentTimeout,
    required this.returnTimeout,
    required this.pollInterval,
  });

  factory FundedBtcpay100Fixtures.fromEnvironment() {
    final env = Platform.environment;

    final lane = _firstNonEmpty([env['GETPAID_E2E_LANE'], _laneDefine]);
    if (lane != fundedBtcpay100LaneName) {
      throw StateError(
        'GETPAID_E2E_LANE must be $fundedBtcpay100LaneName for the funded '
        'BTCPay-100 run (got: ${lane ?? '<unset>'})',
      );
    }

    final mnemonic = _requiredMnemonic(
      env['GETPAID_FUNDED_MNEMONIC'],
      'GETPAID_FUNDED_MNEMONIC',
    );

    // Credential refusal. The pairing URL is a short-lived secret the operator
    // sets from a mode-600 file at pairing time; a funded pairing with no
    // credential must fail fast and loud rather than start any wallet work. It
    // is only read from the process environment — never a --dart-define, so it
    // cannot be baked into a build artifact.
    final pairingUrl = env['GETPAID_BTCPAY_PAIRING_URL']?.trim();
    if (pairingUrl == null || pairingUrl.isEmpty) {
      throw StateError(
        'GETPAID_BTCPAY_PAIRING_URL is not set; refusing to run a funded '
        'BTCPay-100 pairing with no SamRock pairing URL. The operator sets it '
        'at run time from a mode-600 file (a fresh, short-lived OTP is minted '
        'at pairing time); it is never committed, logged, or --dart-defined.',
      );
    }

    // Handshake-channel refusal (mirrors the Page-102 lane): checked BEFORE any
    // wallet or network work so a funded journey with no channel back to the
    // coordinator fails fast rather than moving funds it cannot report on.
    final handshakePath = _firstNonEmpty([
      env['GETPAID_FUNDED_HANDSHAKE_DIR'],
      _handshakeDefine,
    ]);
    if (handshakePath == null) {
      throw StateError(
        'GETPAID_FUNDED_HANDSHAKE_DIR is not set; refusing to run a funded '
        'BTCPay-100 journey with no handshake directory to publish addresses to '
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

    final runId = _cleanRunId(
      _firstNonEmpty([env['GETPAID_FUNDED_RUN_ID'], _runIdDefine]) ??
          DateTime.now().millisecondsSinceEpoch.toRadixString(36),
    );

    return FundedBtcpay100Fixtures._(
      mnemonicWords: mnemonic,
      pairingUrl: pairingUrl,
      runId: runId,
      handshakeDir: handshakeDir,
      targetAmountSat: _intFromEnv(
        env['GETPAID_FUNDED_AMOUNT_SAT'],
        'GETPAID_FUNDED_AMOUNT_SAT',
        _defaultAmountSat,
      ),
      maxFeeSat: _intFromEnv(
        env['GETPAID_BTCPAY_MAX_FEE_SAT'] ?? env['GETPAID_FUNDED_MAX_FEE_SAT'],
        'GETPAID_BTCPAY_MAX_FEE_SAT',
        _defaultMaxFeeSat,
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

  /// Spec -> coordinator: the payable BTC addresses and the run parameters.
  /// Written once pairing has activated wallet 100 and its address is known,
  /// before the spec starts waiting for the payment. It carries NO credential —
  /// only the derived on-chain addresses and amounts.
  File get requestFile => _fileIn('btcpay100_request.json');

  /// Coordinator -> spec: at minimum `return_address` (a BTC address the
  /// coordinator controls). Polled after the receipt/autosweep.
  File get responseFile => _fileIn('btcpay100_response.json');

  /// Spec -> coordinator: the final observed state (autosweep + return txids and
  /// closing balances). Written last, atomically.
  File get resultFile => _fileIn('btcpay100_result.json');

  File _fileIn(String name) =>
      File('${handshakeDir.path}${Platform.pathSeparator}$name');

  /// Scrubs the pairing URL (and any URL-shaped secret / OTP / token) from
  /// [text]. Every log line, CHECKPOINT, handshake write, and error message
  /// that could conceivably carry the credential is routed through this.
  String redact(String text) =>
      redactBtcpaySecrets(text, secrets: [pairingUrl]);

  /// Atomic publish: write to a sibling temp file then rename over the target so
  /// the coordinator never observes a half-written document. The payload is
  /// redaction-scanned first: a funded run must never leave a credential on disk
  /// even by construction error.
  Future<void> writeJsonAtomic(File file, Map<String, Object?> data) async {
    final body = const JsonEncoder.withIndent('  ').convert(data);
    final scrubbed = redact(body);
    if (scrubbed != body) {
      throw StateError(
        'refusing to write ${file.path}: payload contained a pairing secret '
        '(handshake files must carry only derived addresses/amounts)',
      );
    }
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(body, flush: true);
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
      throw StateError('$name must be set for the funded BTCPay-100 run');
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

  static String _cleanRunId(String value) {
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

  static Duration _durationFromEnvSec(String? raw, String name, int fallback) {
    return Duration(seconds: _intFromEnv(raw, name, fallback));
  }
}
