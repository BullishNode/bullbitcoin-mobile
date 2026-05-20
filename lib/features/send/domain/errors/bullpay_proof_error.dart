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
        return const BullpayProofRequiresProof();
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
  const BullpayProofRequiresProof();
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
