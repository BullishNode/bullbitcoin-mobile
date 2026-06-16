import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/btcpay/application/application_errors.dart';
import 'package:bb_mobile/features/btcpay/application/usecases/complete_btcpay_samrock_pairing_usecase.dart';
import 'package:bb_mobile/features/btcpay/application/usecases/get_btcpay_wallet_behaviors_usecase.dart';
import 'package:bb_mobile/features/btcpay/application/usecases/get_btcpay_connection_usecase.dart';
import 'package:bb_mobile/features/btcpay/application/usecases/preview_btcpay_samrock_pairing_usecase.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_connection.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_wallet.dart';
import 'package:bb_mobile/features/btcpay/presentation/btcpay_pairing_state.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/update_wallet_behavior_usecase.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class BtcpayPairingCubit extends Cubit<BtcpayPairingState> {
  final CompleteBtcpaySamRockPairingUsecase _completePairing;
  final GetBtcpayConnectionUsecase _getConnection;
  final GetBtcpayWalletBehaviorsUsecase _getWalletBehaviors;
  final PreviewBtcpaySamRockPairingUsecase _previewPairing;
  final UpdateWalletBehaviorUsecase _updateWalletBehavior;

  BtcpayPairingCubit({
    required this._completePairing,
    required this._getConnection,
    required this._getWalletBehaviors,
    required this._previewPairing,
    required this._updateWalletBehavior,
  }) : super(const BtcpayPairingState());

  Future<void> load() async {
    if (state.isSubmitting || state.connection != null) return;
    try {
      final connection = await _getConnection.execute();
      final walletBehaviors = connection == null
          ? const <BtcpayWalletBehaviorViewModel>[]
          : await _loadWalletBehaviors(connection);
      if (isClosed) return;
      emit(
        state.copyWith(
          status: BtcpayPairingStatus.idle,
          connection: connection == null ? null : _connectionView(connection),
          walletBehaviors: walletBehaviors,
          clearConnection: connection == null,
        ),
      );
    } on Exception catch (e, stack) {
      log.warning('Failed to load BTCPay connection', error: e, trace: stack);
      if (isClosed) return;
      emit(state.copyWith(status: BtcpayPairingStatus.idle));
    }
  }

  BtcpayPairingPreview? preview(String pairingUrl) {
    try {
      final preview = _previewPairing.execute(pairingUrl);
      return BtcpayPairingPreview(
        serverUrl: preview.serverUrl,
        supportsBitcoinChain: preview.supportsBitcoinChain,
        supportsLiquidChain: preview.supportsLiquidChain,
        supportsLightning: preview.supportsLightning,
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: BtcpayPairingStatus.failure,
          failure: _failureFor(e),
          clearConnection: true,
          showPairingForm: true,
        ),
      );
      return null;
    }
  }

  void pairNew() {
    if (state.isSubmitting) return;
    emit(
      state.copyWith(
        status: BtcpayPairingStatus.idle,
        clearFailure: true,
        showPairingForm: true,
      ),
    );
  }

  void clearPairingFailure() {
    if (state.isSubmitting || state.failure == null) return;
    emit(
      state.copyWith(
        status: BtcpayPairingStatus.idle,
        clearFailure: true,
        showPairingForm: true,
      ),
    );
  }

  Future<void> submit(String pairingUrl) async {
    if (state.isSubmitting) return;
    emit(
      state.copyWith(
        status: BtcpayPairingStatus.submitting,
        clearFailure: true,
        showPairingForm: true,
      ),
    );

    try {
      final connection = await _completePairing.execute(pairingUrl: pairingUrl);
      if (isClosed) return;
      final walletBehaviors = await _loadWalletBehaviors(connection);
      if (isClosed) return;
      emit(
        state.copyWith(
          status: BtcpayPairingStatus.success,
          connection: _connectionView(connection),
          walletBehaviors: walletBehaviors,
          showPairingForm: false,
        ),
      );
    } catch (e) {
      if (isClosed) return;
      final connection = await _connectionAfterUncertainFailure(e);
      if (isClosed) return;
      emit(
        state.copyWith(
          status: BtcpayPairingStatus.failure,
          failure: _failureFor(e),
          connection: connection == null ? null : _connectionView(connection),
          clearConnection: connection == null,
          showPairingForm: connection == null,
        ),
      );
    }
  }

  Future<void> updateWalletBehavior({
    required String walletId,
    bool? hideOnHome,
    bool? autoSweepEnabled,
  }) async {
    if (state.walletSettingsSaving) return;
    final previous = state.walletBehaviors;
    final updated = previous.map((behavior) {
      if (behavior.walletId != walletId) return behavior;
      return behavior.copyWith(
        hideOnHome: hideOnHome,
        autoSweepEnabled: autoSweepEnabled,
      );
    }).toList();
    emit(state.copyWith(walletBehaviors: updated, walletSettingsSaving: true));
    try {
      await _updateWalletBehavior.execute(
        walletId: walletId,
        hideOnHome: hideOnHome,
        autoSweepEnabled: autoSweepEnabled,
      );
      if (isClosed) return;
      emit(
        state.copyWith(
          walletBehaviors: await _loadWalletBehaviors(),
          walletSettingsSaving: false,
        ),
      );
    } catch (e, stack) {
      log.warning(
        'Failed to update BTCPay wallet behavior',
        error: e,
        trace: stack,
      );
      if (isClosed) return;
      emit(
        state.copyWith(
          status: BtcpayPairingStatus.failure,
          failure: BtcpayPairingFailure.generic,
          walletBehaviors: previous,
          walletSettingsSaving: false,
        ),
      );
    }
  }

  BtcpayPairingFailure _failureFor(Object error) {
    return switch (error) {
      BtcpayPairingException(type: BtcpayPairingExceptionType.invalidRequest) =>
        BtcpayPairingFailure.invalidRequest,
      BtcpayPairingException(type: BtcpayPairingExceptionType.localSetup) =>
        BtcpayPairingFailure.localSetup,
      BtcpayPairingException(type: BtcpayPairingExceptionType.rejected) =>
        BtcpayPairingFailure.rejected,
      BtcpayPairingException(type: BtcpayPairingExceptionType.uncertain) =>
        BtcpayPairingFailure.uncertain,
      _ => BtcpayPairingFailure.generic,
    };
  }

  Future<BtcpayConnection?> _connectionAfterUncertainFailure(
    Object error,
  ) async {
    if (error case BtcpayPairingException(
      type: BtcpayPairingExceptionType.uncertain,
    )) {
      try {
        return await _getConnection.execute();
      } on Exception catch (e, stack) {
        log.warning(
          'Failed to load uncertain BTCPay connection',
          error: e,
          trace: stack,
        );
      }
    }
    return null;
  }

  BtcpayConnectionViewModel _connectionView(BtcpayConnection connection) {
    return BtcpayConnectionViewModel(
      serverUrl: connection.serverUrl,
      storeId: connection.storeId,
      rails: [
        if (connection.supportsBitcoinChain) BtcpayPairingRail.bitcoin,
        if (connection.supportsLiquidChain) BtcpayPairingRail.liquid,
        if (connection.supportsLightning) BtcpayPairingRail.lightning,
      ],
      wallets: connection.walletNetworks.map((network) {
        return switch (network) {
          BtcpayWalletNetwork.bitcoin => BtcpayPairingWallet.bitcoin,
          BtcpayWalletNetwork.liquid => BtcpayPairingWallet.liquid,
        };
      }).toList(),
      isUncertain: connection.isUncertain,
      isPaired: connection.isPaired,
      displayDate: connection.pairedAt ?? connection.updatedAt,
    );
  }

  Future<List<BtcpayWalletBehaviorViewModel>> _loadWalletBehaviors([
    BtcpayConnection? connection,
  ]) async {
    try {
      final btcpayConnection = connection ?? await _getConnection.execute();
      final behaviors = await _getWalletBehaviors.execute(
        connection: btcpayConnection,
      );
      return behaviors.map((behavior) {
        return BtcpayWalletBehaviorViewModel(
          walletId: behavior.wallet.id,
          wallet: switch (behavior.network) {
            BtcpayWalletNetwork.bitcoin => BtcpayPairingWallet.bitcoin,
            BtcpayWalletNetwork.liquid => BtcpayPairingWallet.liquid,
          },
          hideOnHome: behavior.wallet.hideOnHome,
          autoSweepEnabled: behavior.wallet.autoSweepEnabled,
        );
      }).toList();
    } catch (e, stack) {
      log.warning(
        'Failed to load BTCPay wallet behavior settings',
        error: e,
        trace: stack,
      );
      return const [];
    }
  }
}
