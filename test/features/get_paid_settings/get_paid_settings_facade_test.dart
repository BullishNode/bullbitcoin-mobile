import 'package:bb_mobile/core/wallet/domain/usecases/get_wallets_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/update_wallet_behavior_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/get_paid_settings_locator.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

void main() {
  test('locator publishes the wallet-behavior facade contract', () async {
    final locator = GetIt.asNewInstance();
    addTearDown(locator.reset);
    locator.registerSingleton<KeychainManifestFacade>(
      _MockKeychainManifestFacade(),
    );
    locator.registerSingleton<GetWalletsUsecase>(_MockGetWallets());
    locator.registerSingleton<UpdateWalletBehaviorUsecase>(
      _MockUpdateWalletBehavior(),
    );

    GetPaidSettingsLocator.setup(locator);

    expect(locator<GetPaidSettingsFacade>(), isA<GetPaidSettingsFacade>());
  });
}

final class _MockKeychainManifestFacade extends Mock
    implements KeychainManifestFacade {}

final class _MockUpdateWalletBehavior extends Mock
    implements UpdateWalletBehaviorUsecase {}

final class _MockGetWallets extends Mock implements GetWalletsUsecase {}
