// ignore_for_file: prefer_initializing_formals

import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/entities/fiat_settlement.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/fiat_settlement_failure.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/scoped_settlement_key_port.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/fiat_settlement_configuration_events.dart';
import 'package:bb_mobile/features/fiat_settlement/presentation/fiat_settlement_editor_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

typedef GetFiatSettlementConfiguration =
    Future<Result<FiatSettlementConfigurationView, FiatSettlementFailure>>
    Function();
typedef GetFiatSettlementConnectionStatus =
    Future<FiatSettlementConnectionStatus> Function();
typedef SetFiatSettlement =
    Future<Result<FiatSettlementConfigurationView, FiatSettlementFailure>>
    Function({
      required FiatSettlementProduct product,
      required int fiatPercentage,
      required FiatCurrency currency,
    });
typedef DisableFiatSettlement =
    Future<Result<FiatSettlementConfigurationView, FiatSettlementFailure>>
    Function({required FiatSettlementProduct product});

/// Drives the shared fiat-settlement editor for one product. A draft is never
/// shown as active until the server confirms a save; a failed save/disable
/// preserves the previously saved configuration exactly.
///
/// There is NO local exchange-account precondition: a fiat change is an
/// npub-signed keyless save against Bullnym's stored sell-only credential.
/// A missing credential is discovered from the SERVER (credentialProblem
/// outcome), never assumed from local state — so a merchant whose npub is
/// already registered can change settings without any exchange login.
class FiatSettlementEditorCubit extends Cubit<FiatSettlementEditorState> {
  final GetFiatSettlementConfiguration _getConfiguration;
  final GetFiatSettlementConnectionStatus _getConnectionStatus;
  final SetFiatSettlement _set;
  final DisableFiatSettlement _disableSettlement;
  final FiatSettlementConfigurationEvents _events;

  int _operationId = 0;

  FiatSettlementEditorCubit({
    required GetFiatSettlementConfiguration getConfiguration,
    required GetFiatSettlementConnectionStatus getConnectionStatus,
    required SetFiatSettlement set,
    required DisableFiatSettlement disable,
    required FiatSettlementConfigurationEvents events,
    required FiatSettlementProduct product,
  }) : _getConfiguration = getConfiguration,
       _getConnectionStatus = getConnectionStatus,
       _set = set,
       _disableSettlement = disable,
       _events = events,
       super(FiatSettlementEditorState.initial(product));

  bool _isStale(int op) => op != _operationId || isClosed;

  Future<void> load() async {
    final op = ++_operationId;
    emit(state.copyWith(status: FiatSettlementEditorStatus.loading));
    final result = await _getConfiguration();
    if (_isStale(op)) return;
    switch (result) {
      case Ok(:final value):
        final config = value.configFor(state.product);
        emit(
          state.copyWith(
            status: FiatSettlementEditorStatus.ready,
            saved: config,
            mode: _modeFor(config),
            mixFiatPercentage: config.mode == FiatSettlementMode.mixed
                ? config.fiatPercentage
                : 50,
            currency: config.currency,
          ),
        );
      case Err():
        // A read failure leaves the editor unusable but never destructive.
        emit(state.copyWith(status: FiatSettlementEditorStatus.loadError));
    }
  }

  /// After the merchant returns from the exchange login (triggered only by a
  /// credentialProblem outcome — i.e. the server had no sell-only key for this
  /// npub), say what that round-trip actually achieved.
  ///
  /// With the credential now on the device, the failure clears and the Save
  /// button reappears with the draft intact; the merchant re-saves explicitly
  /// (owner Q15 — no auto-retry), and that save carries the freshly issued key
  /// on the server's credential-required retry. When the credential is still
  /// missing the merchant is NOT returned to a bare form as if nothing had
  /// happened: the reason is stated instead, distinguishing a login that was
  /// never completed from an account that issued no settlement permission.
  /// Never re-reads the server config (that would reset the draft).
  Future<void> refreshConnection() async {
    if (state.status != FiatSettlementEditorStatus.ready) return;
    final connection = await _getConnectionStatus();
    if (isClosed) return;
    switch (connection) {
      case FiatSettlementConnectionStatus.connected:
        emit(state.copyWith(clearFailure: true, clearConnectionProblem: true));
      case FiatSettlementConnectionStatus.missingSettlementPermission:
        emit(
          state.copyWith(
            clearFailure: true,
            connectionProblem:
                FiatSettlementConnectionProblem.missingSettlementPermission,
          ),
        );
      case FiatSettlementConnectionStatus.notLoggedIn:
        emit(
          state.copyWith(
            clearFailure: true,
            connectionProblem: FiatSettlementConnectionProblem.loginUnfinished,
          ),
        );
    }
  }

  void selectMode(FiatSettlementReceiveMode mode) {
    emit(state.copyWith(mode: mode, clearFailure: true, understood: false));
  }

  void setMixPercentage(int fiatPercentage) {
    final clamped = fiatPercentage.clamp(0, 100);
    emit(state.copyWith(mixFiatPercentage: clamped, clearFailure: true));
  }

  void selectCurrency(FiatCurrency currency) {
    // Changing currency re-arms the acceptance gate.
    emit(
      state.copyWith(currency: currency, understood: false, clearFailure: true),
    );
  }

  void setUnderstood(bool value) {
    emit(state.copyWith(understood: value, clearFailure: true));
  }

  Future<void> save() async {
    if (!state.canSave) return;
    // An effective 0% (Bitcoin mode, or the mix slider at 0% fiat) is a
    // disable, which needs no currency/acceptance.
    if (state.effectiveFiatPercentage == 0) {
      return _disable();
    }
    final currency = state.currency;
    if (currency == null) return;

    final op = ++_operationId;
    emit(
      state.copyWith(
        status: FiatSettlementEditorStatus.saving,
        clearFailure: true,
        clearConnectionProblem: true,
      ),
    );
    final result = await _set(
      product: state.product,
      fiatPercentage: state.effectiveFiatPercentage,
      currency: currency,
    );
    if (_isStale(op)) return;
    if (result is Ok) _events.notifyChanged();
    _applyResult(result);
  }

  /// Switch the product back to Bitcoin-only. Always available, even when the
  /// server rejected a prior activation.
  Future<void> disable() => _disable();

  Future<void> _disable() async {
    final op = ++_operationId;
    emit(
      state.copyWith(
        status: FiatSettlementEditorStatus.saving,
        // Preserve the attempted operation in the draft. If the disable
        // outcome is unknown, the generic Retry action must call disable
        // again—not save the previously active fiat configuration.
        mode: FiatSettlementReceiveMode.bitcoin,
        clearFailure: true,
      ),
    );
    final result = await _disableSettlement(product: state.product);
    if (_isStale(op)) return;
    if (result is Ok) _events.notifyChanged();
    _applyResult(result);
  }

  void _applyResult(
    Result<FiatSettlementConfigurationView, FiatSettlementFailure> result,
  ) {
    switch (result) {
      case Ok(:final value):
        final config = value.configFor(state.product);
        emit(
          state.copyWith(
            status: FiatSettlementEditorStatus.success,
            saved: config,
            mode: _modeFor(config),
            currency: config.currency,
          ),
        );
      case Err(:final failure):
        // Preserve the prior saved config; surface the failure for the outcome
        // UI. The draft selections stay so the merchant can retry.
        emit(
          state.copyWith(
            status: FiatSettlementEditorStatus.ready,
            failure: failure,
          ),
        );
    }
  }

  FiatSettlementReceiveMode _modeFor(FiatSettlementProductConfig config) {
    return switch (config.mode) {
      FiatSettlementMode.bitcoinOnly => FiatSettlementReceiveMode.bitcoin,
      FiatSettlementMode.fiatOnly => FiatSettlementReceiveMode.fiat,
      FiatSettlementMode.mixed => FiatSettlementReceiveMode.mix,
    };
  }
}
