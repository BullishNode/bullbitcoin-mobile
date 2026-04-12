import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Result of a successful LUD-22 Liquid-direct resolution.
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

/// Attempts to resolve a Lightning Address as a Liquid-direct payment (LUD-22).
///
/// If the LNURL server advertises Liquid support in its `currencies` array,
/// calls the callback with `&network=liquid` and returns a direct Liquid
/// address. Returns null if Liquid is not supported — caller should fall
/// back to the standard Lightning swap flow.
class TryLiquidDirectPayUsecase {
  final Dio _dio;

  TryLiquidDirectPayUsecase({Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));

  Future<LiquidDirectPayment?> execute({
    required String lnAddress,
    required int amountSat,
  }) async {
    try {
      final parts = lnAddress.split('@');
      if (parts.length != 2) return null;

      final username = parts[0].toLowerCase();
      final domain = parts[1].toLowerCase();

      // Fetch LNURL metadata
      final metadataResp = await _dio.get<Map<String, dynamic>>(
        'https://$domain/.well-known/lnurlp/$username',
      );
      final metadata = metadataResp.data;
      if (metadata == null || metadata['tag'] != 'payRequest') return null;

      // Check for LUD-22 currencies
      final currencies = metadata['currencies'] as List<dynamic>?;
      if (currencies == null) return null;

      final hasLiquid = currencies.any(
        (c) => c is Map && c['network'] == 'liquid',
      );
      if (!hasLiquid) return null;

      // Call callback with network=liquid
      final callback = metadata['callback'] as String?;
      if (callback == null) return null;

      final separator = callback.contains('?') ? '&' : '?';
      final msats = amountSat * 1000;
      final callbackUrl = '$callback${separator}amount=$msats&network=liquid';

      final callbackResp = await _dio.get<Map<String, dynamic>>(callbackUrl);
      final data = callbackResp.data;
      if (data == null) return null;

      if (data['status'] == 'ERROR') {
        debugPrint('LUD-22 callback error: ${data['reason']}');
        return null;
      }

      // Parse onchain response
      final onchain = data['onchain'] as Map<String, dynamic>?;
      if (onchain == null || onchain['network'] != 'liquid') return null;

      return LiquidDirectPayment(
        address: onchain['address'] as String,
        amountSat: (onchain['amount_sat'] as num).toInt(),
        bip21: onchain['bip21'] as String,
      );
    } catch (e) {
      debugPrint('LUD-22 resolution failed: $e');
      return null;
    }
  }
}
