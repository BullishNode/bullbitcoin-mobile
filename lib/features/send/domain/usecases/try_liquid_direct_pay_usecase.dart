import 'package:bb_mobile/core/utils/constants.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/send/domain/errors/bullpay_proof_error.dart';
import 'package:bb_mobile/features/send/domain/usecases/build_bullpay_proof_usecase.dart';
import 'package:dio/dio.dart';

class LiquidDirectPayment {
  final String address;
  final int amountSat;
  final String bip21;

  LiquidDirectPayment({
    required this.address,
    required this.amountSat,
    required this.bip21,
  });
}

class TryLiquidDirectPayUsecase {
  final BuildBullpayProofUsecase _buildProof;
  final Dio _dio;

  TryLiquidDirectPayUsecase({
    required BuildBullpayProofUsecase buildProof,
    Dio? dio,
  })  : _buildProof = buildProof,
        _dio = dio ??
            Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));

  Future<LiquidDirectPayment> execute({
    required String lnAddress,
    required int amountSat,
    required String walletId,
  }) async {
    final parts = lnAddress.split('@');
    if (parts.length != 2) {
      throw const LiquidDirectPayUnavailable();
    }

    final username = parts[0].toLowerCase();
    final domain = parts[1].toLowerCase();

    final Map<String, dynamic> metadata;
    try {
      final metadataResp = await _dio.get<Map<String, dynamic>>(
        'https://$domain/.well-known/lnurlp/$username',
      );
      final data = metadataResp.data;
      if (data == null || data['tag'] != 'payRequest') {
        throw const LiquidDirectPayUnavailable();
      }
      metadata = data;
    } on DioException {
      throw const LiquidDirectPayUnavailable();
    }

    final paymentMethods = metadata['payment_methods'] as List<dynamic>?;
    final hasLiquid = paymentMethods?.contains('L-BTC') ?? false;
    if (!hasLiquid) {
      throw const LiquidDirectPayUnavailable();
    }

    final callback = metadata['callback'] as String?;
    if (callback == null) {
      throw const LiquidDirectPayUnavailable();
    }

    final proof = await _buildProof.execute(
      walletId: walletId,
      nym: username,
    );

    final separator = callback.contains('?') ? '&' : '?';
    final msats = amountSat * 1000;
    final callbackUrl = '$callback'
        '${separator}amount=$msats'
        '&payment_method=L-BTC'
        '&outpoint=${proof.outpoint}'
        '&pubkey=${proof.pubkeyHex}'
        '&sig=${proof.sigDerHex}';

    final Map<String, dynamic> data;
    try {
      final callbackResp = await _dio.get<Map<String, dynamic>>(callbackUrl);
      final body = callbackResp.data;
      if (body == null) {
        throw const BullpayProofInternal('EmptyResponse');
      }
      data = body;
    } on DioException {
      throw const BullpayProofInternal('NetworkError');
    }

    if (data['status'] == 'ERROR') {
      final code = data['code'] as String?;
      final reason = data['reason'] as String?;
      if (code != null) {
        throw BullpayProofError.fromServerCode(code: code, reason: reason);
      }
      throw const BullpayProofInternal('UnknownServerError');
    }

    try {
      final lbtc = data['L-BTC'] as Map<String, dynamic>?;
      if (lbtc == null) {
        throw const BullpayProofInternal('MalformedResponse');
      }
      final address = lbtc['address'] as String;
      final btcDecimal = (amountSat / 100000000).toStringAsFixed(8);
      final bip21 =
          'liquidnetwork:$address?amount=$btcDecimal&assetid=${AssetConstants.lbtcMainnet}';
      return LiquidDirectPayment(
        address: address,
        amountSat: amountSat,
        bip21: bip21,
      );
    } on BullpayProofError {
      rethrow;
    } catch (e, st) {
      log.severe(error: e, trace: st);
      throw const BullpayProofInternal('MalformedResponse');
    }
  }
}
