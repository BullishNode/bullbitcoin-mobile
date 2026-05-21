import 'package:bb_mobile/features/get_paid/btcpay/domain/btcpay_connection.dart';

abstract class BtcpayConnectionStore {
  Future<BtcpayConnection?> getConnection();
  Future<void> saveConnection(BtcpayConnection connection);
}
