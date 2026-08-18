import 'package:bb_mobile/features/send/domain/errors/bullpay_proof_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BullpayProofError.fromServerCode', () {
    test('maps every stable server code to its variant', () {
      expect(
        BullpayProofError.fromServerCode(code: 'ProofOfFundsRequired'),
        isA<BullpayProofRequiresProof>(),
      );
      expect(
        BullpayProofError.fromServerCode(code: 'ProofOfFundsInvalid'),
        isA<BullpayProofInvalid>(),
      );
      expect(
        BullpayProofError.fromServerCode(code: 'UtxoNotFound'),
        isA<BullpayProofUtxoNotFound>(),
      );
      expect(
        BullpayProofError.fromServerCode(code: 'UtxoSpent'),
        isA<BullpayProofUtxoSpent>(),
      );
      expect(
        BullpayProofError.fromServerCode(code: 'PubkeyUtxoMismatch'),
        isA<BullpayProofPubkeyMismatch>(),
      );
      expect(
        BullpayProofError.fromServerCode(code: 'InvalidAmount'),
        isA<BullpayProofInvalidAmount>(),
      );
      expect(
        BullpayProofError.fromServerCode(code: 'NymNotFound'),
        isA<BullpayProofNymNotFound>(),
      );
    });

    test('unknown code falls back to the internal catch-all', () {
      final error = BullpayProofError.fromServerCode(
        code: 'SomethingBrandNew',
        reason: 'diagnostic only',
      );
      expect(error, isA<BullpayProofInternal>());
      expect((error as BullpayProofInternal).code, 'SomethingBrandNew');
    });

    test('parses min_sat onto RequiresProof', () {
      final error =
          BullpayProofError.fromServerCode(
                code: 'ProofOfFundsRequired',
                minSat: 5000,
              )
              as BullpayProofRequiresProof;
      expect(error.minSat, 5000);
    });

    test('does not map the vanished soft-limit codes to a variant', () {
      // RateLimited / TooManyPendingReservations are gone on the L-BTC path;
      // any such code must land in the generic catch-all, never a bespoke one.
      expect(
        BullpayProofError.fromServerCode(code: 'RateLimited'),
        isA<BullpayProofInternal>(),
      );
      expect(
        BullpayProofError.fromServerCode(code: 'TooManyPendingReservations'),
        isA<BullpayProofInternal>(),
      );
    });
  });
}
