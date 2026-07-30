/// Outcome of one Get Paid hub product read.
///
/// The three cases are deliberately distinct: a CONFIRMED empty read is
/// [GetPaidProductAbsent], while a failed or timed-out read is
/// [GetPaidProductUnavailable]. The hub must never render "not configured" for a
/// truth it does not know, so no product read may collapse the two.
sealed class GetPaidProductProbe<T> {
  const GetPaidProductProbe();
}

/// The product exists on the server; [row] is its current state.
final class GetPaidProductFound<T> extends GetPaidProductProbe<T> {
  final T row;

  const GetPaidProductFound(this.row);
}

/// A confirmed read found no product configured yet.
final class GetPaidProductAbsent<T> extends GetPaidProductProbe<T> {
  const GetPaidProductAbsent();
}

/// The read failed; the product's truth is unknown.
final class GetPaidProductUnavailable<T> extends GetPaidProductProbe<T> {
  const GetPaidProductUnavailable();
}
