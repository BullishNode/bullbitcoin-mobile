import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_address_repository.dart';
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
import 'package:bb_mobile/features/get_paid/invoices/application/ports/invoices_identity_port.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/ports/invoices_pay_service_port.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/cancel_invoice_usecase.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/create_invoice_usecase.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/get_invoice_usecase.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/list_invoices_usecase.dart';
import 'package:bb_mobile/features/get_paid/invoices/data/datasources/invoices_identity_datasource.dart';
import 'package:bb_mobile/features/get_paid/invoices/data/datasources/invoices_pay_service_datasource.dart';
import 'package:bb_mobile/features/get_paid/invoices/presentation/invoice_create_cubit.dart';
import 'package:bb_mobile/features/get_paid/invoices/presentation/invoice_detail_cubit.dart';
import 'package:bb_mobile/features/get_paid/invoices/presentation/invoices_list_cubit.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_dashboard_cubit.dart';
import 'package:bb_mobile/features/get_paid/shared/bullnym/bullnym_client.dart';
import 'package:bb_mobile/features/get_paid/shared/get_paid_identity_derivation.dart';
import 'package:bb_mobile/features/labels/labels_facade.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:get_it/get_it.dart';

class GetPaidLocator {
  static void setup(GetIt locator) {
    if (!locator.isRegistered<BullnymClient>()) {
      locator.registerLazySingleton<BullnymClient>(() => BullnymClient());
    }
    locator.registerLazySingleton<GetPaidIdentityDerivation>(
      () => GetPaidIdentityDerivation(
        walletRepository: locator<WalletRepository>(),
        seedRepository: locator<SeedRepository>(),
      ),
    );

    locator.registerLazySingleton<PaymentPageDatasource>(
      () => PaymentPageDatasource(bullnymClient: locator<BullnymClient>()),
    );
    locator.registerLazySingleton<PaymentPageIdentityDatasource>(
      () => PaymentPageIdentityDatasource(
        identityDerivation: locator<GetPaidIdentityDerivation>(),
      ),
    );
    locator.registerLazySingleton<PaymentPageServicePort>(
      () => locator<PaymentPageDatasource>(),
    );
    locator.registerLazySingleton<PaymentPageIdentityPort>(
      () => locator<PaymentPageIdentityDatasource>(),
    );
    locator.registerLazySingleton<InvoicesPayServiceDatasource>(
      () =>
          InvoicesPayServiceDatasource(bullnymClient: locator<BullnymClient>()),
    );
    locator.registerLazySingleton<InvoicesIdentityDatasource>(
      () => InvoicesIdentityDatasource(
        identityDerivation: locator<GetPaidIdentityDerivation>(),
      ),
    );
    locator.registerLazySingleton<InvoicesPayServicePort>(
      () => locator<InvoicesPayServiceDatasource>(),
    );
    locator.registerLazySingleton<InvoicesIdentityPort>(
      () => locator<InvoicesIdentityDatasource>(),
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
    locator.registerFactory<CreateInvoiceUsecase>(
      () => CreateInvoiceUsecase(
        walletRepository: locator<WalletRepository>(),
        walletAddressRepository: locator<WalletAddressRepository>(),
        labelsFacade: locator<LabelsFacade>(),
        invoiceService: locator<InvoicesPayServicePort>(),
        invoiceIdentity: locator<InvoicesIdentityPort>(),
      ),
    );
    locator.registerFactory<CancelInvoiceUsecase>(
      () => CancelInvoiceUsecase(
        invoiceService: locator<InvoicesPayServicePort>(),
        invoiceIdentity: locator<InvoicesIdentityPort>(),
      ),
    );
    locator.registerFactory<ListInvoicesUsecase>(
      () => ListInvoicesUsecase(
        invoiceService: locator<InvoicesPayServicePort>(),
        invoiceIdentity: locator<InvoicesIdentityPort>(),
      ),
    );
    locator.registerFactory<GetInvoiceUsecase>(
      () =>
          GetInvoiceUsecase(invoiceService: locator<InvoicesPayServicePort>()),
    );
    locator.registerFactory<InvoicesListCubit>(
      () => InvoicesListCubit(listInvoices: locator<ListInvoicesUsecase>()),
    );
    locator.registerFactory<InvoiceCreateCubit>(
      () => InvoiceCreateCubit(createInvoice: locator<CreateInvoiceUsecase>()),
    );
    locator.registerFactory<InvoiceDetailCubit>(
      () => InvoiceDetailCubit(
        getInvoice: locator<GetInvoiceUsecase>(),
        cancelInvoice: locator<CancelInvoiceUsecase>(),
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
