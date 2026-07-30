import 'package:bb_mobile/core/export/domain/transaction_export_saver.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallets_usecase.dart';
import 'package:bb_mobile/features/automatic_fallback/public/automatic_fallback_facade.dart';
import 'package:bb_mobile/features/btcpay/public/btcpay_facade.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart';
import 'package:bb_mobile/features/fiat_settlement/public/fiat_settlement_facade.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/find_get_paid_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/find_get_paid_pos_terminal_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/get_get_paid_btcpay_connection_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/get_get_paid_fiat_settlement_summary_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/load_get_paid_invoices_overview_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/load_get_paid_product_overview_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/look_up_get_paid_invoice_facts_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/look_up_get_paid_lightning_registration_usecase.dart';
import 'package:bb_mobile/features/get_paid/get_paid_locator.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_dashboard_cubit.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_invoice_facts_cubit.dart';
import 'package:bb_mobile/features/invoices/public/invoices_facade.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bb_mobile/features/payment_page/public/payment_page_facade.dart';
import 'package:bb_mobile/features/pos/public/pos_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

class _MockAutomaticFallbackFacade extends Mock
    implements AutomaticFallbackFacade {}

class _MockInvoicesFacade extends Mock implements InvoicesFacade {}

class _MockLightningAddressFacade extends Mock
    implements LightningAddressFacade {}

class _MockPaymentPageFacade extends Mock implements PaymentPageFacade {}

class _MockPosFacade extends Mock implements PosFacade {}

class _MockBtcpayFacade extends Mock implements BtcpayFacade {}

class _MockFiatSettlementFacade extends Mock implements FiatSettlementFacade {}

class _MockBullnymFacade extends Mock implements BullnymFacade {}

class _MockNostrIdentityFacade extends Mock implements NostrIdentityFacade {}

class _MockGetSettingsUsecase extends Mock implements GetSettingsUsecase {}

class _MockGetWalletsUsecase extends Mock implements GetWalletsUsecase {}

class _MockWalletRepository extends Mock implements WalletRepository {}

class _MockSeedRepository extends Mock implements SeedRepository {}

class _MockTransactionExportSaver extends Mock
    implements TransactionExportSaver {}

/// Boot coverage for the hub: every use case the Get Paid presentation layer
/// depends on is registered, and each one resolves from the provider facades
/// alone. A missing registration is a runtime crash on entering the hub, which no
/// widget test would catch.
void main() {
  late GetIt locator;

  setUp(() {
    locator = GetIt.asNewInstance();
    // Provider features and core register before the consumer.
    locator.registerSingleton<AutomaticFallbackFacade>(
      _MockAutomaticFallbackFacade(),
    );
    locator.registerSingleton<InvoicesFacade>(_MockInvoicesFacade());
    locator.registerSingleton<LightningAddressFacade>(
      _MockLightningAddressFacade(),
    );
    locator.registerSingleton<PaymentPageFacade>(_MockPaymentPageFacade());
    locator.registerSingleton<PosFacade>(_MockPosFacade());
    locator.registerSingleton<BtcpayFacade>(_MockBtcpayFacade());
    locator.registerSingleton<FiatSettlementFacade>(
      _MockFiatSettlementFacade(),
    );
    locator.registerSingleton<BullnymFacade>(_MockBullnymFacade());
    locator.registerSingleton<NostrIdentityFacade>(_MockNostrIdentityFacade());
    locator.registerSingleton<GetSettingsUsecase>(_MockGetSettingsUsecase());
    locator.registerSingleton<GetWalletsUsecase>(_MockGetWalletsUsecase());
    locator.registerSingleton<WalletRepository>(_MockWalletRepository());
    locator.registerSingleton<SeedRepository>(_MockSeedRepository());
    locator.registerSingleton<TransactionExportSaver>(
      _MockTransactionExportSaver(),
    );

    GetPaidLocator.setup(locator);
  });

  tearDown(() => locator.reset());

  test('the hub cubit resolves with every boundary use case wired', () {
    expect(locator<GetPaidDashboardCubit>(), isA<GetPaidDashboardCubit>());
  });

  test('the detail card cubit resolves', () {
    expect(
      locator<GetPaidInvoiceFactsCubit>(),
      isA<GetPaidInvoiceFactsCubit>(),
    );
  });

  test('each foreign boundary is reachable only through its use case', () {
    expect(
      locator<LookUpGetPaidLightningRegistrationUsecase>(),
      isA<LookUpGetPaidLightningRegistrationUsecase>(),
    );
    expect(
      locator<FindGetPaidPaymentPageUsecase>(),
      isA<FindGetPaidPaymentPageUsecase>(),
    );
    expect(
      locator<FindGetPaidPosTerminalUsecase>(),
      isA<FindGetPaidPosTerminalUsecase>(),
    );
    expect(
      locator<GetGetPaidBtcpayConnectionUsecase>(),
      isA<GetGetPaidBtcpayConnectionUsecase>(),
    );
    expect(
      locator<GetGetPaidFiatSettlementSummaryUsecase>(),
      isA<GetGetPaidFiatSettlementSummaryUsecase>(),
    );
    expect(
      locator<LookUpGetPaidInvoiceFactsUsecase>(),
      isA<LookUpGetPaidInvoiceFactsUsecase>(),
    );
    expect(
      locator<LoadGetPaidProductOverviewUsecase>(),
      isA<LoadGetPaidProductOverviewUsecase>(),
    );
    expect(
      locator<LoadGetPaidInvoicesOverviewUsecase>(),
      isA<LoadGetPaidInvoicesOverviewUsecase>(),
    );
  });
}
