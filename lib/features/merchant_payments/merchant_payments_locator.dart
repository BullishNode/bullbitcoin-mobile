import 'package:bb_mobile/features/merchant_payments/application/merchant_key_derivation_service.dart';
import 'package:bb_mobile/features/merchant_payments/application/ports/key_derivation_port.dart';
import 'package:get_it/get_it.dart';

class MerchantPaymentsLocator {
  static void setup(GetIt locator) {
    registerServices(locator);
    // TODO: Register blocs, use cases, and repositories
    // registerBlocs(locator);
    // registerUsecases(locator);
    // registerRepositories(locator);
  }

  static void registerServices(GetIt locator) {
    // Register merchant key derivation service
    locator.registerLazySingleton<KeyDerivationPort>(
      () => MerchantKeyDerivationService(),
    );
  }

  // static void registerBlocs(GetIt locator) {
  //   // TODO: Register BLoCs/Cubits for merchant payments
  // }

  // static void registerUsecases(GetIt locator) {
  //   // TODO: Register use cases for merchant payments
  // }

  // static void registerRepositories(GetIt locator) {
  //   // TODO: Register repositories and data sources for merchant payments
  // }
}
