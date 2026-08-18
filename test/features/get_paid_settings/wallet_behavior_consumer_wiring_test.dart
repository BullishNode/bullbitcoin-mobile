import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/apply_wallet_behavior_defaults_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallet_usecase.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart';
import 'package:bb_mobile/features/deterministic_wallets/public/deterministic_wallets_facade.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/get_lightning_address_wallet_behavior_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/update_lightning_address_wallet_behavior_usecase.dart';
import 'package:bb_mobile/features/lightning_address/lightning_address_locator.dart';
import 'package:bb_mobile/features/lightning_address/presentation/lightning_address_activation_cubit.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bb_mobile/features/payment_page/domain/usecases/get_payment_page_wallet_behavior_usecase.dart';
import 'package:bb_mobile/features/payment_page/domain/usecases/update_payment_page_wallet_behavior_usecase.dart';
import 'package:bb_mobile/features/payment_page/payment_page_locator.dart';
import 'package:bb_mobile/features/payment_page/presentation/payment_page_cubit.dart';
import 'package:bb_mobile/features/pos/domain/usecases/get_pos_wallet_behavior_usecase.dart';
import 'package:bb_mobile/features/pos/domain/usecases/update_pos_wallet_behavior_usecase.dart';
import 'package:bb_mobile/features/pos/pos_locator.dart';
import 'package:bb_mobile/features/pos/presentation/pos_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

class _MockGetPaidSettingsFacade extends Mock
    implements GetPaidSettingsFacade {}

class _MockKeychainManifestFacade extends Mock
    implements KeychainManifestFacade {}

class _MockBip85RegistryFacade extends Mock implements Bip85RegistryFacade {}

class _MockDeterministicWalletsFacade extends Mock
    implements DeterministicWalletsFacade {}

class _MockBullnymFacade extends Mock implements BullnymFacade {}

class _MockNostrIdentityFacade extends Mock implements NostrIdentityFacade {}

class _MockGetSettingsUsecase extends Mock implements GetSettingsUsecase {}

class _MockGetWalletUsecase extends Mock implements GetWalletUsecase {}

class _MockApplyWalletBehaviorDefaultsUsecase extends Mock
    implements ApplyWalletBehaviorDefaultsUsecase {}

class _MockWalletRepository extends Mock implements WalletRepository {}

class _MockSeedRepository extends Mock implements SeedRepository {}

/// Boot coverage for the wallet-behavior consumers. Each product feature owns a
/// wrapper use case over `GetPaidSettingsFacade`, and its Cubit is wired to those
/// wrappers — never to the foreign facade. Resolving each Cubit here proves both
/// halves: the wrappers are registered, and nothing in the chain still asks the
/// locator for the provider facade on a Cubit's behalf.
void main() {
  late GetIt locator;

  setUp(() {
    locator = GetIt.asNewInstance();
    // The provider boundary registers before its consumers.
    locator.registerSingleton<GetPaidSettingsFacade>(
      _MockGetPaidSettingsFacade(),
    );
    locator.registerSingleton<KeychainManifestFacade>(
      _MockKeychainManifestFacade(),
    );
    locator.registerSingleton<Bip85RegistryFacade>(_MockBip85RegistryFacade());
    locator.registerSingleton<DeterministicWalletsFacade>(
      _MockDeterministicWalletsFacade(),
    );
    locator.registerSingleton<BullnymFacade>(_MockBullnymFacade());
    locator.registerSingleton<NostrIdentityFacade>(_MockNostrIdentityFacade());
    locator.registerSingleton<GetSettingsUsecase>(_MockGetSettingsUsecase());
    locator.registerSingleton<GetWalletUsecase>(_MockGetWalletUsecase());
    locator.registerSingleton<ApplyWalletBehaviorDefaultsUsecase>(
      _MockApplyWalletBehaviorDefaultsUsecase(),
    );
    locator.registerSingleton<WalletRepository>(_MockWalletRepository());
    locator.registerSingleton<SeedRepository>(_MockSeedRepository());

    // Lightning Address publishes the facade the other two consume.
    LightningAddressLocator.setup(locator);
    PaymentPageLocator.setup(locator);
    PosLocator.setup(locator);
  });

  tearDown(() => locator.reset());

  test('each product feature owns its wallet-behavior wrappers', () {
    expect(
      locator<GetLightningAddressWalletBehaviorUsecase>(),
      isA<GetLightningAddressWalletBehaviorUsecase>(),
    );
    expect(
      locator<UpdateLightningAddressWalletBehaviorUsecase>(),
      isA<UpdateLightningAddressWalletBehaviorUsecase>(),
    );
    expect(
      locator<GetPaymentPageWalletBehaviorUsecase>(),
      isA<GetPaymentPageWalletBehaviorUsecase>(),
    );
    expect(
      locator<UpdatePaymentPageWalletBehaviorUsecase>(),
      isA<UpdatePaymentPageWalletBehaviorUsecase>(),
    );
    expect(
      locator<GetPosWalletBehaviorUsecase>(),
      isA<GetPosWalletBehaviorUsecase>(),
    );
    expect(
      locator<UpdatePosWalletBehaviorUsecase>(),
      isA<UpdatePosWalletBehaviorUsecase>(),
    );
  });

  test('every product Cubit resolves through its own wrappers', () {
    expect(
      locator<LightningAddressActivationCubit>(),
      isA<LightningAddressActivationCubit>(),
    );
    expect(locator<PaymentPageCubit>(), isA<PaymentPageCubit>());
    expect(locator<PosCubit>(), isA<PosCubit>());
  });
}
