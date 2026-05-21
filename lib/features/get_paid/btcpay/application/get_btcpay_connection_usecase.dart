import 'package:bb_mobile/features/get_paid/btcpay/application/ports/btcpay_connection_store.dart';
import 'package:bb_mobile/features/get_paid/btcpay/domain/btcpay_connection.dart';

class GetBtcpayConnectionUsecase {
  final BtcpayConnectionStore _store;

  const GetBtcpayConnectionUsecase({required BtcpayConnectionStore store})
    : _store = store;

  Future<BtcpayConnection?> execute() => _store.getConnection();
}
