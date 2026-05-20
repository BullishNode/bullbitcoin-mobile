import 'package:bb_mobile/features/external_receive_wallets/public/external_receive_wallets.dart';

class GetPaidSettingsState {
  final bool isLoadingSettings;
  final bool loadFailed;
  final bool saveFailed;
  final bool isSavingSettings;
  final bool lightningAddressLiquidAutoSweep;
  final bool lightningAddressLiquidHideWallet;
  final bool paymentPageAutoSweep;
  final bool paymentPageHideWallet;
  final bool btcpayLiquidAutoSweep;
  final bool btcpayLiquidHideWallet;
  final bool btcpayBitcoinAutoSweep;
  final bool btcpayBitcoinHideWallet;
  final bool isRestoringWallets;
  final List<ExternalReceiveWalletRestoreOutcome>? restoreOutcomes;
  final bool restoreFailed;

  const GetPaidSettingsState({
    this.isLoadingSettings = false,
    this.loadFailed = false,
    this.saveFailed = false,
    this.isSavingSettings = false,
    this.lightningAddressLiquidAutoSweep = true,
    this.lightningAddressLiquidHideWallet = true,
    this.paymentPageAutoSweep = true,
    this.paymentPageHideWallet = true,
    this.btcpayLiquidAutoSweep = true,
    this.btcpayLiquidHideWallet = true,
    this.btcpayBitcoinAutoSweep = false,
    this.btcpayBitcoinHideWallet = false,
    this.isRestoringWallets = false,
    this.restoreOutcomes,
    this.restoreFailed = false,
  });

  bool get operationInProgress =>
      isLoadingSettings || isRestoringWallets || isSavingSettings;
  bool get blocksNavigation => isRestoringWallets || isSavingSettings;

  GetPaidSettingsState copyWith({
    bool? isLoadingSettings,
    bool? loadFailed,
    bool? saveFailed,
    bool? isSavingSettings,
    bool? lightningAddressLiquidAutoSweep,
    bool? lightningAddressLiquidHideWallet,
    bool? paymentPageAutoSweep,
    bool? paymentPageHideWallet,
    bool? btcpayLiquidAutoSweep,
    bool? btcpayLiquidHideWallet,
    bool? btcpayBitcoinAutoSweep,
    bool? btcpayBitcoinHideWallet,
    bool? isRestoringWallets,
    List<ExternalReceiveWalletRestoreOutcome>? restoreOutcomes,
    bool? restoreFailed,
    bool clearRestoreOutcomes = false,
  }) {
    return GetPaidSettingsState(
      isLoadingSettings: isLoadingSettings ?? this.isLoadingSettings,
      loadFailed: loadFailed ?? this.loadFailed,
      saveFailed: saveFailed ?? this.saveFailed,
      isSavingSettings: isSavingSettings ?? this.isSavingSettings,
      lightningAddressLiquidAutoSweep:
          lightningAddressLiquidAutoSweep ??
          this.lightningAddressLiquidAutoSweep,
      lightningAddressLiquidHideWallet:
          lightningAddressLiquidHideWallet ??
          this.lightningAddressLiquidHideWallet,
      paymentPageAutoSweep: paymentPageAutoSweep ?? this.paymentPageAutoSweep,
      paymentPageHideWallet:
          paymentPageHideWallet ?? this.paymentPageHideWallet,
      btcpayLiquidAutoSweep:
          btcpayLiquidAutoSweep ?? this.btcpayLiquidAutoSweep,
      btcpayLiquidHideWallet:
          btcpayLiquidHideWallet ?? this.btcpayLiquidHideWallet,
      btcpayBitcoinAutoSweep:
          btcpayBitcoinAutoSweep ?? this.btcpayBitcoinAutoSweep,
      btcpayBitcoinHideWallet:
          btcpayBitcoinHideWallet ?? this.btcpayBitcoinHideWallet,
      isRestoringWallets: isRestoringWallets ?? this.isRestoringWallets,
      restoreOutcomes: clearRestoreOutcomes
          ? null
          : restoreOutcomes ?? this.restoreOutcomes,
      restoreFailed: restoreFailed ?? this.restoreFailed,
    );
  }
}
