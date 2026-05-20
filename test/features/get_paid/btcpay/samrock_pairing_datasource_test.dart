import 'dart:convert';

import 'package:bb_mobile/features/get_paid/btcpay/data/samrock_pairing_datasource.dart';
import 'package:bb_mobile/features/get_paid/btcpay/domain/samrock_pairing_request.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockHttpAdapter extends Mock implements HttpClientAdapter {}

class _Captured {
  final List<RequestOptions> requests = [];
}

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: ''));
  });

  test('submits SamRock setup as form encoded json field', () async {
    final stub = _stubDatasource(
      responseBody: {
        'Success': true,
        'Result': {'paired': true},
      },
    );

    final response = await stub.datasource.submitSetup(
      request: _request(),
      payload: {
        'LBTC': {'Descriptor': 'ct(desc)'},
      },
    );

    expect(response.success, isTrue);
    expect(response.result, {'paired': true});
    final request = stub.captured.requests.single;
    expect(request.method, 'POST');
    expect(request.path, _request().protocolUri.toString());
    expect(request.contentType, Headers.formUrlEncodedContentType);
    expect(request.data, {
      'json': jsonEncode({
        'LBTC': {'Descriptor': 'ct(desc)'},
      }),
    });
  });

  test('does not trust success body on non-2xx HTTP status', () async {
    final stub = _stubDatasource(
      statusCode: 500,
      responseBody: {'Success': true, 'Message': 'not really paired'},
    );

    final response = await stub.datasource.submitSetup(
      request: _request(),
      payload: const {},
    );

    expect(response.success, isFalse);
    expect(response.serverFailure, isTrue);
    expect(response.message, 'not really paired');
  });

  test('maps non-json server failures to HTTP status messages', () async {
    final stub = _stubDatasource(
      statusCode: 502,
      rawResponseBody: '<html>bad gateway</html>',
    );

    final response = await stub.datasource.submitSetup(
      request: _request(),
      payload: const {},
    );

    expect(response.success, isFalse);
    expect(response.serverFailure, isTrue);
    expect(response.message, 'BTCPay SamRock server returned HTTP 502');
  });

  test('accepts lowercase response fields', () async {
    final stub = _stubDatasource(
      responseBody: {
        'success': false,
        'message': 'otp expired',
        'result': {'code': 'expired'},
      },
    );

    final response = await stub.datasource.submitSetup(
      request: _request(),
      payload: const {},
    );

    expect(response.success, isFalse);
    expect(response.message, 'otp expired');
    expect(response.result, {'code': 'expired'});
  });
}

({SamRockPairingDatasource datasource, _Captured captured}) _stubDatasource({
  Map<String, Object?>? responseBody,
  String? rawResponseBody,
  int statusCode = 200,
}) {
  final captured = _Captured();
  final adapter = _MockHttpAdapter();
  final dio = Dio(
    BaseOptions(validateStatus: (status) => status != null && status < 600),
  )..httpClientAdapter = adapter;

  when(() => adapter.fetch(any(), any(), any())).thenAnswer((invocation) async {
    final options = invocation.positionalArguments[0] as RequestOptions;
    captured.requests.add(options);
    return ResponseBody.fromString(
      rawResponseBody ?? jsonEncode(responseBody),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  });

  return (datasource: SamRockPairingDatasource(dio: dio), captured: captured);
}

SamRockPairingRequest _request() {
  return const SamRockPairingRequestParser().parse(
    'https://btcpay.example/plugins/store/samrock/protocol?setup=liquid-chain&otp=abc',
  );
}
