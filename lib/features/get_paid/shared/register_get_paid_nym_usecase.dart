import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_errors.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/register_lightning_address_usecase.dart';

class RegisterGetPaidNymException implements Exception {
  final String message;

  const RegisterGetPaidNymException(this.message);
}

class RegisterGetPaidNymUsecase {
  final RegisterLightningAddressUsecase _register;
  final GetSettingsUsecase _getSettings;

  RegisterGetPaidNymUsecase({
    required RegisterLightningAddressUsecase register,
    required GetSettingsUsecase getSettings,
  }) : _register = register,
       _getSettings = getSettings;

  Future<String> execute(String nym) async {
    try {
      final settings = await _getSettings.execute();
      final result = await _register.execute(
        nym: nym,
        environment: settings.environment,
      );
      return result.address.split('@').first;
    } on LightningAddressRegistrationException catch (e) {
      throw RegisterGetPaidNymException(e.message);
    }
  }
}
