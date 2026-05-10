import 'dart:convert';

import 'package:bb_mobile/features/send/domain/errors/bullpay_proof_error.dart';
import 'package:bb_mobile/features/send/domain/usecases/build_bullpay_proof_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/try_liquid_direct_pay_usecase.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBuildProof extends Mock implements BuildBullpayProofUsecase {}

class _MockHttpAdapter extends Mock implements HttpClientAdapter {}

final _proof = BullpayProofParams(
  outpoint: '${'aa' * 32}:0',
  pubkeyHex: 'bb' * 32,
  sigDerHex: 'cc' * 64,
);

class _Captured {
  final List<RequestOptions> requests = [];
}

({Dio dio, _Captured captured}) _stubDio({
  Map<String, dynamic>? metadataBody,
  Map<String, dynamic>? callbackBody,
  int metadataStatus = 200,
  int callbackStatus = 200,
}) {
  final captured = _Captured();
  final adapter = _MockHttpAdapter();
  final dio = Dio()..httpClientAdapter = adapter;

  when(() => adapter.fetch(any(), any(), any())).thenAnswer((inv) async {
    final opts = inv.positionalArguments[0] as RequestOptions;
    captured.requests.add(opts);
    final isMetadata = opts.path.contains('/.well-known/lnurlp/');
    final body = isMetadata ? metadataBody : callbackBody;
    final status = isMetadata ? metadataStatus : callbackStatus;
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      status,
      headers: {
        'content-type': ['application/json'],
      },
    );
  });
  return (dio: dio, captured: captured);
}

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: ''));
  });

  TryLiquidDirectPayUsecase build(Dio dio) {
    final mockProof = _MockBuildProof();
    when(
      () => mockProof.execute(
        walletId: any(named: 'walletId'),
        nym: any(named: 'nym'),
      ),
    ).thenAnswer((_) async => _proof);
    return TryLiquidDirectPayUsecase(buildProof: mockProof, dio: dio);
  }

  group('username/domain validation (C-3)', () {
    final cases = <String>[
      'alice@evil.com/x',
      '../etc/passwd@bullpay.ca',
      'alice@bullpay.ca:8080',
      'alice@127.0.0.1',
      'alice@localhost',
      'alice@',
      '@bullpay.ca',
      'alice with space@bullpay.ca',
      'alice@bullpay',
    ];

    for (final input in cases) {
      test('rejects "$input"', () async {
        final stub = _stubDio();
        final usecase = build(stub.dio);
        await expectLater(
          usecase.execute(lnAddress: input, amountSat: 1000, walletId: 'w'),
          throwsA(isA<LiquidDirectPayUnavailable>()),
        );
        expect(stub.captured.requests, isEmpty);
      });
    }

    test('accepts well-formed lowercase nym + hostname', () async {
      final stub = _stubDio(
        metadataBody: {
          'tag': 'payRequest',
          'payment_methods': ['L-BTC'],
          'callback': 'https://bullpay.ca/lnurlp/callback?id=abc',
        },
        callbackBody: {
          'L-BTC': {'address': 'lq1qfake'},
        },
      );
      final out = await build(
        stub.dio,
      ).execute(lnAddress: 'alice@bullpay.ca', amountSat: 1000, walletId: 'w');
      expect(out.address, 'lq1qfake');
      expect(
        stub.captured.requests.first.uri.toString(),
        'https://bullpay.ca/.well-known/lnurlp/alice',
      );
    });
  });

  group('callback URL pinning (C-4)', () {
    final invalidCallbacks = <String>[
      'http://bullpay.ca/cb',
      'https://attacker.example/cb',
      'https://bullpay.ca.attacker.example/cb',
      'javascript:alert(1)',
      '//bullpay.ca/cb',
      '',
    ];

    for (final cb in invalidCallbacks) {
      test('rejects callback "$cb"', () async {
        final stub = _stubDio(
          metadataBody: {
            'tag': 'payRequest',
            'payment_methods': ['L-BTC'],
            'callback': cb,
          },
        );
        await expectLater(
          build(stub.dio).execute(
            lnAddress: 'alice@bullpay.ca',
            amountSat: 1000,
            walletId: 'w',
          ),
          throwsA(isA<LiquidDirectPayUnavailable>()),
        );
      });
    }

    test('disables redirects on metadata + callback requests', () async {
      final stub = _stubDio(
        metadataBody: {
          'tag': 'payRequest',
          'payment_methods': ['L-BTC'],
          'callback': 'https://bullpay.ca/cb',
        },
        callbackBody: {
          'L-BTC': {'address': 'lq1qfake'},
        },
      );
      await build(
        stub.dio,
      ).execute(lnAddress: 'alice@bullpay.ca', amountSat: 1000, walletId: 'w');
      expect(stub.captured.requests, hasLength(2));
      for (final r in stub.captured.requests) {
        expect(r.followRedirects, isFalse);
      }
    });
  });

  group('happy path', () {
    test('payment_methods without L-BTC throws Unavailable', () async {
      final stub = _stubDio(
        metadataBody: {
          'tag': 'payRequest',
          'payment_methods': ['BTC'],
          'callback': 'https://bullpay.ca/cb',
        },
      );
      await expectLater(
        build(stub.dio).execute(
          lnAddress: 'alice@bullpay.ca',
          amountSat: 1000,
          walletId: 'w',
        ),
        throwsA(isA<LiquidDirectPayUnavailable>()),
      );
    });

    test('non-payRequest tag throws Unavailable', () async {
      final stub = _stubDio(metadataBody: {'tag': 'channelRequest'});
      await expectLater(
        build(stub.dio).execute(
          lnAddress: 'alice@bullpay.ca',
          amountSat: 1000,
          walletId: 'w',
        ),
        throwsA(isA<LiquidDirectPayUnavailable>()),
      );
    });

    test('attaches proof params + msats to callback query', () async {
      final stub = _stubDio(
        metadataBody: {
          'tag': 'payRequest',
          'payment_methods': ['L-BTC'],
          'callback': 'https://bullpay.ca/cb?existing=1',
        },
        callbackBody: {
          'L-BTC': {'address': 'lq1qfake'},
        },
      );
      await build(
        stub.dio,
      ).execute(lnAddress: 'alice@bullpay.ca', amountSat: 5000, walletId: 'w');
      final cb = stub.captured.requests[1];
      expect(cb.uri.queryParameters, {
        'existing': '1',
        'amount': '5000000',
        'payment_method': 'L-BTC',
        'outpoint': _proof.outpoint,
        'pubkey': _proof.pubkeyHex,
        'sig': _proof.sigDerHex,
      });
    });

    test('server ERROR with code maps to BullpayProofError', () async {
      final stub = _stubDio(
        metadataBody: {
          'tag': 'payRequest',
          'payment_methods': ['L-BTC'],
          'callback': 'https://bullpay.ca/cb',
        },
        callbackBody: {
          'status': 'ERROR',
          'code': 'utxo_spent',
          'reason': 'spent',
        },
      );
      await expectLater(
        build(stub.dio).execute(
          lnAddress: 'alice@bullpay.ca',
          amountSat: 1000,
          walletId: 'w',
        ),
        throwsA(isA<BullpayProofError>()),
      );
    });
  });
}
