import 'dart:convert';
import 'dart:io';

/// Lane guard for the funded BTCPay-100 journey. This lane MOVES REAL FUNDS on
/// Bitcoin mainnet and is driven by an external coordinator through the
/// handshake directory; it is never part of the default aggregate integration
/// run.
const fundedBtcpay100LaneName = 'S-REAL-PROD-BTCPAY100-FUNDED';

/// Default durable, mode-600 carry directory for the app-created wallet's
/// recovery material (fund-safety). It lives at the WORKSPACE root, OUTSIDE both
/// git repos, so it can never be committed by either repo. Overridable via
/// GETPAID_SEED_CARRY_DIR.
const _defaultSeedCarryDir =
    '/home/francis/bull-bitcoin-workspace/.secrets-carry/getpaid-qa-seeds';

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
///
/// This concerns ONLY the SamRock pairing credential. The app-created wallet's
/// recovery material (the mnemonic) is a DIFFERENT secret handled separately by
/// [FundedBtcpay100Fixtures.captureRecoveryMaterial]: it is written only to the
/// mode-600 carry file and is NEVER placed in any text that reaches this path.
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
/// guard and handshake wiring.
///
/// The recipient wallet is CREATED and OWNED by the app (the app generates the
/// seed on-device), so this lane does NOT take an injected mnemonic. As a
/// fund-safety measure the spec captures the app-generated recovery material to
/// a per-run mode-600 file via [captureRecoveryMaterial] before any funds move;
/// that material is NEVER printed, logged, committed, or routed through the
/// pairing-redaction path. The pairing URL is held only in memory and is never
/// written to any handshake file.
class FundedBtcpay100Fixtures {
  static const _laneDefine = String.fromEnvironment('GETPAID_E2E_LANE');
  static const _runIdDefine = String.fromEnvironment('GETPAID_FUNDED_RUN_ID');
  static const _handshakeDefine = String.fromEnvironment(
    'GETPAID_FUNDED_HANDSHAKE_DIR',
  );

  /// The real SamRock pairing URL. SECRET: read only from
  /// `GETPAID_BTCPAY_PAIRING_URL` at run time, never printed, never written to
  /// any handshake file, and always passed through [redact] before it could
  /// appear in a log or error.
  final String pairingUrl;

  final String runId;

  /// The coordinator handshake directory. Non-null for the funded lane; null in
  /// the pairing-only "preserve" lane (which has no coordinator and publishes no
  /// request/response/result files).
  final Directory? handshakeDir;

  /// Durable mode-600 directory the app-created wallet's recovery material is
  /// written into (one file per run). This is a fund-safety carry, kept OUT of
  /// git and OUT of the pairing-redaction path.
  final Directory seedCarryDir;

  final int targetAmountSat;
  final int maxFeeSat;
  final Duration paymentTimeout;
  final Duration returnTimeout;
  final Duration pollInterval;

  /// When true, the funded run REUSES a pairing already armed by the pair-only
  /// "preserve" lane: it does NOT wipe app state and does NOT re-pair; it
  /// resolves the persisted BTCPay connection + wallet 100 and funds those. Set
  /// via GETPAID_BTCPAY_REUSE_PAIRED=1. The pairing URL is then not required.
  final bool reusePaired;

  const FundedBtcpay100Fixtures._({
    required this.pairingUrl,
    required this.runId,
    required this.seedCarryDir,
    this.handshakeDir,
    required this.targetAmountSat,
    required this.maxFeeSat,
    required this.paymentTimeout,
    required this.returnTimeout,
    required this.pollInterval,
    this.reusePaired = false,
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

    // Credential refusal. The pairing URL is a short-lived secret the operator
    // sets from a mode-600 file at pairing time; a funded pairing with no
    // credential must fail fast and loud rather than start any wallet work. It
    // is only read from the process environment — never a --dart-define, so it
    // cannot be baked into a build artifact.
    final reusePaired = env['GETPAID_BTCPAY_REUSE_PAIRED'] == '1';

    // The pairing URL is required only when this run will PAIR. In reuse mode
    // (the funded run attaching to a pairing armed by the pair-only lane) no
    // pairing happens, so no credential is needed.
    final pairingUrl = env['GETPAID_BTCPAY_PAIRING_URL']?.trim() ?? '';
    if (pairingUrl.isEmpty && !reusePaired) {
      throw StateError(
        'GETPAID_BTCPAY_PAIRING_URL is not set; refusing to run a funded '
        'BTCPay-100 pairing with no SamRock pairing URL. The operator sets it '
        'at run time from a mode-600 file (a fresh, short-lived OTP is minted '
        'at pairing time); it is never committed, logged, or --dart-defined. '
        '(Set GETPAID_BTCPAY_REUSE_PAIRED=1 to reuse a pairing already armed by '
        'the pair-only lane instead.)',
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

    // Fund-safety carry directory for the app-generated recovery material.
    final seedCarryPath =
        _firstNonEmpty([env['GETPAID_SEED_CARRY_DIR']]) ?? _defaultSeedCarryDir;

    return FundedBtcpay100Fixtures._(
      pairingUrl: pairingUrl,
      runId: runId,
      handshakeDir: handshakeDir,
      seedCarryDir: Directory(seedCarryPath),
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
      reusePaired: reusePaired,
    );
  }

  /// Pairing-only "preserve" lane: same lane guard, pairing-URL credential, and
  /// fund-safety seed carry as the funded lane, but NO coordinator handshake
  /// (this lane pairs and stops; it publishes nothing and funds nothing). Used
  /// by get_paid_btcpay100_pair_only_test.dart to arm a paired wallet whose
  /// state is preserved for a later funded run.
  factory FundedBtcpay100Fixtures.pairingOnly() {
    final env = Platform.environment;

    final lane = _firstNonEmpty([env['GETPAID_E2E_LANE'], _laneDefine]);
    if (lane != fundedBtcpay100LaneName) {
      throw StateError(
        'GETPAID_E2E_LANE must be $fundedBtcpay100LaneName for the BTCPay-100 '
        'pairing-only run (got: ${lane ?? '<unset>'})',
      );
    }

    final pairingUrl = env['GETPAID_BTCPAY_PAIRING_URL']?.trim();
    if (pairingUrl == null || pairingUrl.isEmpty) {
      throw StateError(
        'GETPAID_BTCPAY_PAIRING_URL is not set; refusing to run BTCPay-100 '
        'pairing with no SamRock pairing URL. The operator sets it at run time '
        'from a mode-600 file (a fresh, short-lived OTP is minted at pairing '
        'time); it is never committed, logged, or --dart-defined.',
      );
    }

    final runId = _cleanRunId(
      _firstNonEmpty([env['GETPAID_FUNDED_RUN_ID'], _runIdDefine]) ??
          DateTime.now().millisecondsSinceEpoch.toRadixString(36),
    );
    final seedCarryPath =
        _firstNonEmpty([env['GETPAID_SEED_CARRY_DIR']]) ?? _defaultSeedCarryDir;

    return FundedBtcpay100Fixtures._(
      pairingUrl: pairingUrl,
      runId: runId,
      seedCarryDir: Directory(seedCarryPath),
      targetAmountSat: _defaultAmountSat,
      maxFeeSat: _defaultMaxFeeSat,
      paymentTimeout: const Duration(seconds: _defaultPaymentTimeoutSec),
      returnTimeout: const Duration(seconds: _defaultReturnTimeoutSec),
      pollInterval: const Duration(seconds: _defaultPollIntervalSec),
    );
  }

  /// Spec -> coordinator: the payable BTC addresses and the run parameters.
  /// Written once pairing has activated wallet 100 and its address is known,
  /// before the spec starts waiting for the payment. It carries NO credential
  /// and NO recovery material — only the derived on-chain addresses and amounts.
  File get requestFile => _fileIn('btcpay100_request.json');

  /// Coordinator -> spec: at minimum `return_address` (a BTC address the
  /// coordinator controls). Polled after the receipt/autosweep.
  File get responseFile => _fileIn('btcpay100_response.json');

  /// Spec -> coordinator: the final observed state (autosweep + return txids and
  /// closing balances). Written last, atomically.
  File get resultFile => _fileIn('btcpay100_result.json');

  File _fileIn(String name) =>
      File('${handshakeDir!.path}${Platform.pathSeparator}$name');

  /// The per-run mode-600 file the recovery material is captured into
  /// (`<runId>.txt`, unique per run — the operator supplies a unique run id).
  File get seedCarryFile =>
      File('${seedCarryDir.path}${Platform.pathSeparator}$runId.txt');

  /// FUND-SAFETY: durably captures the APP-GENERATED wallet's recovery material
  /// (the mnemonic + master fingerprint) into a per-run mode-600 file BEFORE any
  /// funds move, so a crashed/lost run is always recoverable. The words are a
  /// secret DISTINCT from the pairing OTP: they are written only here, with
  /// `0700` on the directory and `0600` on the file, and are NEVER printed,
  /// logged, committed, or routed through [redact]. Returns the file path (the
  /// path is not a secret; the words inside it are). Fail-closed: if the file
  /// cannot be created with restrictive permissions, the caller must not fund.
  Future<String> captureRecoveryMaterial(
    List<String> mnemonicWords, {
    required String masterFingerprint,
  }) async {
    if (mnemonicWords.length < 12) {
      throw StateError(
        'refusing to capture recovery material: mnemonic looks incomplete '
        '(${mnemonicWords.length} words)',
      );
    }
    seedCarryDir.createSync(recursive: true);
    await _chmod('700', seedCarryDir.path);
    // Defence in depth: if this directory ever lands inside a git repo, ignore
    // everything in it so the recovery material can never be committed.
    final ignore = File(
      '${seedCarryDir.path}${Platform.pathSeparator}.gitignore',
    );
    if (!ignore.existsSync()) ignore.writeAsStringSync('*\n', flush: true);

    final file = seedCarryFile;
    // Create the file empty with 0600 BEFORE writing the secret, so the words
    // are never briefly world-readable on disk.
    file.writeAsStringSync('', flush: true);
    await _chmod('600', file.path);
    // Plaintext carry: two comment header lines (run id + fingerprint + a loud
    // do-not-share note) then the mnemonic on its own line. The words live ONLY
    // in this mode-600 file — never a checkpoint, handshake, or log.
    final buffer = StringBuffer()
      ..writeln('# getpaid-qa fund-safety recovery material (scenario=btcpay100)')
      ..writeln('# run_id=$runId master_fingerprint=$masterFingerprint '
          'network=bitcoin-mainnet captured_at='
          '${DateTime.now().toUtc().toIso8601String()}')
      ..writeln('# APP-CREATED wallet. DO NOT print/commit/share. Restore this '
          'mnemonic into the app to recover funds if a run is interrupted.')
      ..writeln(mnemonicWords.join(' '));
    file.writeAsStringSync(buffer.toString(), flush: true);
    await _chmod('600', file.path);
    return file.path;
  }

  static Future<void> _chmod(String mode, String path) async {
    final result = await Process.run('chmod', [mode, path]);
    if (result.exitCode != 0) {
      throw StateError(
        'failed to chmod $mode $path (recovery material must be restricted '
        'before it holds a secret): ${result.stderr}',
      );
    }
  }

  /// Scrubs the pairing URL (and any URL-shaped secret / OTP / token) from
  /// [text]. Every log line, CHECKPOINT, handshake write, and error message
  /// that could conceivably carry the credential is routed through this. It does
  /// NOT touch the recovery mnemonic — that never reaches any text this guards.
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
