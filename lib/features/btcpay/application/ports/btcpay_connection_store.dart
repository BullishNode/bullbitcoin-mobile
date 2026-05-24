import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_connection.dart';

abstract class BtcpayConnectionStore {
  Future<BtcpayConnection?> getConnection(Environment environment);
  Future<void> saveConnection(BtcpayConnection connection);
}
