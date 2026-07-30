import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/pos/domain/usecases/get_pos_wallet_behavior_usecase.dart';
import 'package:bb_mobile/features/pos/domain/usecases/update_pos_wallet_behavior_usecase.dart';
import 'package:bb_mobile/features/pos/domain/usecases/claim_pos_nym_usecase.dart';
import 'package:bb_mobile/features/pos/domain/usecases/get_pos_permanent_name_usecase.dart';
import 'package:bb_mobile/features/pos/presentation/pos_state.dart';
import 'package:bb_mobile/features/pos/public/pos_facade.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Drives the Point of Sale provisioning screen through the [PosFacade] and
/// the feature-owned permanent-name read usecase. An [_operationId] guard makes
/// double-taps and stale async completions inert. Holds no secrets or
/// descriptor.
class PosCubit extends Cubit<PosState> {
  final PosFacade _facade;
  final GetPosPermanentNameUsecase _getPermanentName;
  final ClaimPosNymUsecase _claimNym;
  final GetPosWalletBehaviorUsecase _getWalletBehavior;
  final UpdatePosWalletBehaviorUsecase _updateWalletBehavior;
  int _operationId = 0;

  PosCubit({
    required this._facade,
    required this._getPermanentName,
    required this._claimNym,
    required this._getWalletBehavior,
    required this._updateWalletBehavior,
  }) : super(const PosState());

  Future<void> load() async {
    if (state.submitting) return;
    final op = ++_operationId;
    emit(
      state.copyWith(
        status: PosStatus.loading,
        clearFailure: true,
        submissionUncertain: false,
      ),
    );

    // Resolve the reserved wallet locally FIRST (label-match, no server) so the
    // behavior controls stay reachable even when the server load below fails.
    final walletBehaviorRead = await _resolveWalletBehavior();
    final walletBehavior = _behaviorFrom(walletBehaviorRead);
    final walletBehaviorUnavailable =
        walletBehaviorRead is PosWalletBehaviorUnavailable;
    if (_isStale(op)) return;

    final PosPermanentName permanentName;
    try {
      permanentName = await _getPermanentName.execute();
    } catch (e, stack) {
      log.warning(
        'Point of Sale permanent-name probe failed',
        error: e,
        trace: stack,
      );
      if (_isStale(op)) return;
      emit(
        state.copyWith(
          status: PosStatus.loadFailed,
          failure: _asPosException(e),
          walletBehavior: walletBehavior,
          clearWalletBehavior: walletBehavior == null,
          walletBehaviorUnavailable: walletBehaviorUnavailable,
        ),
      );
      return;
    }
    if (_isStale(op)) return;

    if (!permanentName.supported) {
      emit(
        state.copyWith(
          status: PosStatus.unsupported,
          nym: '',
          aliasDraft: '',
          clearTerminal: true,
          clearPermanentAlias: true,
          clearFailure: true,
          walletBehavior: walletBehavior,
          clearWalletBehavior: walletBehavior == null,
          walletBehaviorUnavailable: walletBehaviorUnavailable,
        ),
      );
      return;
    }

    final nym = permanentName.nym;
    if (nym == null) {
      emit(
        state.copyWith(
          status: PosStatus.needsNym,
          nym: '',
          aliasDraft: '',
          claimingNym: false,
          clearTerminal: true,
          clearPermanentAlias: true,
          clearFailure: true,
          walletBehavior: walletBehavior,
          clearWalletBehavior: walletBehavior == null,
          walletBehaviorUnavailable: walletBehaviorUnavailable,
        ),
      );
      return;
    }
    final permanentAlias = permanentName.alias;

    // Currencies degrade to the fallback rather than blocking the screen.
    var currencies = const <DisplayCurrency>[];
    var currenciesUnavailable = false;
    try {
      currencies = await _facade.supportedCurrencies();
    } catch (e, stack) {
      log.warning(
        'Point of Sale currency fetch failed',
        error: e,
        trace: stack,
      );
      currenciesUnavailable = true;
    }
    if (_isStale(op)) return;

    final PosTerminal? terminal;
    try {
      terminal = await _facade.find(nym: nym);
    } catch (e, stack) {
      log.warning('Point of Sale probe failed', error: e, trace: stack);
      if (_isStale(op)) return;
      emit(
        state.copyWith(
          status: PosStatus.loadFailed,
          nym: nym,
          failure: _asPosException(e),
          walletBehavior: walletBehavior,
          clearWalletBehavior: walletBehavior == null,
          walletBehaviorUnavailable: walletBehaviorUnavailable,
        ),
      );
      return;
    }
    if (_isStale(op)) return;

    if (terminal != null &&
        (terminal.nym != nym || terminal.alias != permanentAlias)) {
      emit(
        state.copyWith(
          status: PosStatus.loadFailed,
          nym: nym,
          failure: const PosException.invalidServerResponse(),
          walletBehavior: walletBehavior,
          clearWalletBehavior: walletBehavior == null,
          walletBehaviorUnavailable: walletBehaviorUnavailable,
        ),
      );
      return;
    }

    if (terminal == null) {
      emit(
        state.copyWith(
          status: PosStatus.create,
          nym: nym,
          permanentAlias: permanentAlias,
          clearPermanentAlias: permanentAlias == null,
          aliasDraft: '',
          currencies: currencies,
          currenciesUnavailable: currenciesUnavailable,
          displayCurrency: _defaultCurrency(currencies),
          label: '',
          clearTerminal: true,
          clearFailure: true,
          walletBehavior: walletBehavior,
          clearWalletBehavior: walletBehavior == null,
          walletBehaviorUnavailable: walletBehaviorUnavailable,
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        status: terminal.isArchived ? PosStatus.archived : PosStatus.edit,
        nym: nym,
        terminal: terminal,
        permanentAlias: permanentAlias,
        clearPermanentAlias: permanentAlias == null,
        aliasDraft: '',
        currencies: currencies,
        currenciesUnavailable: currenciesUnavailable,
        label: terminal.label,
        displayCurrency: terminal.displayCurrency,
        clearFailure: true,
        walletBehavior: walletBehavior,
        clearWalletBehavior: walletBehavior == null,
        walletBehaviorUnavailable: walletBehaviorUnavailable,
      ),
    );
  }

  Future<void> retryCurrencies() async {
    try {
      final currencies = await _facade.supportedCurrencies();
      if (isClosed) return;
      emit(
        state.copyWith(
          currencies: currencies,
          currenciesUnavailable: false,
          displayCurrency: state.displayCurrency.isEmpty
              ? _defaultCurrency(currencies)
              : state.displayCurrency,
        ),
      );
    } catch (e, stack) {
      log.warning(
        'Point of Sale currency retry failed',
        error: e,
        trace: stack,
      );
    }
  }

  void nymDraftChanged(String value) {
    if (state.claimingNym) return;
    emit(
      state.copyWith(
        nymDraft: normalizePosNym(value),
        clearFailure: true,
        clearInvalidField: state.invalidField == PosField.nym,
      ),
    );
  }

  /// Claims the wallet's one lifetime nym from inside this flow, then reloads -
  /// which finds the nym and lands on the create form, so the user continues
  /// into the Point of Sale without leaving for Lightning Address settings.
  Future<void> claimNym() async {
    if (state.claimingNym || state.status != PosStatus.needsNym) return;
    final String nym;
    try {
      nym = validatePosNymClaim(state.nymDraft);
    } on PosException catch (e) {
      emit(
        state.copyWith(
          nymDraft: normalizePosNym(state.nymDraft),
          failure: e,
          invalidField: PosField.nym,
        ),
      );
      return;
    }

    final op = ++_operationId;
    emit(
      state.copyWith(
        claimingNym: true,
        nymDraft: nym,
        clearFailure: true,
        clearInvalidField: true,
      ),
    );
    try {
      await _claimNym.execute(nym: nym);
      if (_isStale(op)) return;
      emit(state.copyWith(claimingNym: false, nymDraft: ''));
      await load();
    } catch (e, stack) {
      log.warning('Point of Sale nym claim failed', error: e, trace: stack);
      if (_isStale(op)) return;
      emit(
        state.copyWith(
          claimingNym: false,
          failure: _asPosException(e),
          invalidField: PosField.nym,
        ),
      );
    }
  }

  void aliasDraftChanged(String value) => emit(
    state.copyWith(
      aliasDraft: normalizePosAlias(value),
      clearFailure: true,
      clearInvalidField: state.invalidField == PosField.alias,
    ),
  );

  void labelChanged(String value) => emit(
    state.copyWith(
      label: value,
      clearFailure: true,
      clearInvalidField: state.invalidField == PosField.label,
    ),
  );

  void displayCurrencyChanged(String value) => emit(
    state.copyWith(
      displayCurrency: value,
      clearFailure: true,
      clearInvalidField: state.invalidField == PosField.displayCurrency,
    ),
  );

  Future<void> provision() async {
    if (state.submitting ||
        (state.status != PosStatus.create &&
            state.status != PosStatus.edit &&
            state.status != PosStatus.archived)) {
      return;
    }
    final command = state.command;
    final expectedAlias = state.permanentAlias ?? command.normalizedAliasClaim;
    final invalidField = command.firstInvalidField();
    if (invalidField != null) {
      emit(
        state.copyWith(
          failure: PosException.invalidInput(code: invalidField.name),
          invalidField: invalidField,
        ),
      );
      return;
    }

    final op = ++_operationId;
    emit(
      state.copyWith(
        submitting: true,
        clearFailure: true,
        clearInvalidField: true,
        submissionUncertain: false,
      ),
    );
    try {
      final terminal = await _facade.provision(command);
      if (isClosed || _isStale(op)) return;
      if (terminal.nym != state.nym || terminal.alias != expectedAlias) {
        throw PosProvisionException.submission(
          cause: const PosException.invalidServerResponse(),
        );
      }
      // Provisioning creates wallet 103, so refresh its resolved behavior.
      final walletBehaviorRead = await _resolveWalletBehavior();
      final walletBehavior = _behaviorFrom(walletBehaviorRead);
      if (isClosed || _isStale(op)) return;
      emit(
        state.copyWith(
          submitting: false,
          status: terminal.isArchived ? PosStatus.archived : PosStatus.edit,
          terminal: terminal,
          permanentAlias: terminal.alias,
          clearPermanentAlias: terminal.alias == null,
          aliasDraft: '',
          label: terminal.label,
          displayCurrency: terminal.displayCurrency,
          clearFailure: true,
          walletBehavior: walletBehavior,
          clearWalletBehavior: walletBehavior == null,
          walletBehaviorUnavailable:
              walletBehaviorRead is PosWalletBehaviorUnavailable,
        ),
      );
    } on PosProvisionException catch (e) {
      if (isClosed || _isStale(op)) return;
      final ownedAlias = e.ownedAlias;
      emit(
        state.copyWith(
          submitting: false,
          failure: e,
          submissionUncertain: e.submissionMayBeUncertain,
          permanentAlias: ownedAlias,
          aliasDraft: ownedAlias == null ? state.aliasDraft : '',
          invalidField: e.kind == PosErrorKind.aliasTaken
              ? PosField.alias
              : null,
          clearInvalidField: e.kind != PosErrorKind.aliasTaken,
        ),
      );
    } on Exception catch (e, stack) {
      log.warning('Point of Sale provision failed', error: e, trace: stack);
      if (isClosed || _isStale(op)) return;
      emit(state.copyWith(submitting: false, failure: _asPosException(e)));
    }
  }

  Future<void> archive() async {
    if (state.submitting || state.status != PosStatus.edit) return;
    final op = ++_operationId;
    emit(state.copyWith(submitting: true, clearFailure: true));
    try {
      await _facade.archive();
      if (isClosed || _isStale(op)) return;
      emit(state.copyWith(submitting: false));
      await load();
    } catch (e, stack) {
      log.warning('Point of Sale archive failed', error: e, trace: stack);
      if (isClosed || _isStale(op)) return;
      emit(state.copyWith(submitting: false, failure: _asPosException(e)));
    }
  }

  /// Changes only POS availability. Every write remains `kind=pos`; Lightning
  /// Address and Payment Page availability are independent.
  Future<void> setOnline(bool online) async {
    if (online) {
      if (state.status == PosStatus.archived) await provision();
      return;
    }
    if (state.status == PosStatus.edit) await archive();
  }

  /// Updates the reserved wallet's auto-sweep / hide-on-home behavior with the
  /// same optimistic-emit / revert-on-failure / saving-guard posture BTCPay
  /// uses (`BtcpayPairingCubit.updateWalletBehavior`).
  Future<void> updateWalletBehavior({
    required String walletId,
    bool? hideOnHome,
    bool? autoSweepEnabled,
  }) async {
    if (state.walletBehaviorSaving) return;
    final previous = state.walletBehavior;
    if (previous == null || previous.walletId != walletId) return;
    emit(
      state.copyWith(
        walletBehavior: previous.withRequestedChange(
          hideOnHome: hideOnHome,
          autoSweepEnabled: autoSweepEnabled,
        ),
        walletBehaviorSaving: true,
      ),
    );
    final saved = await _updateWalletBehavior.execute(
      walletId: walletId,
      hideOnHome: hideOnHome,
      autoSweepEnabled: autoSweepEnabled,
    );
    if (isClosed) return;
    if (!saved) {
      // The write did not land: restore what was optimistically shown.
      emit(
        state.copyWith(walletBehavior: previous, walletBehaviorSaving: false),
      );
      return;
    }
    final refreshed = await _resolveWalletBehavior();
    final refreshedBehavior = _behaviorFrom(refreshed);
    if (isClosed) return;
    emit(
      state.copyWith(
        walletBehavior: refreshedBehavior,
        clearWalletBehavior: refreshedBehavior == null,
        walletBehaviorSaving: false,
        walletBehaviorUnavailable: refreshed is PosWalletBehaviorUnavailable,
      ),
    );
  }

  /// Retries only the reserved-wallet settings read. Product form edits stay
  /// untouched, and the shared guard prevents overlapping reads or writes.
  Future<void> retryWalletBehavior() async {
    if (state.walletBehaviorSaving) return;
    emit(state.copyWith(walletBehaviorSaving: true));
    final refreshed = await _resolveWalletBehavior();
    if (isClosed) return;
    final behavior = _behaviorFrom(refreshed);
    emit(
      state.copyWith(
        walletBehavior: behavior,
        clearWalletBehavior: behavior == null,
        walletBehaviorUnavailable: refreshed is PosWalletBehaviorUnavailable,
        walletBehaviorSaving: false,
      ),
    );
  }

  Future<PosWalletBehaviorRead> _resolveWalletBehavior() =>
      _getWalletBehavior.execute();

  GetPaidWalletBehavior? _behaviorFrom(PosWalletBehaviorRead read) =>
      switch (read) {
        PosWalletBehaviorFound(:final behavior) => behavior,
        PosWalletBehaviorAbsent() || PosWalletBehaviorUnavailable() => null,
      };

  bool _isStale(int op) => isClosed || op != _operationId;

  String _defaultCurrency(List<DisplayCurrency> currencies) {
    if (currencies.any((c) => c.code == posFallbackCurrency)) {
      return posFallbackCurrency;
    }
    if (currencies.isNotEmpty) return currencies.first.code;
    return posFallbackCurrency;
  }

  PosException _asPosException(Object error) {
    if (error is PosException) return error;
    return const PosException.unexpected();
  }
}
