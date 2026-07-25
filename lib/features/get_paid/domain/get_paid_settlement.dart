// Get Paid-owned settlement presentation projection.
//
// Get Paid does not consume the Bullnym transport/domain settlement types in
// its widgets. The list use-case maps the validated Bullnym projection into
// these Get Paid types at the feature boundary, and history/detail screens
// render only from here.

/// Coarse settlement classification for a received Get Paid payment. There is
/// deliberately no "bitcoin-by-default": a payment with no server-provided
/// classification is represented by a null projection, never by this enum.
enum GetPaidSettlementKind { bitcoin, fiat, mixed, unavailable }

/// Per-leg lifecycle in the Get Paid presentation. Fiat legs use
/// pending/settled/unavailable; Bitcoin legs use pending/settled/problem.
enum GetPaidSettlementLegStatus { pending, settled, problem, unavailable }

/// Why a configured fiat conversion was overridden to all-Bitcoin. `unknown`
/// covers a reason this client version does not recognize (rendered with the
/// generic override copy).
enum GetPaidFiatOverrideReason {
  belowMinimum,
  invalidSplit,
  conversionUnavailable,
  unknown,
}

/// One private fiat settlement leg. [amountMinor] is the credited amount,
/// present only once settled. [quotedAmountMinor] is the fiat amount locked at
/// order creation, present (positive) whenever a quote is known — for pending
/// legs too — and null for a legacy row or an unavailable leg.
/// [executionRateMinorPerBtc] is R2 — Bull Bitcoin's real execution rate for
/// this leg, denominated in the leg's own [currency]; present (positive) once
/// the leg has settled, null otherwise.
class GetPaidFiatSettlementLeg {
  final int? amountMinor;
  final int? quotedAmountMinor;
  final int? executionRateMinorPerBtc;
  final String currency;
  final String orderId;
  final GetPaidSettlementLegStatus status;

  const GetPaidFiatSettlementLeg({
    required this.amountMinor,
    required this.currency,
    required this.orderId,
    required this.status,
    this.quotedAmountMinor,
    this.executionRateMinorPerBtc,
  });
}

/// The Bitcoin-wallet portion of a mixed settlement.
class GetPaidBitcoinSettlementLeg {
  final int amountSat;
  final GetPaidSettlementLegStatus status;

  const GetPaidBitcoinSettlementLeg({
    required this.amountSat,
    required this.status,
  });
}

/// The Get Paid settlement projection shown on the history and detail screens.
class GetPaidSettlement {
  final GetPaidSettlementKind kind;
  final List<GetPaidFiatSettlementLeg> fiat;
  final List<GetPaidBitcoinSettlementLeg> bitcoin;
  final GetPaidFiatOverrideReason? overrideReason;

  /// The captured split percentage that applied at payment time (`100` for a
  /// fiat kind, `1..=99` for mixed). Null for a legacy row predating the
  /// captured column, in which case no Split row is shown.
  final int? fiatPercentage;

  /// R1 — the invoice-creation reference rate (minor units per BTC), in the
  /// invoice FACE currency ([creationRateCurrency]). Present only for a
  /// fiat-priced invoice on a server that sends it; null otherwise. The
  /// "Rate at creation" row and the derived ≈ value both read from this.
  final int? creationRateMinorPerBtc;

  /// The FACE currency of [creationRateMinorPerBtc] (which may differ from any
  /// fiat leg's currency). Null when the rate is absent or the server names no
  /// currency for it — the rate is then not rendered.
  final String? creationRateCurrency;

  const GetPaidSettlement({
    required this.kind,
    this.fiat = const [],
    this.bitcoin = const [],
    this.overrideReason,
    this.fiatPercentage,
    this.creationRateMinorPerBtc,
    this.creationRateCurrency,
  });
}
