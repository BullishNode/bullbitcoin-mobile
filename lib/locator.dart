import 'dart:async';

import 'package:bb_mobile/core/ark/locator.dart';
import 'package:bb_mobile/core/core_locator.dart';
import 'package:bb_mobile/core/payjoin/domain/repositories/payjoin_repository.dart';
import 'package:bb_mobile/core/status/status_locator.dart';
import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/core/sync/sync_locator.dart';
import 'package:bb_mobile/features/address_view/address_view_locator.dart';
import 'package:bb_mobile/features/all_seed_view/all_seed_view_locator.dart';
import 'package:bb_mobile/features/automatic_fallback/automatic_fallback_locator.dart';
import 'package:bb_mobile/features/app_startup/app_startup_locator.dart';
import 'package:bb_mobile/features/announcements/announcements_locator.dart';
import 'package:bb_mobile/features/app_unlock/app_unlock_locator.dart';
import 'package:bb_mobile/features/autosweep/autosweep_locator.dart';
import 'package:bb_mobile/features/autoswap/autoswap_locator.dart';
import 'package:bb_mobile/features/backup_settings/backup_settings_locator.dart';
import 'package:bb_mobile/features/bip85_entropy/locator.dart';
import 'package:bb_mobile/features/bip85_registry/bip85_registry_locator.dart';
import 'package:bb_mobile/features/bitbox/bitbox_locator.dart';
import 'package:bb_mobile/features/bitcoin_price/bitcoin_price_locator.dart';
import 'package:bb_mobile/features/broadcast_signed_tx/locator.dart';
import 'package:bb_mobile/features/bullnym/bullnym_locator.dart';
import 'package:bb_mobile/features/btcpay/btcpay_locator.dart';
import 'package:bb_mobile/features/buy/buy_locator.dart';
import 'package:bb_mobile/features/coins/coins_locator.dart';
import 'package:bb_mobile/features/consolidation/consolidation_locator.dart';
import 'package:bb_mobile/features/dca/dca_locator.dart';
import 'package:bb_mobile/features/deterministic_wallets/deterministic_wallets_locator.dart';
import 'package:bb_mobile/features/electrum_settings/electrum_settings_locator.dart';
import 'package:bb_mobile/features/exchange/exchange_locator.dart';
import 'package:bb_mobile/features/exchange_settings/exchange_settings_locator.dart';
import 'package:bb_mobile/features/mempool_settings/mempool_settings_locator.dart';
import 'package:bb_mobile/features/fiat_settlement/fiat_settlement_locator.dart';
import 'package:bb_mobile/features/fund_exchange/fund_exchange_locator.dart';
import 'package:bb_mobile/features/get_paid/get_paid_locator.dart';
import 'package:bb_mobile/features/get_paid_settings/get_paid_settings_locator.dart';
import 'package:bb_mobile/features/import_mnemonic/locator.dart';
import 'package:bb_mobile/features/import_watch_only_wallet/import_watch_only_locator.dart';
import 'package:bb_mobile/features/invoices/invoices_locator.dart';
import 'package:bb_mobile/features/keychain_manifest/keychain_manifest_locator.dart';
import 'package:bb_mobile/features/keychain_recovery/keychain_recovery_locator.dart';
import 'package:bb_mobile/features/ledger/ledger_locator.dart';
import 'package:bb_mobile/features/legacy_seed_view/legacy_seed_view_locator.dart';
import 'package:bb_mobile/features/lightning_address/lightning_address_locator.dart';
import 'package:bb_mobile/features/nostr_identity/nostr_identity_locator.dart';
import 'package:bb_mobile/features/onboarding/onboarding_locator.dart';
import 'package:bb_mobile/features/pay/pay_locator.dart';
import 'package:bb_mobile/features/payment_page/payment_page_locator.dart';
import 'package:bb_mobile/features/pos/pos_locator.dart';
import 'package:bb_mobile/features/pin_code/pin_code_locator.dart';
import 'package:bb_mobile/features/receive/receive_locator.dart';
import 'package:bb_mobile/features/recipients/recipients_locator.dart';
import 'package:bb_mobile/features/recoverbull/recoverbull_locator.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/remote_keychain_recovery_locator.dart';
import 'package:bb_mobile/features/replace_by_fee/locator.dart';
import 'package:bb_mobile/features/sell/sell_locator.dart';
import 'package:bb_mobile/features/send/send_locator.dart';
import 'package:bb_mobile/features/settings/settings_locator.dart';
import 'package:bb_mobile/features/status_check/locator.dart';
import 'package:bb_mobile/features/swap/swap_locator.dart';
import 'package:bb_mobile/features/test_wallet_backup/test_wallet_backup_locator.dart';
import 'package:bb_mobile/features/tor_settings/tor_settings_locator.dart';
import 'package:bb_mobile/features/transactions/transactions_locator.dart';
import 'package:bb_mobile/features/wallet/wallet_locator.dart';
import 'package:bb_mobile/features/wallet_backup/wallet_backup_locator.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/wallet_metadata_backup_locator.dart';
import 'package:bb_mobile/features/withdraw/withdraw_locator.dart';
import 'package:bb_mobile/features/wizard/wizard_locator.dart';
import 'package:get_it/get_it.dart';

final GetIt locator = GetIt.instance;

class AppLocator {
  /// Call this in the `main` function **before** `runApp()`
  static Future<void> setup(GetIt locator, SqliteDatabase database) async {
    locator.enableRegisteringMultipleInstancesOfOneType();

    // Register core dependencies first
    CoreLocator.register(locator, database);
    await CoreLocator.registerDatasources(locator);
    // Note: since the WalletLocator repositories depend on ports for electrum servers,
    // we need to make sure the ports are registered before the repositories
    // This is a hack though as normally repositories should not depend on ports
    // The proper solution is to refactor the code to remove this dependency
    CoreLocator.registerPorts(locator);
    await CoreLocator.registerRepositories(locator);
    CoreLocator.registerServices(locator);
    CoreLocator.registerUsecases(locator);
    CoreLocator.registerFrameworks(locator);
    CoreLocator.registerFacades(locator);

    // Every dependency PayjoinRepositoryImpl needs (wallet repositories,
    //  settings, the labels facade) is now guaranteed registered — resume any
    //  unfinished payjoin sessions left over from a previous run. Not awaited:
    //  this is background work (relay polling, wallet syncs) that must not
    //  delay app startup. See resumePayjoinsOnStartup's doc for why this
    //  can't just run in the repository's constructor.
    unawaited(locator<PayjoinRepository>().resumePayjoinsOnStartup());

    SyncLocator.setup(locator);

    // Register feature-specific dependencies
    ElectrumSettingsLocator.setup(locator);
    MempoolSettingsLocator.setup(locator);
    TorSettingsLocator.setup(locator);
    PinCodeLocator.setup(locator);
    WizardLocator.setup(locator);
    AppStartupLocator.setup(locator);
    AppUnlockLocator.setup(locator);
    TestWalletBackupLocator.setup(locator);
    OnboardingLocator.setup(locator);
    LegacySeedViewLocator.setup(locator);
    AllSeedViewLocator.setup(locator);
    SettingsLocator.setup(locator);
    BitcoinPriceLocator.setup(locator);
    AutosweepLocator.setup(locator);
    WalletLocator.setup(locator);
    TransactionsLocator.registerAdapters(locator);
    Bip85RegistryLocator.setup(locator);
    NostrIdentityLocator.setup(locator);
    DeterministicWalletsLocator.setup(locator);
    KeychainManifestLocator.setup(locator);
    WalletBackupLocator.setup(locator);
    WalletMetadataBackupLocator.setup(locator);
    KeychainRecoveryLocator.setup(locator);
    BullnymLocator.setup(locator);
    GetPaidSettingsLocator.setup(locator);
    AutomaticFallbackLocator.setup(locator);
    LightningAddressLocator.setup(locator);
    PaymentPageLocator.setup(locator);
    PosLocator.setup(locator);
    FiatSettlementLocator.setup(locator);
    InvoicesLocator.setup(locator);
    RemoteKeychainRecoveryLocator.setup(locator);
    BtcpayLocator.setup(locator);
    GetPaidLocator.setup(locator);
    TransactionsLocator.registerUsecases(locator);
    TransactionsLocator.registerBlocs(locator);
    ReceiveLocator.setup(locator);
    RecoverBullLocator.setup(locator);
    SendLocator.setup(locator);
    CoinsLocator.setup(locator);
    ConsolidationLocator.setup(locator);
    BackupSettingsLocator.setup(locator);
    AnnouncementsLocator.setup(locator);
    ImportWatchOnlyLocator.setup(locator);
    BroadcastSignedTxLocator.setup(locator);
    SwapLocator.setup(locator);

    ExchangeLocator.setup(locator);
    ExchangeSettingsLocator.setup(locator);
    BuyLocator.setup(locator);
    SellLocator.setup(locator);
    WithdrawLocator.setup(locator);
    PayLocator.setup(locator);
    StatusLocator.setup(locator);
    StatusCheckLocator.setup(locator);

    FundExchangeLocator.setup(locator);
    AutoSwapLocator.setup(locator);
    AddressViewLocator.setup(locator);
    ImportMnemonicLocator.setup(locator);
    DcaLocator.setup(locator);
    ReplaceByFeeLocator.setup(locator);
    Bip85EntropyLocator.setup(locator);
    LedgerLocator.setup(locator);
    RecipientsLocator.setup(locator);
    BitBoxLocator.setup(locator);
    ArkCoreLocator.setup(locator);
  }

  static void startForeground(GetIt locator) {
    WalletBackupLocator.start(locator);
  }
}
