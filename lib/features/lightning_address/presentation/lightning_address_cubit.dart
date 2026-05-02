import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/lightning_address/domain/entities/lookup_result.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_errors.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/delete_lightning_address_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/get_lightning_address_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/lookup_lightning_address_status_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/register_lightning_address_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/republish_nostr_profile_usecase.dart';
import 'package:bb_mobile/features/lightning_address/presentation/lightning_address_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

const _kNostrPublishWarning =
    'Saved on bullpay, but couldn’t reach Nostr relays. '
    'Tap “Republish to Nostr” to retry.';

class LightningAddressCubit extends Cubit<LightningAddressState> {
  final GetLightningAddressWalletUsecase _getWallet;
  final RegisterLightningAddressUsecase _register;
  final DeleteLightningAddressUsecase _delete;
  final LookupLightningAddressStatusUsecase _lookupStatus;
  final RepublishNostrProfileUsecase _republishNostrProfile;
  final PayServicePort _payService;

  LightningAddressCubit({
    required GetLightningAddressWalletUsecase getWallet,
    required RegisterLightningAddressUsecase register,
    required DeleteLightningAddressUsecase delete,
    required LookupLightningAddressStatusUsecase lookupStatus,
    required RepublishNostrProfileUsecase republishNostrProfile,
    required PayServicePort payService,
  })  : _getWallet = getWallet,
        _register = register,
        _delete = delete,
        _lookupStatus = lookupStatus,
        _republishNostrProfile = republishNostrProfile,
        _payService = payService,
        super(const LightningAddressState());

  Future<void> checkStatus(Environment environment) async {
    try {
      final wallet = await _getWallet.execute(environment: environment);
      final storedAddress = await _payService.getStoredAddress();

      if (storedAddress != null) {
        if (isClosed) return;
        emit(state.copyWith(
          loading: false,
          walletExists: wallet != null,
          lightningAddress: storedAddress,
        ));
        await _refreshQuota();
        return;
      }

      LookupResult? lookup;
      try {
        lookup = await _lookupStatus.execute();
      } on PayServiceException catch (e, stack) {
        log.warning('LA server lookup failed', error: e, trace: stack);
      }

      if (isClosed) return;
      switch (lookup) {
        case ActiveLookupResult(:final nym, :final quota):
          final address = '$nym@$lightningAddressDomain';
          await _payService.storeAddress(address);
          if (isClosed) return;
          emit(state.copyWith(
            loading: false,
            walletExists: wallet != null,
            lightningAddress: address,
            quota: quota,
            quotaStale: false,
          ));
        case InactiveLookupResult(:final nym, :final quota):
          emit(state.copyWith(
            loading: false,
            walletExists: wallet != null,
            previousNym: nym,
            quota: quota,
            quotaStale: false,
          ));
        case null:
          emit(state.copyWith(
            loading: false,
            walletExists: wallet != null,
          ));
      }
    } on Exception catch (e) {
      if (isClosed) return;
      emit(state.copyWith(loading: false, error: _mapError(e)));
    }
  }

  Future<void> registerNym(
    String nym,
    Environment environment, {
    bool publishOnNostr = true,
  }) async {
    if (nym.isEmpty || state.registering) return;
    emit(state.copyWith(
      registering: true,
      error: null,
      nostrPublishWarning: null,
    ));

    try {
      final result = await _register.execute(
        nym: nym,
        environment: environment,
        publishOnNostr: publishOnNostr,
      );
      if (isClosed) return;
      emit(state.copyWith(
        registering: false,
        lightningAddress: result.address,
        previousNym: null,
        quota: result.quota,
        quotaStale: false,
      ));
    } on LightningAddressNostrPublishFailedException catch (e, stack) {
      // Server-side register succeeded; only the relay broadcast failed.
      // Emit the registered state but flag the warning so the UI can prompt
      // a manual retry via "Republish to Nostr".
      log.warning('LA register: nostr publish failed',
          error: e, trace: stack);
      if (isClosed) return;
      final address = '$nym@$lightningAddressDomain';
      emit(state.copyWith(
        registering: false,
        lightningAddress: address,
        previousNym: null,
        quotaStale: false,
        nostrPublishWarning: _kNostrPublishWarning,
      ));
    } on Exception catch (e, stack) {
      log.severe(message: 'register failed', error: e, trace: stack);
      if (isClosed) return;
      emit(state.copyWith(registering: false, error: _mapError(e)));
    }
  }

  Future<void> deleteAddress() async {
    if (state.registering) return;
    final currentAddress = state.lightningAddress;
    emit(state.copyWith(
      registering: true,
      error: null,
      nostrPublishWarning: null,
    ));
    try {
      final quota = await _delete.execute();
      if (isClosed) return;
      final nym = currentAddress?.split('@').firstOrNull;
      emit(LightningAddressState(
        loading: false,
        walletExists: state.walletExists,
        previousNym: nym,
        quota: quota,
        quotaStale: false,
      ));
    } on LightningAddressNostrPublishFailedException catch (e, stack) {
      // Server-side deactivation succeeded; only the relay clear failed.
      // The post-delete quota the usecase would have returned was lost when
      // the exception was thrown — fall back to the stale pre-delete quota
      // and best-effort refresh from the server.
      log.warning('LA delete: nostr publish failed',
          error: e, trace: stack);
      if (isClosed) return;
      final nym = currentAddress?.split('@').firstOrNull;
      emit(LightningAddressState(
        loading: false,
        walletExists: state.walletExists,
        previousNym: nym,
        quota: state.quota,
        quotaStale: true,
        nostrPublishWarning: _kNostrPublishWarning,
      ));
      await _refreshQuota();
    } on Exception catch (e) {
      if (isClosed) return;
      emit(state.copyWith(registering: false, error: _mapError(e)));
    }
  }

  /// Manual retry: re-asserts the canonical bullpay state on Nostr relays.
  /// Idempotent — looks up the npub on the server and either re-publishes
  /// the active profile or clears it.
  Future<void> republishNostrProfile() async {
    if (state.republishingNostr) return;
    emit(state.copyWith(
      republishingNostr: true,
      nostrPublishWarning: null,
    ));
    try {
      await _republishNostrProfile.execute();
      if (isClosed) return;
      emit(state.copyWith(republishingNostr: false));
    } on LightningAddressNostrPublishFailedException catch (e, stack) {
      log.warning('LA republish failed', error: e, trace: stack);
      if (isClosed) return;
      emit(state.copyWith(
        republishingNostr: false,
        nostrPublishWarning: _kNostrPublishWarning,
      ));
    } on Exception catch (e, stack) {
      log.severe(message: 'LA republish unexpected error',
          error: e, trace: stack);
      if (isClosed) return;
      emit(state.copyWith(
        republishingNostr: false,
        nostrPublishWarning: _kNostrPublishWarning,
      ));
    }
  }

  Future<void> _refreshQuota() async {
    try {
      final lookup = await _lookupStatus.execute();
      if (isClosed) return;
      switch (lookup) {
        case ActiveLookupResult(:final quota) ||
              InactiveLookupResult(:final quota):
          emit(state.copyWith(quota: quota, quotaStale: false));
        case null:
          break;
      }
    } on Exception catch (e, stack) {
      if (isClosed) return;
      log.warning('LA quota refresh failed', error: e, trace: stack);
      emit(state.copyWith(quotaStale: true));
    }
  }

  String _mapError(Exception e) {
    if (e is LightningAddressRegistrationException) return e.message;
    if (e is LightningAddressWalletAlreadyExistsException) {
      return 'Wallet already exists';
    }
    if (e is LightningAddressNoDefaultWalletException) {
      return 'No wallet available';
    }
    if (e is LightningAddressSweepException) return e.message;
    return e.toString();
  }
}
