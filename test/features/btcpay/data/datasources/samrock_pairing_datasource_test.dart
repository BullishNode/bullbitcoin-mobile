import 'package:bb_mobile/features/btcpay/domain/samrock_pairing_request.dart';
import 'package:bb_mobile/features/btcpay/data/datasources/samrock_pairing_datasource.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final request = const SamRockPairingRequestParser().parse(
    'https://btcpay.example.com/plugins/store123/samrock/protocol?otp=123&setup=btc',
  );

  test('requires explicit SamRock success response', () async {
    final datasource = SamRockPairingDatasource(
      dio: _dioReturning(statusCode: 200, body: '{}'),
    );

    final response = await datasource.submitSetup(
      request: request,
      payload: const {},
    );

    expect(response.success, isFalse);
    expect(response.serverFailure, isFalse);
  });

  test('accepts explicit SamRock success response', () async {
    final datasource = SamRockPairingDatasource(
      dio: _dioReturning(statusCode: 200, body: '{"Success":true}'),
    );

    final response = await datasource.submitSetup(
      request: request,
      payload: const {},
    );

    expect(response.success, isTrue);
  });
}

Dio _dioReturning({required int statusCode, required String body}) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response<String>(
            requestOptions: options,
            statusCode: statusCode,
            data: body,
          ),
        );
      },
    ),
  );
  return dio;
}
