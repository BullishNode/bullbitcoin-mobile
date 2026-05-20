import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/features/external_receive_wallets/public/external_receive_wallets.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_settings_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class GetPaidSettingsCubit extends Cubit<GetPaidSettingsState> {
  final GetSettingsUsecase _getSettings;
  final ExternalReceiveWalletsFacade _externalReceiveWallets;

  GetPaidSettingsCubit({
    required GetSettingsUsecase getSettings,
    required ExternalReceiveWalletsFacade externalReceiveWallets,
  }) : _getSettings = getSettings,
       _externalReceiveWallets = externalReceiveWallets,
       super(const GetPaidSettingsState());

  Future<void> load() async {
    emit(state.copyWith(isLoadingSettings: true, loadFailed: false));

    try {
      final settings = await _getSettings.execute();
      final isTestnet = settings.environment.isTestnet;
      final lightningAddressLiquidAccountKey = _liquidAccountKey(
        ExternalReceiveWalletPurpose.lightningAddress,
        isTestnet: isTestnet,
      );
      final paymentPageLiquidAccountKey = _liquidAccountKey(
        ExternalReceiveWalletPurpose.paymentPage,
        isTestnet: isTestnet,
      );
      final btcpayLiquidAccountKey = _liquidAccountKey(
        ExternalReceiveWalletPurpose.btcpay,
        isTestnet: isTestnet,
      );
      final btcpayBitcoinAccountKey = _bitcoinAccountKey(
        ExternalReceiveWalletPurpose.btcpay,
        isTestnet: isTestnet,
      );
      final autoSweep = await _externalReceiveWallets.shouldAutoSweepForAccount(
        lightningAddressLiquidAccountKey,
      );
      final hideWallet = await _externalReceiveWallets.isHiddenOnHomeForAccount(
        lightningAddressLiquidAccountKey,
      );
      final paymentPageAutoSweep = await _externalReceiveWallets
          .shouldAutoSweepForAccount(paymentPageLiquidAccountKey);
      final paymentPageHideWallet = await _externalReceiveWallets
          .isHiddenOnHomeForAccount(paymentPageLiquidAccountKey);
      final btcpayAutoSweep = await _externalReceiveWallets
          .shouldAutoSweepForAccount(btcpayLiquidAccountKey);
      final btcpayHideWallet = await _externalReceiveWallets
          .isHiddenOnHomeForAccount(btcpayLiquidAccountKey);
      final btcpayBitcoinHideWallet = await _externalReceiveWallets
          .isHiddenOnHomeForAccount(btcpayBitcoinAccountKey);
      final btcpayBitcoinAutoSweep = await _externalReceiveWallets
          .shouldAutoSweepForAccount(btcpayBitcoinAccountKey);
      if (isClosed) return;
      emit(
        state.copyWith(
          isLoadingSettings: false,
          loadFailed: false,
          lightningAddressAutoSweep: autoSweep,
          lightningAddressHideWallet: hideWallet,
          paymentPageAutoSweep: paymentPageAutoSweep,
          paymentPageHideWallet: paymentPageHideWallet,
          btcpayLiquidAutoSweep: btcpayAutoSweep,
          btcpayLiquidHideWallet: btcpayHideWallet,
          btcpayBitcoinAutoSweep: btcpayBitcoinAutoSweep,
          btcpayBitcoinHideWallet: btcpayBitcoinHideWallet,
        ),
      );
    } catch (_) {
      if (isClosed) return;
      emit(state.copyWith(isLoadingSettings: false, loadFailed: true));
    }
  }

  Future<void> setLightningAddressAutoSweep(bool value) async {
    return _setGetPaidAutoSweep(
      purpose: ExternalReceiveWalletPurpose.lightningAddress,
      value: value,
    );
  }

  Future<bool> setLightningAddressHideWallet(bool value) async {
    return _setGetPaidHideWallet(
      purpose: ExternalReceiveWalletPurpose.lightningAddress,
      value: value,
    );
  }

  Future<void> setPaymentPageAutoSweep(bool value) {
    return _setGetPaidAutoSweep(
      purpose: ExternalReceiveWalletPurpose.paymentPage,
      value: value,
    );
  }

  Future<bool> setPaymentPageHideWallet(bool value) {
    return _setGetPaidHideWallet(
      purpose: ExternalReceiveWalletPurpose.paymentPage,
      value: value,
    );
  }

  Future<void> setBtcpayLiquidAutoSweep(bool value) {
    return _setGetPaidAutoSweep(
      purpose: ExternalReceiveWalletPurpose.btcpay,
      value: value,
    );
  }

  Future<bool> setBtcpayLiquidHideWallet(bool value) {
    return _setGetPaidHideWallet(
      purpose: ExternalReceiveWalletPurpose.btcpay,
      value: value,
    );
  }

  Future<bool> setBtcpayBitcoinHideWallet(bool value) {
    return _setGetPaidBitcoinHideWallet(
      purpose: ExternalReceiveWalletPurpose.btcpay,
      value: value,
    );
  }

  Future<void> setBtcpayBitcoinAutoSweep(bool value) {
    return _setGetPaidBitcoinAutoSweep(
      purpose: ExternalReceiveWalletPurpose.btcpay,
      value: value,
    );
  }

  Future<void> _setGetPaidAutoSweep({
    required ExternalReceiveWalletPurpose purpose,
    required bool value,
  }) async {
    if (state.operationInProgress) return;
    final isTestnet = await _isTestnet();
    if (isClosed) return;
    if (state.operationInProgress) return;
    final previous = _autoSweepValue(purpose);
    emit(
      _copyAutoSweep(
        state.copyWith(isSavingSettings: true, saveFailed: false),
        purpose: purpose,
        value: value,
      ),
    );

    try {
      await _externalReceiveWallets.setAutoSweepForAccount(
        _liquidAccountKey(purpose, isTestnet: isTestnet),
        value,
      );
      if (isClosed) return;
      emit(state.copyWith(isSavingSettings: false));
    } catch (_) {
      if (isClosed) return;
      emit(
        _copyAutoSweep(
          state.copyWith(isSavingSettings: false, saveFailed: true),
          purpose: purpose,
          value: previous,
        ),
      );
    }
  }

  Future<bool> _setGetPaidHideWallet({
    required ExternalReceiveWalletPurpose purpose,
    required bool value,
  }) async {
    if (state.operationInProgress) return false;
    final isTestnet = await _isTestnet();
    if (isClosed) return false;
    if (state.operationInProgress) return false;
    final previous = _hideWalletValue(purpose);
    emit(
      _copyHideWallet(
        state.copyWith(isSavingSettings: true, saveFailed: false),
        purpose: purpose,
        value: value,
      ),
    );

    try {
      await _externalReceiveWallets.setHiddenOnHomeForAccount(
        _liquidAccountKey(purpose, isTestnet: isTestnet),
        value,
      );
      if (isClosed) return false;
      emit(state.copyWith(isSavingSettings: false));
      return true;
    } catch (_) {
      if (isClosed) return false;
      emit(
        _copyHideWallet(
          state.copyWith(isSavingSettings: false, saveFailed: true),
          purpose: purpose,
          value: previous,
        ),
      );
      return false;
    }
  }

  Future<bool> _setGetPaidHideWalletForAccount({
    required ExternalReceiveWalletAccountKey accountKey,
    required bool value,
  }) async {
    if (state.operationInProgress) return false;
    final previous = _hideWalletValueForAccount(accountKey);
    emit(
      _copyHideWalletForAccount(
        state.copyWith(isSavingSettings: true, saveFailed: false),
        accountKey: accountKey,
        value: value,
      ),
    );

    try {
      await _externalReceiveWallets.setHiddenOnHomeForAccount(
        accountKey,
        value,
      );
      if (isClosed) return false;
      emit(state.copyWith(isSavingSettings: false));
      return true;
    } catch (_) {
      if (isClosed) return false;
      emit(
        _copyHideWalletForAccount(
          state.copyWith(isSavingSettings: false, saveFailed: true),
          accountKey: accountKey,
          value: previous,
        ),
      );
      return false;
    }
  }

  Future<bool> _setGetPaidBitcoinHideWallet({
    required ExternalReceiveWalletPurpose purpose,
    required bool value,
  }) async {
    if (state.operationInProgress) return false;
    final isTestnet = await _isTestnet();
    if (isClosed) return false;
    return _setGetPaidHideWalletForAccount(
      accountKey: _bitcoinAccountKey(purpose, isTestnet: isTestnet),
      value: value,
    );
  }

  Future<void> _setGetPaidAutoSweepForAccount({
    required ExternalReceiveWalletAccountKey accountKey,
    required bool value,
  }) async {
    if (state.operationInProgress) return;
    final previous = _autoSweepValueForAccount(accountKey);
    emit(
      _copyAutoSweepForAccount(
        state.copyWith(isSavingSettings: true, saveFailed: false),
        accountKey: accountKey,
        value: value,
      ),
    );

    try {
      await _externalReceiveWallets.setAutoSweepForAccount(accountKey, value);
      if (isClosed) return;
      emit(state.copyWith(isSavingSettings: false));
    } catch (_) {
      if (isClosed) return;
      emit(
        _copyAutoSweepForAccount(
          state.copyWith(isSavingSettings: false, saveFailed: true),
          accountKey: accountKey,
          value: previous,
        ),
      );
    }
  }

  Future<void> _setGetPaidBitcoinAutoSweep({
    required ExternalReceiveWalletPurpose purpose,
    required bool value,
  }) async {
    if (state.operationInProgress) return;
    final isTestnet = await _isTestnet();
    if (isClosed) return;
    return _setGetPaidAutoSweepForAccount(
      accountKey: _bitcoinAccountKey(purpose, isTestnet: isTestnet),
      value: value,
    );
  }

  Future<bool> _isTestnet() async {
    final settings = await _getSettings.execute();
    return settings.environment.isTestnet;
  }

  bool _autoSweepValue(ExternalReceiveWalletPurpose purpose) {
    return switch (purpose) {
      ExternalReceiveWalletPurpose.paymentPage => state.paymentPageAutoSweep,
      ExternalReceiveWalletPurpose.btcpay => state.btcpayLiquidAutoSweep,
      ExternalReceiveWalletPurpose.lightningAddress =>
        state.lightningAddressAutoSweep,
    };
  }

  bool _autoSweepValueForAccount(ExternalReceiveWalletAccountKey accountKey) {
    if (!accountKey.network.isLiquid &&
        accountKey.purpose == ExternalReceiveWalletPurpose.btcpay) {
      return state.btcpayBitcoinAutoSweep;
    }
    return _autoSweepValue(accountKey.purpose);
  }

  bool _hideWalletValue(ExternalReceiveWalletPurpose purpose) {
    return switch (purpose) {
      ExternalReceiveWalletPurpose.paymentPage => state.paymentPageHideWallet,
      ExternalReceiveWalletPurpose.btcpay => state.btcpayLiquidHideWallet,
      ExternalReceiveWalletPurpose.lightningAddress =>
        state.lightningAddressHideWallet,
    };
  }

  bool _hideWalletValueForAccount(ExternalReceiveWalletAccountKey accountKey) {
    if (!accountKey.network.isLiquid &&
        accountKey.purpose == ExternalReceiveWalletPurpose.btcpay) {
      return state.btcpayBitcoinHideWallet;
    }
    return _hideWalletValue(accountKey.purpose);
  }

  GetPaidSettingsState _copyAutoSweep(
    GetPaidSettingsState state, {
    required ExternalReceiveWalletPurpose purpose,
    required bool value,
  }) {
    return switch (purpose) {
      ExternalReceiveWalletPurpose.paymentPage => state.copyWith(
        paymentPageAutoSweep: value,
      ),
      ExternalReceiveWalletPurpose.btcpay => state.copyWith(
        btcpayLiquidAutoSweep: value,
      ),
      ExternalReceiveWalletPurpose.lightningAddress => state.copyWith(
        lightningAddressAutoSweep: value,
      ),
    };
  }

  GetPaidSettingsState _copyAutoSweepForAccount(
    GetPaidSettingsState state, {
    required ExternalReceiveWalletAccountKey accountKey,
    required bool value,
  }) {
    if (!accountKey.network.isLiquid &&
        accountKey.purpose == ExternalReceiveWalletPurpose.btcpay) {
      return state.copyWith(btcpayBitcoinAutoSweep: value);
    }
    return _copyAutoSweep(state, purpose: accountKey.purpose, value: value);
  }

  GetPaidSettingsState _copyHideWallet(
    GetPaidSettingsState state, {
    required ExternalReceiveWalletPurpose purpose,
    required bool value,
  }) {
    return switch (purpose) {
      ExternalReceiveWalletPurpose.paymentPage => state.copyWith(
        paymentPageHideWallet: value,
      ),
      ExternalReceiveWalletPurpose.btcpay => state.copyWith(
        btcpayLiquidHideWallet: value,
      ),
      ExternalReceiveWalletPurpose.lightningAddress => state.copyWith(
        lightningAddressHideWallet: value,
      ),
    };
  }

  GetPaidSettingsState _copyHideWalletForAccount(
    GetPaidSettingsState state, {
    required ExternalReceiveWalletAccountKey accountKey,
    required bool value,
  }) {
    if (!accountKey.network.isLiquid &&
        accountKey.purpose == ExternalReceiveWalletPurpose.btcpay) {
      return state.copyWith(btcpayBitcoinHideWallet: value);
    }
    return _copyHideWallet(state, purpose: accountKey.purpose, value: value);
  }

  Future<void> restoreGetPaidWallets() async {
    if (state.operationInProgress) return;

    emit(
      state.copyWith(
        isRestoringWallets: true,
        restoreFailed: false,
        clearRestoreOutcomes: true,
      ),
    );

    try {
      final settings = await _getSettings.execute();
      if (isClosed) return;
      final outcomes = await _externalReceiveWallets
          .restoreReservedExternalReceiveWallets(
            environment: settings.environment,
          );
      if (isClosed) return;
      emit(
        state.copyWith(
          isRestoringWallets: false,
          restoreOutcomes: outcomes,
          restoreFailed: false,
        ),
      );
    } catch (_) {
      if (isClosed) return;
      emit(state.copyWith(isRestoringWallets: false, restoreFailed: true));
    }
  }
}

ExternalReceiveWalletAccountKey _liquidAccountKey(
  ExternalReceiveWalletPurpose purpose, {
  required bool isTestnet,
}) {
  return switch (purpose) {
    ExternalReceiveWalletPurpose.lightningAddress =>
      ExternalReceiveWalletPurpose.lightningAddress.liquidAccountKey(
        isTestnet: isTestnet,
      ),
    ExternalReceiveWalletPurpose.paymentPage =>
      ExternalReceiveWalletPurpose.paymentPage.liquidAccountKey(
        isTestnet: isTestnet,
      ),
    ExternalReceiveWalletPurpose.btcpay =>
      ExternalReceiveWalletPurpose.btcpay.liquidAccountKey(
        isTestnet: isTestnet,
      ),
  };
}

ExternalReceiveWalletAccountKey _bitcoinAccountKey(
  ExternalReceiveWalletPurpose purpose, {
  required bool isTestnet,
}) {
  return purpose.bitcoinAccountKey(isTestnet: isTestnet);
}
