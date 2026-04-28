const int kBullpayDefaultMinProofValueSat = 1000;

class LiquidDirectPayUnavailable implements Exception {
  const LiquidDirectPayUnavailable();
}

sealed class BullpayProofError implements Exception {
  const BullpayProofError();

  factory BullpayProofError.fromServerCode({
    required String code,
    String? reason,
  }) {
    switch (code) {
      case 'ProofOfFundsRequired':
        return BullpayProofRequiresProof(
          minSat: _parseMinSatFromReason(reason),
        );
      case 'UtxoNotFound':
        return const BullpayProofUtxoNotFound();
      case 'UtxoSpent':
        return const BullpayProofUtxoSpent();
      case 'RateLimited':
        return const BullpayProofRateLimited();
      case 'TooManyPendingReservations':
        return const BullpayProofTooManyReservations();
      default:
        return BullpayProofInternal(code);
    }
  }
}

final class BullpayProofRequiresProof extends BullpayProofError {
  final int minSat;
  const BullpayProofRequiresProof({this.minSat = kBullpayDefaultMinProofValueSat});
}

final class BullpayProofUtxoNotFound extends BullpayProofError {
  const BullpayProofUtxoNotFound();
}

final class BullpayProofUtxoSpent extends BullpayProofError {
  const BullpayProofUtxoSpent();
}

final class BullpayProofRateLimited extends BullpayProofError {
  const BullpayProofRateLimited();
}

final class BullpayProofTooManyReservations extends BullpayProofError {
  const BullpayProofTooManyReservations();
}

final class BullpayProofInternal extends BullpayProofError {
  final String code;
  const BullpayProofInternal(this.code);
}

int _parseMinSatFromReason(String? reason) {
  if (reason == null) return kBullpayDefaultMinProofValueSat;
  final match = RegExp(r'(\d+)\s*sat').firstMatch(reason);
  if (match == null) return kBullpayDefaultMinProofValueSat;
  return int.tryParse(match.group(1)!) ?? kBullpayDefaultMinProofValueSat;
}
