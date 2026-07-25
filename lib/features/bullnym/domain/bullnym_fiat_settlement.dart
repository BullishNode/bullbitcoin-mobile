// Bullnym fiat-settlement wire domain types.
//
// The client submits signed per-product fiat-settlement configuration and
// reads back the server-owned configuration. It performs no eligibility, FX,
// KYC, routing, or order logic — those are entirely server-owned.

/// The Bullnym contract version pinned into every fiat-settlement request.
const int bullnymFiatSettlementContractVersion = 1;

/// The four Get Paid products, each configured independently. The [wire] value
/// is the exact server path segment / signed-field string.
enum BullnymFiatSettlementProduct {
  lightningAddress('lightning_address'),
  paymentPage('payment_page'),
  pos('pos'),
  invoice('invoice');

  const BullnymFiatSettlementProduct(this.wire);

  final String wire;
}

/// Coarse settlement classification for a received Get Paid payment, shown as
/// the single label in history lists. `unavailable` is the fail-closed value
/// for anything this client version cannot confidently interpret — it must
/// NEVER be silently shown as Bitcoin-only.
enum BullnymSettlementKind { bitcoin, fiat, mixed, unavailable }

/// Per-leg lifecycle. Fiat legs are `pending`, `settled`, or `unavailable`;
/// Bitcoin legs are `pending`, `settled`, or `problem`. `unknown` is retained
/// for exhaustive switches but the strict parser never produces it — an
/// unrecognized leg status invalidates the whole projection instead.
enum BullnymSettlementLegStatus {
  pending,
  settled,
  problem,
  unavailable,
  unknown,
}

/// Why a configured fiat conversion was overridden to all-Bitcoin.
enum BullnymFiatConversionOverrideReason {
  belowMinimum,
  invalidSplit,
  conversionUnavailable,
  unknown,
}

/// One fiat settlement order (private, merchant-only). `amountMinor` is the
/// credited amount, present only once settled. `quotedAmountMinor` is the fiat
/// amount locked at order creation; it is present (strictly positive) whenever
/// a quote is known — for pending legs as well as settled ones — and null for a
/// legacy row predating the quote column or an unavailable leg.
/// `executionRateMinorPerBtc` is R2 — Bull Bitcoin's real execution rate for
/// this leg, denominated in the LEG's own [currency]; it is present (strictly
/// positive) only once the leg has settled and null for a legacy/pending leg.
class BullnymFiatSettlementLeg {
  final int? amountMinor;
  final int? quotedAmountMinor;
  final int? executionRateMinorPerBtc;
  final String currency;
  final String orderId;
  final BullnymSettlementLegStatus status;

  const BullnymFiatSettlementLeg({
    required this.amountMinor,
    required this.currency,
    required this.orderId,
    required this.status,
    this.quotedAmountMinor,
    this.executionRateMinorPerBtc,
  });
}

/// The Bitcoin-wallet portion of a mixed settlement.
class BullnymBitcoinSettlementLeg {
  final int amountSat;
  final String network;
  final BullnymSettlementLegStatus status;

  const BullnymBitcoinSettlementLeg({
    required this.amountSat,
    required this.network,
    required this.status,
  });
}

/// Private, structured settlement projection for one Get Paid payment.
///
/// Parsing is tolerant-outer / strict-inner: any JSON-type surprise or any
/// value this client version cannot confidently interpret fails closed to
/// [BullnymSettlementKind.unavailable] (empty legs, no override) rather than
/// throwing or fabricating a breakdown. Classification is read from the
/// authoritative top-level `settlement_kind`; it is NEVER derived from field
/// presence or from `settlement_details.kind` alone.
class BullnymGetPaidSettlement {
  final BullnymSettlementKind kind;
  final List<BullnymFiatSettlementLeg> fiat;
  final List<BullnymBitcoinSettlementLeg> bitcoin;
  final BullnymFiatConversionOverrideReason? overrideReason;

  /// The captured split percentage that applied at payment time (`100` for a
  /// `fiat` kind, `1..=99` for `mixed`). Null for a legacy row predating the
  /// captured column. Never re-read from current product config.
  final int? fiatPercentage;

  /// R1 — the invoice-creation reference rate (minor units per BTC), from the
  /// quote captured when the invoice was created. Denominated in the invoice
  /// FACE currency ([creationRateCurrency]), NOT the leg currency. Present
  /// (strictly positive) only for a fiat-priced invoice on a server that sends
  /// it; null for a sat-priced invoice or a legacy/old-server row.
  final int? creationRateMinorPerBtc;

  /// The FACE currency that [creationRateMinorPerBtc] is denominated in. Travels
  /// with the rate on `settlement_details` because the invoice face currency can
  /// differ from a fiat leg's currency (e.g. face USD, leg CAD) and is not
  /// otherwise carried on a history row. Null when the rate is absent or the
  /// server names no currency for it (the rate then cannot be rendered).
  final String? creationRateCurrency;

  const BullnymGetPaidSettlement({
    required this.kind,
    this.fiat = const [],
    this.bitcoin = const [],
    this.overrideReason,
    this.fiatPercentage,
    this.creationRateMinorPerBtc,
    this.creationRateCurrency,
  });

  static const unavailable = BullnymGetPaidSettlement(
    kind: BullnymSettlementKind.unavailable,
  );

  static const _bitcoin = BullnymGetPaidSettlement(
    kind: BullnymSettlementKind.bitcoin,
  );

  static final RegExp _canonicalUuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  static const String _nilUuid = '00000000-0000-0000-0000-000000000000';

  /// The seven approved settlement currencies, pinned uppercase. Any other
  /// currency string invalidates the leg (and therefore the projection).
  static const Set<String> _supportedCurrencies = {
    'ARS',
    'CAD',
    'COP',
    'CRC',
    'EUR',
    'MXN',
    'USD',
  };

  /// Strict parse of the merchant settlement projection carried on a signed Get
  /// Paid transaction. Returns:
  ///
  /// - `null` when the top-level `settlement_kind` field is ABSENT (an old
  ///   server row with no projection). The caller maps null to its own no-data
  ///   state — this is NEVER interpreted as Bitcoin.
  /// - a settlement with the read [kind] when the payload is internally
  ///   consistent with the contract.
  /// - [unavailable] for any present-but-uninterpretable or inconsistent
  ///   payload (unknown enum, tagged-kind mismatch, invalid/empty legs, an
  ///   override or details attached to the wrong kind, a JSON type error).
  static BullnymGetPaidSettlement? tryParse(Map<String, dynamic> json) {
    // Absent classification is the no-data path (old server). Presence is what
    // distinguishes it from a server-sent `unavailable`.
    if (!json.containsKey('settlement_kind')) return null;

    try {
      final details = json['settlement_details'];
      final override = json['fiat_conversion'];
      switch (json['settlement_kind']) {
        case 'bitcoin':
          return _parseBitcoin(details: details, override: override);
        case 'fiat':
          return _parseFiat(details: details, override: override);
        case 'mixed':
          return _parseMixed(details: details, override: override);
        case 'unavailable':
          // A trustworthy `unavailable` carries neither field; any attached
          // detail is itself inconsistent, so fail closed either way.
          return unavailable;
        default:
          // Unknown or non-string classification → fail closed.
          return unavailable;
      }
    } catch (_) {
      return unavailable;
    }
  }

  static BullnymGetPaidSettlement _parseBitcoin({
    required Object? details,
    required Object? override,
  }) {
    // Ordinary Bitcoin settlement carries no structured details.
    if (details != null) return unavailable;
    if (override == null) return _bitcoin;
    // The only Bitcoin-kind detail is a pre-funding conversion override. An
    // unknown reason is tolerated (it renders as a generic override note); a
    // malformed override envelope fails closed.
    if (override is! Map<String, dynamic> ||
        override['status'] != 'overridden') {
      return unavailable;
    }
    return BullnymGetPaidSettlement(
      kind: BullnymSettlementKind.bitcoin,
      overrideReason: _reason(override['reason']),
    );
  }

  static BullnymGetPaidSettlement _parseFiat({
    required Object? details,
    required Object? override,
  }) {
    // A fiat projection never carries a Bitcoin-only conversion override.
    if (override != null) return unavailable;
    if (details is! Map<String, dynamic>) return unavailable;
    // The tagged detail kind must equal the top-level classification.
    if (details['kind'] != 'fiat') return unavailable;
    // A fiat projection has no bitcoin array.
    if (details.containsKey('bitcoin')) return unavailable;
    final fiat = _fiatLegs(details['fiat']);
    if (fiat == null || fiat.isEmpty) return unavailable;
    // A fiat kind is 100% fiat: a present split must be exactly 100.
    final percentage = _fiatPercentage(details['fiat_percentage'], min: 100);
    if (percentage == _invalidPercentage) return unavailable;
    final creation = _creationRate(details);
    if (creation == null) return unavailable;
    return BullnymGetPaidSettlement(
      kind: BullnymSettlementKind.fiat,
      fiat: fiat,
      fiatPercentage: percentage,
      creationRateMinorPerBtc: creation.rate,
      creationRateCurrency: creation.currency,
    );
  }

  static BullnymGetPaidSettlement _parseMixed({
    required Object? details,
    required Object? override,
  }) {
    if (override != null) return unavailable;
    if (details is! Map<String, dynamic>) return unavailable;
    if (details['kind'] != 'mixed') return unavailable;
    final fiat = _fiatLegs(details['fiat']);
    final bitcoin = _bitcoinLegs(details['bitcoin']);
    // A mixed projection requires non-empty valid legs on BOTH sides.
    if (fiat == null || fiat.isEmpty) return unavailable;
    if (bitcoin == null || bitcoin.isEmpty) return unavailable;
    // A mixed kind splits both ways: a present split must be 1..=99.
    final percentage = _fiatPercentage(
      details['fiat_percentage'],
      min: 1,
      max: 99,
    );
    if (percentage == _invalidPercentage) return unavailable;
    final creation = _creationRate(details);
    if (creation == null) return unavailable;
    return BullnymGetPaidSettlement(
      kind: BullnymSettlementKind.mixed,
      fiat: fiat,
      bitcoin: bitcoin,
      fiatPercentage: percentage,
      creationRateMinorPerBtc: creation.rate,
      creationRateCurrency: creation.currency,
    );
  }

  /// Reads R1 (the invoice-creation reference rate) and its FACE currency off
  /// `settlement_details`. Returns:
  /// - `(rate: null, currency: null)` when both are absent/JSON-null — a legacy
  ///   or sat-priced row that carries no creation rate.
  /// - `(rate, currency)` when each present value is well-formed (rate a
  ///   strictly positive int; currency a supported code). Either may still be
  ///   null independently — a rate with no currency is retained but cannot be
  ///   rendered (the UI omits the row rather than guess a denomination).
  /// - `null` when either field is PRESENT but invalid, signalling the caller to
  ///   fail the whole projection closed to [unavailable] (the established rule).
  static ({int? rate, String? currency})? _creationRate(
    Map<String, dynamic> details,
  ) {
    final rawRate = details['creation_rate_minor_per_btc'];
    final int? rate;
    if (rawRate == null) {
      rate = null;
    } else if (rawRate is int && rawRate > 0) {
      rate = rawRate;
    } else {
      return null;
    }
    final rawCurrency = details['creation_rate_currency'];
    final String? currency;
    if (rawCurrency == null) {
      currency = null;
    } else if (rawCurrency is String &&
        _supportedCurrencies.contains(rawCurrency)) {
      currency = rawCurrency;
    } else {
      return null;
    }
    return (rate: rate, currency: currency);
  }

  static BullnymFiatConversionOverrideReason _reason(Object? v) => switch (v) {
    'below_minimum' => BullnymFiatConversionOverrideReason.belowMinimum,
    'invalid_split' => BullnymFiatConversionOverrideReason.invalidSplit,
    'conversion_unavailable' =>
      BullnymFiatConversionOverrideReason.conversionUnavailable,
    _ => BullnymFiatConversionOverrideReason.unknown,
  };

  /// Validates every fiat leg. Returns null if ANY leg is invalid so the whole
  /// projection fails closed to `unavailable` without partial details.
  static List<BullnymFiatSettlementLeg>? _fiatLegs(Object? raw) {
    if (raw is! List) return null;
    final legs = <BullnymFiatSettlementLeg>[];
    for (final e in raw) {
      if (e is! Map<String, dynamic>) return null;
      final currency = e['currency'];
      if (currency is! String || !_supportedCurrencies.contains(currency)) {
        return null;
      }
      final orderId = e['order_id'];
      if (orderId is! String || !_isCanonicalUuid(orderId)) return null;
      final status = _fiatLegStatus(e['status']);
      if (status == null) return null;
      final amountMinor = e['amount_minor'];
      final int? amount;
      if (status == BullnymSettlementLegStatus.settled) {
        // amount_minor is a strictly positive int only for settled.
        if (amountMinor is! int || amountMinor <= 0) return null;
        amount = amountMinor;
      } else {
        // pending / unavailable: amount_minor must be JSON null (zero is never
        // a pending sentinel).
        if (amountMinor != null) return null;
        amount = null;
      }
      final quotedRaw = e['quoted_amount_minor'];
      final int? quotedAmountMinor;
      if (quotedRaw == null) {
        // Absent or JSON null: a legacy row predating the quote column, or an
        // unavailable leg — no quote to show.
        quotedAmountMinor = null;
      } else if (quotedRaw is int && quotedRaw > 0) {
        // A known quote is a strictly positive int, for pending as well as
        // settled legs.
        quotedAmountMinor = quotedRaw;
      } else {
        // Present but not a strictly positive int → the whole projection fails
        // closed (never a fabricated quote).
        return null;
      }
      final executionRaw = e['execution_rate_minor_per_btc'];
      final int? executionRateMinorPerBtc;
      if (executionRaw == null) {
        // Absent or JSON null: a legacy row, or a leg not yet settled — R2 is
        // only known once the order has executed.
        executionRateMinorPerBtc = null;
      } else if (executionRaw is int && executionRaw > 0) {
        executionRateMinorPerBtc = executionRaw;
      } else {
        // Present but not a strictly positive int → the whole projection fails
        // closed (never a fabricated execution rate).
        return null;
      }
      legs.add(
        BullnymFiatSettlementLeg(
          amountMinor: amount,
          quotedAmountMinor: quotedAmountMinor,
          executionRateMinorPerBtc: executionRateMinorPerBtc,
          currency: currency,
          orderId: orderId,
          status: status,
        ),
      );
    }
    return legs;
  }

  /// Validates every Bitcoin leg. Returns null if ANY leg is invalid.
  static List<BullnymBitcoinSettlementLeg>? _bitcoinLegs(Object? raw) {
    if (raw is! List) return null;
    final legs = <BullnymBitcoinSettlementLeg>[];
    for (final e in raw) {
      if (e is! Map<String, dynamic>) return null;
      final amountSat = e['amount_sat'];
      if (amountSat is! int || amountSat <= 0) return null;
      // Version one settles Bitcoin legs on Liquid only.
      if (e['network'] != 'liquid') return null;
      final status = _bitcoinLegStatus(e['status']);
      if (status == null) return null;
      legs.add(
        BullnymBitcoinSettlementLeg(
          amountSat: amountSat,
          network: 'liquid',
          status: status,
        ),
      );
    }
    return legs;
  }

  /// Sentinel meaning `fiat_percentage` was PRESENT but invalid (non-int or out
  /// of the kind's allowed range) — the caller fails the projection closed.
  static const int _invalidPercentage = -1;

  /// Reads the captured split percentage. Returns null when the field is absent
  /// or JSON null (a legacy row — no split shown), the value when it is an int
  /// in `[min, max]`, or [_invalidPercentage] when it is present but not a valid
  /// int in range.
  static int? _fiatPercentage(Object? raw, {required int min, int max = 100}) {
    if (raw == null) return null;
    if (raw is int && raw >= min && raw <= max) return raw;
    return _invalidPercentage;
  }

  static BullnymSettlementLegStatus? _fiatLegStatus(Object? v) => switch (v) {
    'pending' => BullnymSettlementLegStatus.pending,
    'settled' => BullnymSettlementLegStatus.settled,
    'unavailable' => BullnymSettlementLegStatus.unavailable,
    _ => null,
  };

  static BullnymSettlementLegStatus? _bitcoinLegStatus(Object? v) =>
      switch (v) {
        'pending' => BullnymSettlementLegStatus.pending,
        'settled' => BullnymSettlementLegStatus.settled,
        'problem' => BullnymSettlementLegStatus.problem,
        _ => null,
      };

  static bool _isCanonicalUuid(String value) =>
      value != _nilUuid && _canonicalUuid.hasMatch(value);
}

/// Lifecycle status of the server-held encrypted Bull Bitcoin credential.
enum BullnymCredentialStatus {
  absent,
  active,
  deletionPending,

  /// A status value this client version does not recognize. Fails closed:
  /// treated as not-active for gating so we never assume a credential exists.
  unknown;

  static BullnymCredentialStatus fromWire(String? value) {
    switch (value) {
      case 'absent':
        return BullnymCredentialStatus.absent;
      case 'active':
        return BullnymCredentialStatus.active;
      case 'deletion_pending':
        return BullnymCredentialStatus.deletionPending;
      default:
        return BullnymCredentialStatus.unknown;
    }
  }

  bool get isActive => this == BullnymCredentialStatus.active;
}

/// One product's server-confirmed fiat-settlement setting. A `fiatPercentage`
/// of 0 means Bitcoin-only (the product will not appear in a configuration
/// response as an explicit setting when it is Bitcoin-only).
class BullnymFiatSettlementSetting {
  final BullnymFiatSettlementProduct product;
  final int fiatPercentage;
  final String? fiatCurrency;

  const BullnymFiatSettlementSetting({
    required this.product,
    required this.fiatPercentage,
    required this.fiatCurrency,
  });
}

/// The server-owned fiat-settlement configuration returned by set / get /
/// disable operations. The scoped credential is never present in this payload.
class BullnymFiatSettlementConfiguration {
  final List<BullnymFiatSettlementSetting> settings;
  final BullnymCredentialStatus credentialStatus;

  const BullnymFiatSettlementConfiguration({
    required this.settings,
    required this.credentialStatus,
  });

  BullnymFiatSettlementSetting? settingFor(
    BullnymFiatSettlementProduct product,
  ) {
    for (final setting in settings) {
      if (setting.product == product) return setting;
    }
    return null;
  }
}
