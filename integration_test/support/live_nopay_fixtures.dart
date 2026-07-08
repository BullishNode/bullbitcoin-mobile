import 'dart:io';

const liveNoPayLaneName = 'S-REAL-PROD-LIVE-NOPAY';

class LiveNoPayFixtures {
  static const _laneDefine = String.fromEnvironment('GETPAID_E2E_LANE');
  static const _nymDefine = String.fromEnvironment('GETPAID_LIVE_NOPAY_NYM');
  static const _runIdDefine = String.fromEnvironment(
    'GETPAID_LIVE_NOPAY_RUN_ID',
  );

  final List<String> primaryMnemonicWords;
  final List<String> secondaryMnemonicWords;
  final List<String> cleanMnemonicWords;
  final String runId;
  final String _nymBase;

  const LiveNoPayFixtures._({
    required this.primaryMnemonicWords,
    required this.secondaryMnemonicWords,
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

    final primaryMnemonic = _requiredMnemonic(
      env['GETPAID_LIVE_NOPAY_MNEMONIC'],
      'GETPAID_LIVE_NOPAY_MNEMONIC',
    );
    final runId = _cleanNymPart(
      _firstNonEmpty([env['GETPAID_LIVE_NOPAY_RUN_ID'], _runIdDefine]) ??
          DateTime.now().millisecondsSinceEpoch.toRadixString(36),
    );
    final configuredNym = _firstNonEmpty([
      env['GETPAID_LIVE_NOPAY_NYM'],
      _nymDefine,
    ]);
    final nymBase = configuredNym == null
        ? 'bbe2enopay$runId'
        : _cleanNymPart(configuredNym);
    if (nymBase.isEmpty) {
      throw StateError('GETPAID_LIVE_NOPAY_NYM produced an empty nym');
    }

    return LiveNoPayFixtures._(
      primaryMnemonicWords: primaryMnemonic,
      secondaryMnemonicWords: _requiredMnemonic(
        env['GETPAID_LIVE_NOPAY_SECONDARY_MNEMONIC'],
        'GETPAID_LIVE_NOPAY_SECONDARY_MNEMONIC',
      ),
      cleanMnemonicWords: _requiredMnemonic(
        env['GETPAID_LIVE_NOPAY_CLEAN_MNEMONIC'],
        'GETPAID_LIVE_NOPAY_CLEAN_MNEMONIC',
      ),
      runId: runId,
      nymBase: nymBase,
    );
  }

  String nymFor(String scenario) {
    final suffix = _cleanNymPart(scenario);
    return suffix.isEmpty ? _nymBase : '$_nymBase$suffix';
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
