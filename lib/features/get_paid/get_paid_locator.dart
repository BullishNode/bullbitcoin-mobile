import 'package:bb_mobile/core/export/domain/transaction_export_saver.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallets_usecase.dart';
import 'package:bb_mobile/features/automatic_fallback/public/automatic_fallback_facade.dart';
import 'package:bb_mobile/features/btcpay/public/btcpay_facade.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart';
import 'package:bb_mobile/features/fiat_settlement/public/fiat_settlement_facade.dart';
import 'package:bb_mobile/features/get_paid/data/get_paid_default_wallet_xprv_adapter.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_default_wallet_xprv_port.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_transaction.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/ensure_get_paid_automatic_fallback_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/ensure_get_paid_product_wallet_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/export_get_paid_transactions_csv_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/find_get_paid_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/find_get_paid_pos_terminal_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/get_get_paid_btcpay_connection_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/get_get_paid_fiat_settlement_summary_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/get_paid_fallback_attention_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/list_get_paid_transactions_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/load_get_paid_invoices_overview_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/load_get_paid_product_overview_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/look_up_get_paid_invoice_facts_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/look_up_get_paid_lightning_registration_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/look_up_get_paid_transaction_usecase.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_dashboard_cubit.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_export_cubit.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_invoice_facts_cubit.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_transaction_detail_cubit.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_transaction_history_cubit.dart';
import 'package:bb_mobile/features/invoices/public/invoices_facade.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bb_mobile/features/payment_page/public/payment_page_facade.dart';
import 'package:bb_mobile/features/pos/public/pos_facade.dart';
import 'package:get_it/get_it.dart';

/// Wires the Get Paid hub after all product facades and automatic fallback. The
/// foreign facades are consumed only by Get Paid's own use cases — the hub cubit
/// is wired to those use cases, never to another feature's facade.
class GetPaidLocator {
  static void setup(GetIt locator) {
    locator.registerFactory<EnsureGetPaidAutomaticFallbackUsecase>(
      () => EnsureGetPaidAutomaticFallbackUsecase(
        automaticFallback: locator<AutomaticFallbackFacade>(),
      ),
    );
    locator.registerFactory<GetPaidFallbackAttentionUsecase>(
      () =>
          GetPaidFallbackAttentionUsecase(invoices: locator<InvoicesFacade>()),
    );
    locator.registerFactory<LoadGetPaidInvoicesOverviewUsecase>(
      () => LoadGetPaidInvoicesOverviewUsecase(
        getWallets: locator<GetWalletsUsecase>(),
        fallbackAttention: locator<GetPaidFallbackAttentionUsecase>(),
      ),
    );
    locator.registerFactory<EnsureGetPaidProductWalletUsecase>(
      () => EnsureGetPaidProductWalletUsecase(
        locator<LightningAddressFacade>(),
        locator<PaymentPageFacade>(),
        locator<PosFacade>(),
      ),
    );
    locator.registerFactory<LookUpGetPaidLightningRegistrationUsecase>(
      () => LookUpGetPaidLightningRegistrationUsecase(
        lightningAddress: locator<LightningAddressFacade>(),
      ),
    );
    locator.registerFactory<FindGetPaidPaymentPageUsecase>(
      () => FindGetPaidPaymentPageUsecase(
        paymentPage: locator<PaymentPageFacade>(),
      ),
    );
    locator.registerFactory<FindGetPaidPosTerminalUsecase>(
      () => FindGetPaidPosTerminalUsecase(pos: locator<PosFacade>()),
    );
    locator.registerFactory<GetGetPaidBtcpayConnectionUsecase>(
      () => GetGetPaidBtcpayConnectionUsecase(btcpay: locator<BtcpayFacade>()),
    );
    locator.registerFactory<GetGetPaidFiatSettlementSummaryUsecase>(
      () => GetGetPaidFiatSettlementSummaryUsecase(
        fiatSettlement: locator<FiatSettlementFacade>(),
        getSettings: locator<GetSettingsUsecase>(),
      ),
    );
    locator.registerFactory<LoadGetPaidProductOverviewUsecase>(
      () => LoadGetPaidProductOverviewUsecase(
        lookUpRegistration:
            locator<LookUpGetPaidLightningRegistrationUsecase>(),
        findPaymentPage: locator<FindGetPaidPaymentPageUsecase>(),
        findPos: locator<FindGetPaidPosTerminalUsecase>(),
        ensureAutomaticFallback:
            locator<EnsureGetPaidAutomaticFallbackUsecase>(),
        ensureProductWallet: locator<EnsureGetPaidProductWalletUsecase>(),
      ),
    );
    locator.registerFactory<LookUpGetPaidInvoiceFactsUsecase>(
      () =>
          LookUpGetPaidInvoiceFactsUsecase(invoices: locator<InvoicesFacade>()),
    );
    locator.registerFactory<GetPaidInvoiceFactsCubit>(
      () => GetPaidInvoiceFactsCubit(
        lookUpInvoiceFacts: locator<LookUpGetPaidInvoiceFactsUsecase>(),
      ),
    );
    locator.registerFactory<GetPaidDefaultWalletXprvPort>(
      () => GetPaidDefaultWalletXprvAdapter(
        getSettings: locator<GetSettingsUsecase>(),
        walletRepository: locator<WalletRepository>(),
        seedRepository: locator<SeedRepository>(),
      ),
    );
    locator.registerFactory<ListGetPaidTransactionsUsecase>(
      () => ListGetPaidTransactionsUsecase(
        defaultWalletXprv: locator<GetPaidDefaultWalletXprvPort>(),
        bullnym: locator<BullnymFacade>(),
        nostrIdentity: locator<NostrIdentityFacade>(),
      ),
    );
    locator.registerFactory<LookUpGetPaidTransactionUsecase>(
      () => LookUpGetPaidTransactionUsecase(
        locator<ListGetPaidTransactionsUsecase>(),
      ),
    );
    locator.registerFactoryParam<
      GetPaidTransactionDetailCubit,
      GetPaidTransaction,
      void
    >(
      (transaction, _) => GetPaidTransactionDetailCubit(
        locator<LookUpGetPaidTransactionUsecase>(),
        initialTransaction: transaction,
      ),
    );
    locator.registerFactory<GetPaidTransactionHistoryCubit>(
      () => GetPaidTransactionHistoryCubit(
        listTransactions: locator<ListGetPaidTransactionsUsecase>(),
      ),
    );
    locator.registerFactory<ExportGetPaidTransactionsCsvUsecase>(
      () => ExportGetPaidTransactionsCsvUsecase(
        listTransactions: locator<ListGetPaidTransactionsUsecase>(),
      ),
    );
    locator.registerFactory<GetPaidExportCubit>(
      () => GetPaidExportCubit(
        exportCsv: locator<ExportGetPaidTransactionsCsvUsecase>(),
        saver: locator<TransactionExportSaver>(),
      ),
    );
    locator.registerFactory<GetPaidDashboardCubit>(
      () => GetPaidDashboardCubit(
        loadProductOverview: locator<LoadGetPaidProductOverviewUsecase>(),
        getBtcpayConnection: locator<GetGetPaidBtcpayConnectionUsecase>(),
        loadInvoicesOverview: locator<LoadGetPaidInvoicesOverviewUsecase>(),
        fiatSettlementSummary:
            locator<GetGetPaidFiatSettlementSummaryUsecase>(),
      ),
    );
  }
}
