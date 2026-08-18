import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';

/// The single product-availability policy for fiat-settlement surfaces.
///
/// Account and configuration failures belong inside the editor. Only the
/// network environment controls whether the feature is offered at all.
class IsFiatSettlementAvailableUsecase {
  const IsFiatSettlementAvailableUsecase(this._getSettings);

  final GetSettingsUsecase _getSettings;

  Future<bool> execute() async {
    final settings = await _getSettings.execute();
    return settings.environment == Environment.mainnet;
  }
}
