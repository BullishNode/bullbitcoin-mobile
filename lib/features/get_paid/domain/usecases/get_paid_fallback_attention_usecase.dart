import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/invoices/public/invoices_facade.dart';

sealed class GetPaidFallbackAttentionResult {
  const GetPaidFallbackAttentionResult();
}

final class GetPaidFallbackAttentionKnown
    extends GetPaidFallbackAttentionResult {
  final int count;

  const GetPaidFallbackAttentionKnown(this.count);
}

final class GetPaidFallbackAttentionUnavailable
    extends GetPaidFallbackAttentionResult {
  const GetPaidFallbackAttentionUnavailable();
}

/// Get Paid's narrow wrapper over the invoices public boundary. Presentation
/// receives only an attention count; authenticated rows and protocol details
/// remain owned by the invoices feature.
class GetPaidFallbackAttentionUsecase {
  final InvoicesFacade _invoices;

  const GetPaidFallbackAttentionUsecase({required this._invoices});

  Future<GetPaidFallbackAttentionResult> execute() async {
    try {
      return switch (await _invoices.fallbackSupervision()) {
        Ok(:final value) => GetPaidFallbackAttentionKnown(value.attentionCount),
        Err(:final failure) => _reportUnavailable(failure),
      };
    } on Exception catch (error, trace) {
      log.warning(
        'Get Paid fallback attention lookup failed',
        error: error,
        trace: trace,
      );
      return const GetPaidFallbackAttentionUnavailable();
    }
  }

  GetPaidFallbackAttentionResult _reportUnavailable(Object failure) {
    log.warning(
      'Get Paid fallback attention lookup was rejected',
      error: failure,
    );
    return const GetPaidFallbackAttentionUnavailable();
  }
}
