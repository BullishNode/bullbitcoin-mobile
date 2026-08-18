import 'package:bb_mobile/core/wallet/data/slip77_blinding_key_deriver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const deriver = Slip77BlindingKeyDeriver();

  test('matches an independently calculated SLIP-77 HMAC vector', () async {
    final secret = await deriver.derive(
      masterKeyExpression:
          'slip77(000102030405060708090a0b0c0d0e0f'
          '101112131415161718191a1b1c1d1e1f)',
      standardAddress: 'ex1qqqgjyv6y24n80zye42aueh0wluqpzg3n8dhp6s',
    );

    expect(
      secret,
      'd33053eb94d002cf2461c0d0ba004dbfc00ec81eb665ec4492381314733fac42',
    );
  });

  test('rejects non-SLIP-77 wallet keys', () async {
    await expectLater(
      deriver.derive(
        masterKeyExpression: 'view-key',
        standardAddress: 'ex1qqqgjyv6y24n80zye42aueh0wluqpzg3n8dhp6s',
      ),
      throwsFormatException,
    );
  });

  test('rejects addresses outside the supported Liquid wallet shape', () async {
    await expectLater(
      deriver.derive(
        masterKeyExpression:
            'slip77(000102030405060708090a0b0c0d0e0f'
            '101112131415161718191a1b1c1d1e1f)',
        standardAddress: 'bc1qqqgjyv6y24n80zye42aueh0wluqpzg3ndy2ehs',
      ),
      throwsFormatException,
    );
  });
}
