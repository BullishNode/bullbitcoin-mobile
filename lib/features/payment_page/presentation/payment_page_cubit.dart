// ignore_for_file: prefer_initializing_formals

import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/payment_page/domain/display_currency.dart';
import 'package:bb_mobile/features/payment_page/domain/payment_page.dart';
import 'package:bb_mobile/features/payment_page/domain/payment_page_error.dart';
import 'package:bb_mobile/features/payment_page/domain/payment_page_validation.dart';
import 'package:bb_mobile/features/payment_page/domain/usecases/get_payment_page_wallet_behavior_usecase.dart';
import 'package:bb_mobile/features/payment_page/domain/usecases/update_payment_page_wallet_behavior_usecase.dart';
import 'package:bb_mobile/features/payment_page/domain/usecases/claim_payment_page_nym_usecase.dart';
import 'package:bb_mobile/features/payment_page/domain/usecases/get_payment_page_permanent_name_usecase.dart';
import 'package:bb_mobile/features/payment_page/presentation/payment_page_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

typedef FindPaymentPage = Future<PaymentPage?> Function({required String nym});
typedef SavePaymentPage =
    Future<PaymentPage> Function(SavePaymentPageCommand command);
typedef ArchivePaymentPage = Future<PaymentPage?> Function();
typedef GetPaymentPageCurrencies = Future<List<DisplayCurrency>> Function();

/// Drives the Donation Page editor through its feature-owned use cases. An
/// [_operationId] guard makes double-taps and stale async completions inert.
class PaymentPageCubit extends Cubit<PaymentPageState> {
  final FindPaymentPage _find;
  final SavePaymentPage _save;
  final ArchivePaymentPage _archive;
  final GetPaymentPageCurrencies _supportedCurrencies;
  final GetPaymentPagePermanentNameUsecase _getPermanentName;
  final ClaimPaymentPageNymUsecase _claimNym;
  final GetPaymentPageWalletBehaviorUsecase _getWalletBehavior;
  final UpdatePaymentPageWalletBehaviorUsecase _updateWalletBehavior;
  int _operationId = 0;

  PaymentPageCubit({
    required FindPaymentPage find,
    required SavePaymentPage save,
    required ArchivePaymentPage archive,
    required GetPaymentPageCurrencies supportedCurrencies,
    required this._getPermanentName,
    required this._claimNym,
    required this._getWalletBehavior,
    required this._updateWalletBehavior,
  }) : _find = find,
       _save = save,
       _archive = archive,
       _supportedCurrencies = supportedCurrencies,
       super(const PaymentPageState());

  Future<void> load() async {
    if (state.submitting) return;
    final op = ++_operationId;
    emit(
      state.copyWith(
        status: PaymentPageStatus.loading,
        clearFailure: true,
        submissionUncertain: false,
      ),
    );

    // Resolve the reserved wallet locally FIRST (label-match, no server) so the
    // behavior controls stay reachable even when the server load below fails.
    final walletBehaviorRead = await _resolveWalletBehavior();
    final walletBehavior = _behaviorFrom(walletBehaviorRead);
    final walletBehaviorUnavailable =
        walletBehaviorRead is PaymentPageWalletBehaviorUnavailable;
    if (_isStale(op)) return;

    final PaymentPagePermanentName permanentName;
    try {
      permanentName = await _getPermanentName.execute();
    } on Exception catch (e, stack) {
      log.warning(
        'Donation Page permanent-name probe failed',
        error: e,
        trace: stack,
      );
      if (_isStale(op)) return;
      emit(
        state.copyWith(
          status: PaymentPageStatus.loadFailed,
          failure: _asPaymentPageException(e),
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
          status: PaymentPageStatus.unsupported,
          nym: '',
          aliasDraft: '',
          clearPage: true,
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
          status: PaymentPageStatus.needsNym,
          nym: '',
          aliasDraft: '',
          claimingNym: false,
          clearPage: true,
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

    // Currencies degrade to the fallback rather than blocking the editor.
    var currencies = const <DisplayCurrency>[];
    var currenciesUnavailable = false;
    try {
      currencies = await _supportedCurrencies();
    } on Exception catch (e, stack) {
      log.warning(
        'Donation Page currency fetch failed',
        error: e,
        trace: stack,
      );
      currenciesUnavailable = true;
    }
    if (_isStale(op)) return;

    final PaymentPage? page;
    try {
      page = await _find(nym: nym);
    } on Exception catch (e, stack) {
      log.warning('Donation Page probe failed', error: e, trace: stack);
      if (_isStale(op)) return;
      emit(
        state.copyWith(
          status: PaymentPageStatus.loadFailed,
          nym: nym,
          failure: _asPaymentPageException(e),
          walletBehavior: walletBehavior,
          clearWalletBehavior: walletBehavior == null,
          walletBehaviorUnavailable: walletBehaviorUnavailable,
        ),
      );
      return;
    }
    if (_isStale(op)) return;

    if (page != null && (page.nym != nym || page.alias != permanentAlias)) {
      emit(
        state.copyWith(
          status: PaymentPageStatus.loadFailed,
          nym: nym,
          failure: const PaymentPageException.invalidServerResponse(),
          walletBehavior: walletBehavior,
          clearWalletBehavior: walletBehavior == null,
          walletBehaviorUnavailable: walletBehaviorUnavailable,
        ),
      );
      return;
    }

    if (page == null) {
      emit(
        state.copyWith(
          status: PaymentPageStatus.create,
          nym: nym,
          permanentAlias: permanentAlias,
          clearPermanentAlias: permanentAlias == null,
          aliasDraft: '',
          currencies: currencies,
          currenciesUnavailable: currenciesUnavailable,
          displayCurrency: _defaultCurrency(currencies),
          header: '',
          description: '',
          website: '',
          twitter: '',
          instagram: '',
          clearPage: true,
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
        status: page.isArchived
            ? PaymentPageStatus.archived
            : PaymentPageStatus.edit,
        nym: nym,
        page: page,
        permanentAlias: permanentAlias,
        clearPermanentAlias: permanentAlias == null,
        aliasDraft: '',
        currencies: currencies,
        currenciesUnavailable: currenciesUnavailable,
        header: page.header,
        description: page.description,
        displayCurrency: page.displayCurrency,
        website: page.website ?? '',
        twitter: page.twitter ?? '',
        instagram: page.instagram ?? '',
        clearFailure: true,
        walletBehavior: walletBehavior,
        clearWalletBehavior: walletBehavior == null,
        walletBehaviorUnavailable: walletBehaviorUnavailable,
      ),
    );
  }

  Future<void> retryCurrencies() async {
    try {
      final currencies = await _supportedCurrencies();
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
    } on Exception catch (e, stack) {
      log.warning(
        'Donation Page currency retry failed',
        error: e,
        trace: stack,
      );
    }
  }

  void nymDraftChanged(String value) {
    if (state.claimingNym) return;
    emit(
      state.copyWith(
        nymDraft: normalizePaymentPageNym(value),
        clearFailure: true,
        clearInvalidField: state.invalidField == PaymentPageField.nym,
      ),
    );
  }

  /// Claims the wallet's one lifetime nym from inside this flow, then reloads —
  /// which finds the nym and lands on the create form, so the user continues
  /// into the Donation Page without leaving for Lightning Address settings.
  Future<void> claimNym() async {
    if (state.claimingNym || state.status != PaymentPageStatus.needsNym) return;
    final String nym;
    try {
      nym = validatePaymentPageNymClaim(state.nymDraft);
    } on PaymentPageException catch (e) {
      emit(
        state.copyWith(
          nymDraft: normalizePaymentPageNym(state.nymDraft),
          failure: e,
          invalidField: PaymentPageField.nym,
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
    } on Exception catch (e, stack) {
      log.warning('Donation Page nym claim failed', error: e, trace: stack);
      if (_isStale(op)) return;
      final failure = _asPaymentPageException(e);
      emit(
        state.copyWith(
          claimingNym: false,
          failure: failure,
          invalidField: PaymentPageField.nym,
        ),
      );
    }
  }

  void aliasDraftChanged(String value) => emit(
    state.copyWith(
      aliasDraft: normalizePaymentPageAlias(value),
      clearFailure: true,
      clearInvalidField: state.invalidField == PaymentPageField.alias,
    ),
  );

  void headerChanged(String value) => emit(
    state.copyWith(
      header: value,
      clearFailure: true,
      clearInvalidField: state.invalidField == PaymentPageField.header,
    ),
  );

  void descriptionChanged(String value) => emit(
    state.copyWith(
      description: value,
      clearFailure: true,
      clearInvalidField: state.invalidField == PaymentPageField.description,
    ),
  );

  void displayCurrencyChanged(String value) => emit(
    state.copyWith(
      displayCurrency: value,
      clearFailure: true,
      clearInvalidField: state.invalidField == PaymentPageField.displayCurrency,
    ),
  );

  void websiteChanged(String value) => emit(
    state.copyWith(
      website: value,
      clearFailure: true,
      clearInvalidField: state.invalidField == PaymentPageField.website,
    ),
  );

  void twitterChanged(String value) => emit(
    state.copyWith(
      twitter: value,
      clearFailure: true,
      clearInvalidField: state.invalidField == PaymentPageField.twitter,
    ),
  );

  void instagramChanged(String value) => emit(
    state.copyWith(
      instagram: value,
      clearFailure: true,
      clearInvalidField: state.invalidField == PaymentPageField.instagram,
    ),
  );

  Future<void> save() async {
    if (state.submitting ||
        (state.status != PaymentPageStatus.create &&
            state.status != PaymentPageStatus.edit &&
            state.status != PaymentPageStatus.archived)) {
      return;
    }

    // Normalize the website + social handles at submit time and reflect the
    // result back into form state (the user sees `aa.com` become
    // `https://aa.com`, and `@name` become `name`) BEFORE validating.
    final normalizedWebsite = normalizePaymentPageUrl(state.website);
    final normalizedTwitter = stripHandleAt(state.twitter);
    final normalizedInstagram = stripHandleAt(state.instagram);
    if (normalizedWebsite != state.website ||
        normalizedTwitter != state.twitter ||
        normalizedInstagram != state.instagram) {
      emit(
        state.copyWith(
          website: normalizedWebsite,
          twitter: normalizedTwitter,
          instagram: normalizedInstagram,
        ),
      );
    }

    final command = state.command;
    final expectedAlias = state.permanentAlias ?? command.normalizedAliasClaim;
    final invalidField = command.firstInvalidField();
    if (invalidField != null) {
      emit(
        state.copyWith(
          failure: PaymentPageException.invalidInput(code: invalidField.name),
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
      final page = await _save(command);
      if (isClosed || _isStale(op)) return;
      if (page.nym != state.nym || page.alias != expectedAlias) {
        throw PaymentPageSaveException.submission(
          cause: const PaymentPageException.invalidServerResponse(),
        );
      }
      // Saving provisions wallet 102, so refresh its resolved behavior.
      final walletBehaviorRead = await _resolveWalletBehavior();
      final walletBehavior = _behaviorFrom(walletBehaviorRead);
      if (isClosed || _isStale(op)) return;
      emit(
        state.copyWith(
          submitting: false,
          status: page.isArchived
              ? PaymentPageStatus.archived
              : PaymentPageStatus.edit,
          page: page,
          permanentAlias: page.alias,
          clearPermanentAlias: page.alias == null,
          aliasDraft: '',
          header: page.header,
          description: page.description,
          displayCurrency: page.displayCurrency,
          website: page.website ?? '',
          twitter: page.twitter ?? '',
          instagram: page.instagram ?? '',
          clearFailure: true,
          walletBehavior: walletBehavior,
          clearWalletBehavior: walletBehavior == null,
          walletBehaviorUnavailable:
              walletBehaviorRead is PaymentPageWalletBehaviorUnavailable,
        ),
      );
    } on PaymentPageSaveException catch (e) {
      if (isClosed || _isStale(op)) return;
      final ownedAlias = e.ownedAlias;
      emit(
        state.copyWith(
          submitting: false,
          failure: e,
          submissionUncertain: e.submissionMayBeUncertain,
          permanentAlias: ownedAlias,
          aliasDraft: ownedAlias == null ? state.aliasDraft : '',
          invalidField: e.kind == PaymentPageErrorKind.aliasTaken
              ? PaymentPageField.alias
              : null,
          clearInvalidField: e.kind != PaymentPageErrorKind.aliasTaken,
        ),
      );
    } on Exception catch (e, stack) {
      log.warning('Donation Page save failed', error: e, trace: stack);
      if (isClosed || _isStale(op)) return;
      emit(
        state.copyWith(submitting: false, failure: _asPaymentPageException(e)),
      );
    }
  }

  Future<void> archive() async {
    if (state.submitting || state.status != PaymentPageStatus.edit) return;
    final op = ++_operationId;
    emit(state.copyWith(submitting: true, clearFailure: true));
    try {
      await _archive();
      if (isClosed || _isStale(op)) return;
      emit(state.copyWith(submitting: false));
      await load();
    } on Exception catch (e, stack) {
      log.warning('Donation Page archive failed', error: e, trace: stack);
      if (isClosed || _isStale(op)) return;
      emit(
        state.copyWith(submitting: false, failure: _asPaymentPageException(e)),
      );
    }
  }

  /// Changes only Payment Page availability. The signed writes remain pinned
  /// to `kind=payment_page`; Lightning Address and POS are never touched.
  Future<void> setOnline(bool online) async {
    if (online) {
      if (state.status == PaymentPageStatus.archived) await save();
      return;
    }
    if (state.status == PaymentPageStatus.edit) await archive();
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
        walletBehaviorUnavailable:
            refreshed is PaymentPageWalletBehaviorUnavailable,
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
        walletBehaviorUnavailable:
            refreshed is PaymentPageWalletBehaviorUnavailable,
        walletBehaviorSaving: false,
      ),
    );
  }

  Future<PaymentPageWalletBehaviorRead> _resolveWalletBehavior() =>
      _getWalletBehavior.execute();

  GetPaidWalletBehavior? _behaviorFrom(PaymentPageWalletBehaviorRead read) =>
      switch (read) {
        PaymentPageWalletBehaviorFound(:final behavior) => behavior,
        PaymentPageWalletBehaviorAbsent() ||
        PaymentPageWalletBehaviorUnavailable() => null,
      };

  bool _isStale(int op) => isClosed || op != _operationId;

  String _defaultCurrency(List<DisplayCurrency> currencies) {
    if (currencies.any((c) => c.code == paymentPageFallbackCurrency)) {
      return paymentPageFallbackCurrency;
    }
    if (currencies.isNotEmpty) return currencies.first.code;
    return paymentPageFallbackCurrency;
  }

  PaymentPageException _asPaymentPageException(Object error) {
    if (error is PaymentPageException) return error;
    return const PaymentPageException.unexpected();
  }
}
