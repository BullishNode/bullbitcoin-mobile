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

    final currencies = metadata['currencies'] as List<dynamic>?;
    if (currencies == null) {
      throw const LiquidDirectPayUnavailable();
    }
    final hasLiquid = currencies.any(
      (c) => c is Map && c['network'] == 'liquid',
    );
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
        '&network=liquid'
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
      final onchain = data['onchain'] as Map<String, dynamic>?;
      if (onchain == null || onchain['network'] != 'liquid') {
        throw const BullpayProofInternal('MalformedResponse');
      }
      return LiquidDirectPayment(
        address: onchain['address'] as String,
        amountSat: (onchain['amount_sat'] as num).toInt(),
        bip21: onchain['bip21'] as String,
      );
    } on BullpayProofError {
      rethrow;
    } catch (e, st) {
      log.severe(error: e, trace: st);
      throw const BullpayProofInternal('MalformedResponse');
    }
  }
}
