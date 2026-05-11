import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/ports/payment_page_identity_port.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/ports/payment_page_service_port.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/archive_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/find_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/get_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/save_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/data/datasources/payment_page_datasource.dart';
import 'package:bb_mobile/features/get_paid/payment_page/data/datasources/payment_page_identity_datasource.dart';
import 'package:bb_mobile/features/get_paid/payment_page/presentation/payment_page_cubit.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_dashboard_cubit.dart';
import 'package:bb_mobile/features/get_paid/shared/bullnym/bullnym_client.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:get_it/get_it.dart';

class GetPaidLocator {
  static void setup(GetIt locator) {
    if (!locator.isRegistered<BullnymClient>()) {
      locator.registerLazySingleton<BullnymClient>(() => BullnymClient());
    }

    locator.registerLazySingleton<PaymentPageDatasource>(
      () => PaymentPageDatasource(bullnymClient: locator<BullnymClient>()),
    );
    locator.registerLazySingleton<PaymentPageIdentityDatasource>(
      () => PaymentPageIdentityDatasource(
        walletRepository: locator<WalletRepository>(),
        seedRepository: locator<SeedRepository>(),
      ),
    );
    locator.registerLazySingleton<PaymentPageServicePort>(
      () => locator<PaymentPageDatasource>(),
    );
    locator.registerLazySingleton<PaymentPageIdentityPort>(
      () => locator<PaymentPageIdentityDatasource>(),
    );

    locator.registerFactory<GetPaymentPageUsecase>(
      () => GetPaymentPageUsecase(
        paymentPageService: locator<PaymentPageServicePort>(),
      ),
    );
    locator.registerFactory<FindPaymentPageUsecase>(
      () => FindPaymentPageUsecase(
        paymentPageService: locator<PaymentPageServicePort>(),
      ),
    );
    locator.registerFactory<SavePaymentPageUsecase>(
      () => SavePaymentPageUsecase(
        paymentPageService: locator<PaymentPageServicePort>(),
        paymentPageIdentity: locator<PaymentPageIdentityPort>(),
      ),
    );
    locator.registerFactory<ArchivePaymentPageUsecase>(
      () => ArchivePaymentPageUsecase(
        paymentPageService: locator<PaymentPageServicePort>(),
        paymentPageIdentity: locator<PaymentPageIdentityPort>(),
      ),
    );
    locator.registerFactory<PaymentPageCubit>(
      () => PaymentPageCubit(
        findPaymentPage: locator<FindPaymentPageUsecase>(),
        savePaymentPage: locator<SavePaymentPageUsecase>(),
        archivePaymentPage: locator<ArchivePaymentPageUsecase>(),
      ),
    );
    locator.registerFactory<GetPaidDashboardCubit>(
      () => GetPaidDashboardCubit(
        lightningAddressFacade: locator<LightningAddressFacade>(),
        findPaymentPage: locator<FindPaymentPageUsecase>(),
      ),
    );
  }
}
