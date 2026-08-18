import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/btcpay/public/btcpay_facade.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_dashboard_snapshot.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_product_probe.dart';

/// Get Paid's narrow wrapper over the BTCPay boundary: read the current paired
/// connection for the hub card. The BTCPay failure family stays behind the
/// boundary — presentation only learns whether the connection is present,
/// confirmed absent, or unknown.
class GetGetPaidBtcpayConnectionUsecase {
  final BtcpayFacade _btcpay;

  const GetGetPaidBtcpayConnectionUsecase({required this._btcpay});

  Future<GetPaidProductProbe<GetPaidBtcpayConnectionSnapshot>> execute() async {
    try {
      return switch (await _btcpay.connection()) {
        Ok(:final value) =>
          value == null
              ? const GetPaidProductAbsent()
              : GetPaidProductFound(
                  GetPaidBtcpayConnectionSnapshot(serverUrl: value.serverUrl),
                ),
        Err(:final failure) => _reportUnavailable(failure),
      };
    } on Exception catch (error, trace) {
      log.warning(
        'Get Paid BTCPay connection lookup failed',
        error: error,
        trace: trace,
      );
      return const GetPaidProductUnavailable();
    }
  }

  GetPaidProductProbe<GetPaidBtcpayConnectionSnapshot> _reportUnavailable(
    Object failure,
  ) {
    log.warning(
      'Get Paid could not load the BTCPay connection',
      error: failure,
    );
    return const GetPaidProductUnavailable();
  }
}
