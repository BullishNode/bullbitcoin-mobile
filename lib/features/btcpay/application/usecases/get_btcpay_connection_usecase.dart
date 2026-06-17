import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/features/btcpay/application/ports/btcpay_connection_store.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_connection.dart';

class GetBtcpayConnectionUsecase {
  final GetSettingsUsecase _getSettings;
  final BtcpayConnectionStore _store;

  const GetBtcpayConnectionUsecase({
    required this._getSettings,
    required this._store,
  });

  Future<BtcpayConnection?> execute() async {
    final settings = await _getSettings.execute();
    return _store.getConnection(settings.environment);
  }
}
