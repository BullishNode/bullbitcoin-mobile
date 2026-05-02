import 'dart:async';

import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/lightning_address/data/datasources/lightning_address_settings_datasource.dart';
import 'package:bb_mobile/features/lightning_address/domain/entities/lookup_result.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_errors.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/primitives/nostr_publish_status.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/clear_lightning_address_nostr_profile_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/delete_lightning_address_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/get_lightning_address_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/lookup_lightning_address_status_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/publish_lightning_address_nostr_profile_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/register_lightning_address_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/value_objects/nym_quota.dart';
import 'package:bb_mobile/features/lightning_address/presentation/lightning_address_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class LightningAddressCubit extends Cubit<LightningAddressState> {
  final GetLightningAddressWalletUsecase _getWallet;
  final RegisterLightningAddressUsecase _register;
  final DeleteLightningAddressUsecase _delete;
  final LookupLightningAddressStatusUsecase _lookupStatus;
  final PublishLightningAddressNostrProfileUsecase _publishProfile;
  final ClearLightningAddressNostrProfileUsecase _clearProfile;
  final PayServicePort _payService;
  final LightningAddressSettingsDatasource _settings;

  LightningAddressCubit({
    required GetLightningAddressWalletUsecase getWallet,
    required RegisterLightningAddressUsecase register,
    required DeleteLightningAddressUsecase delete,
    required LookupLightningAddressStatusUsecase lookupStatus,
    required PublishLightningAddressNostrProfileUsecase publishProfile,
    required ClearLightningAddressNostrProfileUsecase clearProfile,
    required PayServicePort payService,
    required LightningAddressSettingsDatasource settings,
  })  : _getWallet = getWallet,
        _register = register,
        _delete = delete,
        _lookupStatus = lookupStatus,
        _publishProfile = publishProfile,
        _clearProfile = clearProfile,
        _payService = payService,
        _settings = settings,
        super(const LightningAddressState());

  Future<void> checkStatus(Environment environment) async {
    try {
      final wallet = await _getWallet.execute(environment: environment);
      final storedAddress = await _payService.getStoredAddress();

      if (storedAddress != null) {
        if (isClosed) return;
        await _emitActivated(
          address: storedAddress,
          walletExists: wallet != null,
        );
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
          await _emitActivated(
            address: address,
            walletExists: wallet != null,
            quota: quota,
          );
        case InactiveLookupResult(:final nym, :final quota):
          emit(state.copyWith(
            loading: false,
            walletExists: wallet != null,
            previousNym: nym,
            quota: quota,
            quotaStale: false,
            nostrPublishStatus: NostrPublishStatus.none,
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
    emit(state.copyWith(registering: true, error: null));

    try {
      final result = await _register.execute(
        nym: nym,
        environment: environment,
      );
      if (isClosed) return;
      emit(state.copyWith(
        registering: false,
        lightningAddress: result.address,
        previousNym: null,
        quota: result.quota,
        quotaStale: false,
        nostrPublishStatus: publishOnNostr
            ? NostrPublishStatus.pending
            : NostrPublishStatus.none,
      ));
      if (publishOnNostr) {
        unawaited(_publishNostrInBackground(nym));
      } else {
        unawaited(_settings.clearNostrPublishOutcome());
      }
    } on Exception catch (e, stack) {
      log.severe(message: 'register failed', error: e, trace: stack);
      if (isClosed) return;
      emit(state.copyWith(registering: false, error: _mapError(e)));
    }
  }

  Future<void> deleteAddress() async {
    if (state.registering) return;
    final currentAddress = state.lightningAddress;
    emit(state.copyWith(registering: true, error: null));
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
      unawaited(_settings.clearNostrPublishOutcome());
      unawaited(_clearNostrInBackground());
    } on Exception catch (e) {
      if (isClosed) return;
      emit(state.copyWith(registering: false, error: _mapError(e)));
    }
  }

  Future<void> republishOnNostr() async {
    final address = state.lightningAddress;
    if (address == null) return;
    if (state.nostrPublishStatus == NostrPublishStatus.pending) return;
    emit(state.copyWith(nostrPublishStatus: NostrPublishStatus.pending));
    final nym = address.split('@').first;
    unawaited(_publishNostrInBackground(nym));
  }

  // Hydrates the publish-status row from persisted outcome. On cold start
  // (outcome is null) seeds it with one publish; otherwise no relay traffic.
  Future<void> _emitActivated({
    required String address,
    required bool walletExists,
    NymQuota? quota,
  }) async {
    final persisted = await _settings.getNostrPublishOutcome();
    if (isClosed) return;
    final status = persisted ?? NostrPublishStatus.pending;
    emit(state.copyWith(
      loading: false,
      walletExists: walletExists,
      lightningAddress: address,
      quota: quota ?? state.quota,
      quotaStale: false,
      nostrPublishStatus: status,
    ));
    if (persisted == null) {
      final nym = address.split('@').first;
      unawaited(_publishNostrInBackground(nym));
    }
  }

  Future<void> _publishNostrInBackground(String nym) async {
    NostrPublishStatus outcome;
    try {
      await _publishProfile.execute(nym: nym);
      outcome = NostrPublishStatus.success;
    } on LightningAddressNostrPublishFailedException catch (e, stack) {
      log.warning('LA nostr publish failed', error: e, trace: stack);
      outcome = NostrPublishStatus.failed;
    }
    if (!_isStillActiveAs(nym)) return;
    await _settings.setNostrPublishOutcome(outcome);
    if (!_isStillActiveAs(nym)) return;
    if (isClosed) return;
    emit(state.copyWith(nostrPublishStatus: outcome));
  }

  bool _isStillActiveAs(String nym) {
    final addr = state.lightningAddress;
    if (addr == null) return false;
    return addr.split('@').first == nym;
  }

  Future<void> _clearNostrInBackground() async {
    try {
      await _clearProfile.execute();
    } on LightningAddressNostrPublishFailedException catch (e, stack) {
      log.warning('LA nostr clear failed', error: e, trace: stack);
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
