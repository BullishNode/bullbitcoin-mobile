import 'package:bb_mobile/core/storage/data/datasources/key_value_storage/key_value_storage_datasource.dart';
import 'package:bb_mobile/features/btcpay/data/models/btcpay_connection_model.dart';

class BtcpayConnectionDatasource {
  static const _connectionKeyPrefix = 'btcpay_connection';

  final KeyValueStorageDatasource<String> _storage;

  const BtcpayConnectionDatasource({required this._storage});

  Future<BtcpayConnectionModel?> get(String environmentName) async {
    final value = await _storage.getValue(_connectionKey(environmentName));
    if (value == null || value.trim().isEmpty) return null;
    return BtcpayConnectionModel.tryDecode(value);
  }

  Future<void> save(BtcpayConnectionModel model) {
    return _storage.saveValue(
      key: _connectionKey(model.environment),
      value: model.encode(),
    );
  }

  String _connectionKey(String environmentName) {
    return '${_connectionKeyPrefix}_$environmentName';
  }
}
