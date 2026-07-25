/// The single client-side derivation of a bitcoin leg's estimated fiat worth at
/// the invoice-creation reference rate (R1). Both the payment-details ≈ sub-line
/// and the accounting CSV export read from here so the estimate is computed one
/// way only.
///
/// value (face-currency minor units) = `sats × rateMinorPerBtc / 100_000_000`,
/// using pure integer arithmetic with banker's rounding (round half to even) —
/// never floating point. The result is an ESTIMATE at a reference moment and
/// must only ever be presented as approximate (≈) or in an `_est`-named column.
///
/// Both inputs must be strictly positive (a leg carries positive sats; R1 is a
/// strictly positive int when present).
int getPaidBitcoinLegValueMinorAtCreationRate(
  int sats,
  int creationRateMinorPerBtc,
) {
  const satsPerBtc = 100000000;
  final numerator = sats * creationRateMinorPerBtc;
  final quotient = numerator ~/ satsPerBtc;
  final remainder = numerator % satsPerBtc;
  final twiceRemainder = remainder * 2;
  if (twiceRemainder < satsPerBtc) return quotient;
  if (twiceRemainder > satsPerBtc) return quotient + 1;
  // Exactly halfway: round to the even neighbour.
  return quotient.isEven ? quotient : quotient + 1;
}
