import 'package:bb_mobile/features/send/domain/errors/bullpay_proof_error.dart';
import 'package:bb_mobile/features/send/domain/ports/liquid_direct_pay_port.dart';
import 'package:dio/dio.dart';

class DioLiquidDirectPayDatasource implements LiquidDirectPayPort {
  final Dio _dio;

  DioLiquidDirectPayDatasource({Dio? dio})
    : _dio =
          dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));

  @override
  Future<LiquidDirectPayMetadata> fetchMetadata(Uri metadataUrl) async {
    final Map<String, dynamic> data;
    try {
      final response = await _dio.getUri<Map<String, dynamic>>(
        metadataUrl,
        options: Options(followRedirects: false),
      );
      final body = response.data;
      if (body == null || body['tag'] != 'payRequest') {
        throw const LiquidDirectPayUnavailable();
      }
      data = body;
    } on DioException {
      throw const LiquidDirectPayUnavailable();
    }

    final paymentMethodsRaw = data['payment_methods'];
    final callbackRaw = data['callback'];
    if (paymentMethodsRaw is! List || callbackRaw is! String) {
      throw const LiquidDirectPayUnavailable();
    }

    final Uri callback;
    try {
      callback = Uri.parse(callbackRaw);
    } on FormatException {
      throw const LiquidDirectPayUnavailable();
    }

    return LiquidDirectPayMetadata(
      paymentMethods: paymentMethodsRaw.whereType<String>().toList(),
      callback: callback,
    );
  }

  @override
  Future<LiquidDirectPayCallbackResult> requestLiquidPayment(
    Uri callback, {
    required Map<String, String> body,
  }) async {
    final Map<String, dynamic> data;
    try {
      final response = await _dio.postUri<Map<String, dynamic>>(
        callback,
        data: body,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          followRedirects: false,
        ),
      );
      final responseBody = response.data;
      if (responseBody == null) {
        throw const BullpayProofInternal('EmptyResponse');
      }
      data = responseBody;
    } on DioException {
      throw const BullpayProofInternal('NetworkError');
    }

    if (data['status'] == 'ERROR') {
      return LiquidDirectPayCallbackResult(
        status: 'ERROR',
        code: data['code'] as String?,
        reason: data['reason'] as String?,
      );
    }

    final lbtc = data['L-BTC'];
    if (lbtc is! Map<String, dynamic>) {
      return const LiquidDirectPayCallbackResult();
    }

    return LiquidDirectPayCallbackResult(
      liquidAddress: lbtc['address'] as String?,
    );
  }
}
