import 'dart:io';

const liveNoPayLaneName = 'S-REAL-PROD-LIVE-NOPAY';

/// Fixtures for the live no-pay lane.
///
/// Permanent names (permanent_names_v1) make a wallet seed a one-name-for-life
/// identity: once a seed claims a nym, it can never claim another and no other
/// seed can take that nym. The suite therefore uses a DISTINCT throwaway seed
/// per test that registers, and every generated nym must fit the Bullnym public
/// name syntax (1-32 lowercase ASCII chars, no leading/trailing hyphen). These
/// seeds never hold funds.
///
/// Seed roles (each a separate env var; a fresh throwaway BIP39 mnemonic per
/// run, mode-600 storage, never printed):
///   - GETPAID_LIVE_NOPAY_MNEMONIC           registration + autobackup (test A)
///   - GETPAID_LIVE_NOPAY_PAGE_MNEMONIC      page/POS/invoice/recovery (test B)
///   - GETPAID_LIVE_NOPAY_TAKEOVER_MNEMONIC  anti-takeover owner (test 2)
///   - GETPAID_LIVE_NOPAY_SECONDARY_MNEMONIC anti-takeover attacker (test 2)
///   - GETPAID_LIVE_NOPAY_CLEAN_MNEMONIC     clean no-backup seed (test 3)
class LiveNoPayFixtures {
  static const _laneDefine = String.fromEnvironment('GETPAID_E2E_LANE');
  static const _nymDefine = String.fromEnvironment('GETPAID_LIVE_NOPAY_NYM');
  static const _runIdDefine = String.fromEnvironment(
    'GETPAID_LIVE_NOPAY_RUN_ID',
  );
  static const _preflightDefine = String.fromEnvironment(
    'GETPAID_LIVE_NOPAY_PREFLIGHT',
  );

  /// Opt-in (default OFF) burned-seed preflight lookup. Fresh-per-run seeds and
  /// [_assertDistinctSeeds] already cover the reuse risk, and each preflight is
  /// a public GET that eats into the server's per-source rate window (~30/60s),
  /// so the network preflight only runs when GETPAID_LIVE_NOPAY_PREFLIGHT is
  /// truthy (1/true/yes/on) — e.g. when debugging a suspected burned seed.
  static bool get preflightSeedCheckEnabled {
    final raw = _firstNonEmpty([
      Platform.environment['GETPAID_LIVE_NOPAY_PREFLIGHT'],
      _preflightDefine,
    ]);
    if (raw == null) return false;
    return const {'1', 'true', 'yes', 'on'}.contains(raw.toLowerCase());
  }

  /// BullnymPublicName syntax cap (bullnym_public_names.dart:56-58).
  static const int maxNymLength = 32;
  static const String _nymPrefix = 'bbe2e';
  static const int _maxRunTokenLength = 15;

  /// Scenario suffixes appended to [_nymBase] by [nymFor]. Kept here so the
  /// worst-case nym length can be checked once, at construction.
  static const String registrationScenario = '';
  static const String lifecycleScenario = 'life';
  static const String takeoverScenario = 'takeover';
  static const String noDisclosureScenario = 'nodisclosure';
  static const List<String> _allScenarios = [
    registrationScenario,
    lifecycleScenario,
    takeoverScenario,
    noDisclosureScenario,
  ];

  final List<String> registrationMnemonicWords;
  final List<String> lifecycleMnemonicWords;
  final List<String> takeoverOwnerMnemonicWords;
  final List<String> takeoverAttackerMnemonicWords;
  final List<String> cleanMnemonicWords;
  final String runId;
  final String _nymBase;

  const LiveNoPayFixtures._({
    required this.registrationMnemonicWords,
    required this.lifecycleMnemonicWords,
    required this.takeoverOwnerMnemonicWords,
    required this.takeoverAttackerMnemonicWords,
    required this.cleanMnemonicWords,
    required this.runId,
    required this._nymBase,
  });

  factory LiveNoPayFixtures.fromEnvironment() {
    final env = Platform.environment;
    final lane = _firstNonEmpty([env['GETPAID_E2E_LANE'], _laneDefine]);
    if (lane != liveNoPayLaneName) {
      throw StateError(
        'GETPAID_E2E_LANE must be $liveNoPayLaneName for live no-pay tests',
      );
    }

    final runId = _cleanNymPart(
      _firstNonEmpty([env['GETPAID_LIVE_NOPAY_RUN_ID'], _runIdDefine]) ??
          DateTime.now().millisecondsSinceEpoch.toRadixString(36),
    );
    final configuredNym = _firstNonEmpty([
      env['GETPAID_LIVE_NOPAY_NYM'],
      _nymDefine,
    ]);
    final nymBase = configuredNym == null
        ? '$_nymPrefix${_compactRunToken(runId)}'
        : _cleanNymPart(configuredNym);
    if (nymBase.isEmpty) {
      throw StateError('GETPAID_LIVE_NOPAY_NYM produced an empty nym');
    }
    // Fail fast on the length drift: the longest scenario nym must still fit
    // the 1-32 char Bullnym syntax. Guarding here means an over-long run token
    // is caught before any registration reaches the wire.
    _assertScenariosFit(nymBase);

    final registration = _requiredMnemonic(
      env['GETPAID_LIVE_NOPAY_MNEMONIC'],
      'GETPAID_LIVE_NOPAY_MNEMONIC',
    );
    final lifecycle = _requiredMnemonic(
      env['GETPAID_LIVE_NOPAY_PAGE_MNEMONIC'],
      'GETPAID_LIVE_NOPAY_PAGE_MNEMONIC',
    );
    final takeoverOwner = _requiredMnemonic(
      env['GETPAID_LIVE_NOPAY_TAKEOVER_MNEMONIC'],
      'GETPAID_LIVE_NOPAY_TAKEOVER_MNEMONIC',
    );
    final takeoverAttacker = _requiredMnemonic(
      env['GETPAID_LIVE_NOPAY_SECONDARY_MNEMONIC'],
      'GETPAID_LIVE_NOPAY_SECONDARY_MNEMONIC',
    );
    final clean = _requiredMnemonic(
      env['GETPAID_LIVE_NOPAY_CLEAN_MNEMONIC'],
      'GETPAID_LIVE_NOPAY_CLEAN_MNEMONIC',
    );

    // Every registering seed must be distinct: permanent names are one per
    // seed for life, so a shared (or already-burned) seed cannot satisfy two
    // tests. A duplicate here is a fixture-generation bug, not a test failure.
    _assertDistinctSeeds({
      'GETPAID_LIVE_NOPAY_MNEMONIC': registration,
      'GETPAID_LIVE_NOPAY_PAGE_MNEMONIC': lifecycle,
      'GETPAID_LIVE_NOPAY_TAKEOVER_MNEMONIC': takeoverOwner,
      'GETPAID_LIVE_NOPAY_SECONDARY_MNEMONIC': takeoverAttacker,
      'GETPAID_LIVE_NOPAY_CLEAN_MNEMONIC': clean,
    });

    return LiveNoPayFixtures._(
      registrationMnemonicWords: registration,
      lifecycleMnemonicWords: lifecycle,
      takeoverOwnerMnemonicWords: takeoverOwner,
      takeoverAttackerMnemonicWords: takeoverAttacker,
      cleanMnemonicWords: clean,
      runId: runId,
      nymBase: nymBase,
    );
  }

  /// The nym for a scenario, guaranteed to satisfy the Bullnym syntax. Throws
  /// if the composed nym would exceed [maxNymLength] (a fail-fast the caller
  /// should never hit, since [fromEnvironment] already checks every scenario).
  String nymFor(String scenario) {
    final suffix = _cleanNymPart(scenario);
    final nym = suffix.isEmpty ? _nymBase : '$_nymBase$suffix';
    if (nym.length > maxNymLength) {
      throw StateError(
        'Composed nym "$nym" is ${nym.length} chars; Bullnym allows at most '
        '$maxNymLength. Shorten GETPAID_LIVE_NOPAY_RUN_ID or the scenario tag.',
      );
    }
    return nym;
  }

  /// A short, collision-resistant token for the nym base. A numeric run id
  /// (a timestamp) is compressed to base-36; anything else is used as-is after
  /// normalization. Truncated so `prefix + token + longest suffix` always fits.
  static String _compactRunToken(String runId) {
    final cleaned = _cleanNymPart(runId);
    final digits = cleaned.replaceAll(RegExp(r'[^0-9]'), '');
    final token = (digits.isNotEmpty && digits == cleaned)
        ? (BigInt.tryParse(digits)?.toRadixString(36) ?? cleaned)
        : cleaned;
    return token.length > _maxRunTokenLength
        ? token.substring(0, _maxRunTokenLength)
        : token;
  }

  static void _assertScenariosFit(String nymBase) {
    for (final scenario in _allScenarios) {
      final suffix = _cleanNymPart(scenario);
      final length = nymBase.length + suffix.length;
      if (length > maxNymLength) {
        throw StateError(
          'nym base "$nymBase" + scenario "$scenario" is $length chars; '
          'Bullnym allows at most $maxNymLength. Use a shorter '
          'GETPAID_LIVE_NOPAY_RUN_ID / GETPAID_LIVE_NOPAY_NYM.',
        );
      }
    }
  }

  static void _assertDistinctSeeds(Map<String, List<String>> seeds) {
    final seen = <String, String>{};
    for (final entry in seeds.entries) {
      final key = entry.value.join(' ');
      final previous = seen[key];
      if (previous != null) {
        throw StateError(
          '${entry.key} and $previous share the same mnemonic; each test needs '
          'a FRESH seed (permanent names are one per seed for life).',
        );
      }
      seen[key] = entry.key;
    }
  }

  static List<String> _requiredMnemonic(String? raw, String name) {
    final words = _parseMnemonic(raw, name);
    if (words == null) {
      throw StateError('$name must be set for live no-pay tests');
    }
    return words;
  }

  static List<String>? _parseMnemonic(String? raw, String name) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
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
}
