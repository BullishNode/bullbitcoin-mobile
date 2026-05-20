import 'dart:convert';

import 'package:bb_mobile/features/send/data/datasources/liquid_direct_pay_datasource.dart';
import 'package:bb_mobile/features/send/domain/errors/bullpay_proof_error.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockHttpAdapter extends Mock implements HttpClientAdapter {}

class _Captured {
  final List<RequestOptions> requests = [];
}

({DioLiquidDirectPayDatasource datasource, _Captured captured})
_stubDatasource({
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

  return (
    datasource: DioLiquidDirectPayDatasource(dio: dio),
    captured: captured,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: ''));
  });

  test('parses metadata and disables redirects', () async {
    final stub = _stubDatasource(
      metadataBody: {
        'tag': 'payRequest',
        'payment_methods': ['L-BTC'],
        'callback': 'https://bullpay.ca/cb',
      },
    );

    final metadata = await stub.datasource.fetchMetadata(
      Uri.parse('https://bullpay.ca/.well-known/lnurlp/alice'),
    );

    expect(metadata.paymentMethods, ['L-BTC']);
    expect(metadata.callback.toString(), 'https://bullpay.ca/cb');
    expect(stub.captured.requests.single.followRedirects, isFalse);
  });

  test('malformed metadata maps to unavailable', () async {
    final stub = _stubDatasource(
      metadataBody: {
        'tag': 'payRequest',
        'payment_methods': 'L-BTC',
        'callback': 'https://bullpay.ca/cb',
      },
    );

    await expectLater(
      stub.datasource.fetchMetadata(
        Uri.parse('https://bullpay.ca/.well-known/lnurlp/alice'),
      ),
      throwsA(isA<LiquidDirectPayUnavailable>()),
    );
  });

  test('parses callback error envelope without leaking raw body', () async {
    final stub = _stubDatasource(
      callbackBody: {'status': 'ERROR', 'code': 'UtxoSpent', 'reason': 'spent'},
    );

    final result = await stub.datasource.requestLiquidPayment(
      Uri.parse('https://bullpay.ca/cb'),
      body: const {'amount': '1000'},
    );

    expect(result.status, 'ERROR');
    expect(result.code, 'UtxoSpent');
    expect(result.reason, 'spent');
    expect(stub.captured.requests.single.followRedirects, isFalse);
    expect(stub.captured.requests.single.method, 'POST');
  });

  test(
    'malformed callback response returns no address for usecase mapping',
    () async {
      final stub = _stubDatasource(callbackBody: {'L-BTC': 'not a map'});

      final result = await stub.datasource.requestLiquidPayment(
        Uri.parse('https://bullpay.ca/cb'),
        body: const {'amount': '1000'},
      );

      expect(result.liquidAddress, isNull);
    },
  );
}
