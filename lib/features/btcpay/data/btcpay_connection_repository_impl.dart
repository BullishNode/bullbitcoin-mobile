import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/features/btcpay/data/datasources/btcpay_connection_datasource.dart';
import 'package:bb_mobile/features/btcpay/data/models/btcpay_connection_model.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_connection.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_connection_repository.dart';

class BtcpayConnectionRepositoryImpl implements BtcpayConnectionRepository {
  final BtcpayConnectionDatasource _datasource;

  const BtcpayConnectionRepositoryImpl({required this._datasource});

  @override
  Future<BtcpayConnection?> getConnection(Environment environment) async {
    final model = await _datasource.get(environment.name);
    final connection = model?.toEntity();
    // A record stored under this environment's key must also claim that
    // environment; anything else is treated as absent rather than surfaced.
    if (connection == null || connection.environment != environment) {
      return null;
    }
    return connection;
  }

  @override
  Future<void> saveConnection(BtcpayConnection connection) {
    return _datasource.save(BtcpayConnectionModel.fromEntity(connection));
  }
}
