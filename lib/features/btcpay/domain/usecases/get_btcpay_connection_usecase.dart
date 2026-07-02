import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_connection_repository.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_connection.dart';

class GetBtcpayConnectionUsecase {
  final GetSettingsUsecase _getSettings;
  final BtcpayConnectionRepository _connectionRepository;

  const GetBtcpayConnectionUsecase({
    required this._getSettings,
    required this._connectionRepository,
  });

  Future<BtcpayConnection?> execute() async {
    final settings = await _getSettings.execute();
    return _connectionRepository.getConnection(settings.environment);
  }
}
