import 'package:bb_mobile/core/wallet/domain/wallet_label_reservations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = WalletLabelReservationPolicy(
    reservedLabels: ['System Wallet', 'External Receive'],
  );

  test('matches configured reserved labels case-insensitively', () {
    expect(policy.isReserved('System Wallet'), isTrue);
    expect(policy.isReserved(' external receive '), isTrue);
    expect(policy.isReserved('Savings'), isFalse);
  });

  test('throws for configured reserved user wallet labels', () {
    expect(
      () => policy.throwIfReserved('system wallet'),
      throwsA(isA<ReservedWalletLabelException>()),
    );
    expect(() => policy.throwIfReserved('Cold Storage'), returnsNormally);
    expect(() => policy.throwIfReserved(null), returnsNormally);
  });
}
