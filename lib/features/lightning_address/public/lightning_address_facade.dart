import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/lightning_address/data/datasources/lightning_address_settings_datasource.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/recover_lightning_address_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/sweep_bullnym_receive_wallet_usecase.dart';

/// Public API for the lightning_address feature.
///
/// All cross-feature access MUST go through this facade.
class LightningAddressFacade {
  static const String walletLabel = bullnymReceiveWalletLabel;

  // Public navigation contract while LA management currently lives in Settings.
  static const String manageRouteName = 'lightningAddress';

  static bool isBullnymReceiveWallet(Wallet wallet) =>
      wallet.label == walletLabel;

  final SweepBullnymReceiveWalletUsecase _sweep;
  final RecoverLightningAddressUsecase _recover;
  final LightningAddressSettingsDatasource _settings;
  final PayServicePort _payService;

  LightningAddressFacade({
    required SweepBullnymReceiveWalletUsecase sweep,
    required RecoverLightningAddressUsecase recover,
    required LightningAddressSettingsDatasource settings,
    required PayServicePort payService,
  }) : _sweep = sweep,
       _recover = recover,
       _settings = settings,
       _payService = payService;

  Future<String?> sweepBullnymReceiveWallet({required bool isTestnet}) =>
      _sweep.execute(isTestnet: isTestnet);

  Future<bool> shouldAutoSweepBullnymReceiveWallet() =>
      _settings.getAutoSweep();

  Future<bool> isBullnymReceiveWalletHidden() => _settings.getHideWallet();

  Future<void> setBullnymReceiveWalletAutoSweep(bool value) =>
      _settings.setAutoSweep(value);

  Future<void> setBullnymReceiveWalletHidden(bool value) =>
      _settings.setHideWallet(value);

  Future<String?> recoverIfNeeded({required Environment environment}) =>
      _recover.execute(environment: environment);

  /// Returns the locally cached Lightning Address, if this device knows one.
  Future<String?> getCurrentLightningAddress() =>
      _payService.getStoredAddress();

  Future<String?> getCurrentNym() async {
    final address = await getCurrentLightningAddress();
    return address?.split('@').firstOrNull;
  }
}
