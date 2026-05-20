import 'package:bb_mobile/features/get_paid/btcpay/domain/samrock_pairing_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = SamRockPairingRequestParser();

  test('parses a valid SamRock pairing URL', () {
    final request = parser.parse(
      'https://170-75-171-81.sslip.io/plugins/a35Bg34RcYHY4mUnSRXhcrfrLrmNiiaaUW2vn2zB9jc/samrock/protocol?setup=btc-chain%2Cliquid-chain%2Cbtc-ln&otp=OBBxOBEzrJhS75msKj2im',
    );

    expect(request.protocolUri.scheme, 'https');
    expect(request.otp, 'OBBxOBEzrJhS75msKj2im');
    expect(request.supportsBitcoinChain, isTrue);
    expect(request.supportsLiquidChain, isTrue);
    expect(request.supportsLightning, isTrue);
  });

  test('accepts a chain-only setup without Lightning', () {
    final request = parser.parse(
      'https://btcpay.example/plugins/plugin-id/samrock/protocol?setup=liquid-chain&otp=abc',
    );

    expect(request.supportsBitcoinChain, isFalse);
    expect(request.supportsLiquidChain, isTrue);
    expect(request.supportsLightning, isFalse);
  });

  test('accepts legacy setup aliases from the protocol specification', () {
    final request = parser.parse(
      'https://btcpay.example/plugins/plugin-id/samrock/protocol?setup=btc,lbtc,btcln&otp=abc',
    );

    expect(request.supportsBitcoinChain, isTrue);
    expect(request.supportsLiquidChain, isTrue);
    expect(request.supportsLightning, isTrue);
  });

  test('rejects omitted setup capabilities', () {
    expect(
      () => parser.parse(
        'https://btcpay.example/plugins/plugin-id/samrock/protocol?otp=abc',
      ),
      throwsA(isA<SamRockPairingRequestException>()),
    );
  });

  test('accepts setup all', () {
    final request = parser.parse(
      'https://btcpay.example/plugins/plugin-id/samrock/protocol?setup=all&otp=abc',
    );

    expect(request.supportsBitcoinChain, isTrue);
    expect(request.supportsLiquidChain, isTrue);
    expect(request.supportsLightning, isTrue);
  });

  test('rejects non-HTTPS URLs', () {
    expect(
      () => parser.parse(
        'http://btcpay.example/plugins/plugin-id/samrock/protocol?setup=liquid-chain&otp=abc',
      ),
      throwsA(isA<SamRockPairingRequestException>()),
    );
  });

  test('rejects URLs without a server host', () {
    expect(
      () => parser.parse(
        'https:/plugins/plugin-id/samrock/protocol?setup=liquid-chain&otp=abc',
      ),
      throwsA(isA<SamRockPairingRequestException>()),
    );
  });

  test('rejects URLs that do not point to the SamRock protocol endpoint', () {
    expect(
      () => parser.parse(
        'https://btcpay.example/plugins/plugin-id/samrock/other?setup=liquid-chain&otp=abc',
      ),
      throwsA(isA<SamRockPairingRequestException>()),
    );
  });

  test('rejects URLs without an OTP', () {
    expect(
      () => parser.parse(
        'https://btcpay.example/plugins/plugin-id/samrock/protocol?setup=liquid-chain',
      ),
      throwsA(isA<SamRockPairingRequestException>()),
    );
  });

  test('accepts Lightning setup because it is backed by Liquid data', () {
    final request = parser.parse(
      'https://btcpay.example/plugins/plugin-id/samrock/protocol?setup=btc-ln&otp=abc',
    );

    expect(request.supportsBitcoinChain, isFalse);
    expect(request.supportsLiquidChain, isFalse);
    expect(request.supportsLightning, isTrue);
  });

  test('rejects explicit setup values without supported payment methods', () {
    expect(
      () => parser.parse(
        'https://btcpay.example/plugins/plugin-id/samrock/protocol?setup=doge&otp=abc',
      ),
      throwsA(isA<SamRockPairingRequestException>()),
    );
  });
}
