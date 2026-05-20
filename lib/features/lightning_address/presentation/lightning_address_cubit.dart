import 'dart:async';

import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/external_receive_wallets/public/external_receive_wallets.dart';
import 'package:bb_mobile/features/lightning_address/data/datasources/lightning_address_settings_datasource.dart';
import 'package:bb_mobile/features/lightning_address/domain/entities/lookup_result.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_errors.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/primitives/nostr_publish_status.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/clear_lightning_address_nostr_profile_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/delete_lightning_address_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/lookup_lightning_address_status_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/publish_lightning_address_nostr_profile_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/register_lightning_address_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/value_objects/nym_quota.dart';
import 'package:bb_mobile/features/lightning_address/domain/value_objects/previous_nym.dart';
import 'package:bb_mobile/features/lightning_address/presentation/lightning_address_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class LightningAddressCubit extends Cubit<LightningAddressState> {
  final ExternalReceiveWalletsFacade _externalReceiveWallets;
  final RegisterLightningAddressUsecase _register;
  final DeleteLightningAddressUsecase _delete;
  final LookupLightningAddressStatusUsecase _lookupStatus;
  final PublishLightningAddressNostrProfileUsecase _publishProfile;
  final ClearLightningAddressNostrProfileUsecase _clearProfile;
  final PayServicePort _payService;
  final LightningAddressSettingsDatasource _settings;

  LightningAddressCubit({
    required ExternalReceiveWalletsFacade externalReceiveWallets,
    required RegisterLightningAddressUsecase register,
    required DeleteLightningAddressUsecase delete,
    required LookupLightningAddressStatusUsecase lookupStatus,
    required PublishLightningAddressNostrProfileUsecase publishProfile,
    required ClearLightningAddressNostrProfileUsecase clearProfile,
    required PayServicePort payService,
    required LightningAddressSettingsDatasource settings,
  }) : _externalReceiveWallets = externalReceiveWallets,
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
      final wallet = await _externalReceiveWallets.get(
        environment: environment,
        purpose: ExternalReceiveWalletPurpose.lightningAddress,
      );
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
        case ActiveLookupResult(:final nym, :final quota, :final previousNyms):
          final address = '$nym@$lightningAddressDomain';
          await _payService.storeAddress(address);
          if (isClosed) return;
          await _emitActivated(
            address: address,
            walletExists: wallet != null,
            quota: quota,
            previousNyms: previousNyms,
          );
        case InactiveLookupResult(:final quota, :final previousNyms):
          emit(
            state.copyWith(
              loading: false,
              walletExists: wallet != null,
              previousNyms: previousNyms,
              quota: quota,
              quotaStale: false,
              nostrPublishStatus: NostrPublishStatus.none,
            ),
          );
        case null:
          emit(state.copyWith(loading: false, walletExists: wallet != null));
      }
    } on Exception catch (e) {
      if (isClosed) return;
      log.warning('LA status check failed', error: e);
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
      if (!publishOnNostr) {
        try {
          await _settings.setNostrPublishOutcome(NostrPublishStatus.none);
        } on Exception catch (e, stack) {
          log.warning(
            'LA nostr opt-out persistence failed',
            error: e,
            trace: stack,
          );
          if (isClosed) return;
          emit(
            state.copyWith(
              registering: false,
              error: 'Could not save Nostr preference. Please try again.',
            ),
          );
          return;
        }
      }
      if (isClosed) return;
      final result = await _register.execute(
        nym: nym,
        environment: environment,
      );
      if (isClosed) return;
      emit(
        state.copyWith(
          registering: false,
          lightningAddress: result.address,
          previousNyms: state.previousNyms.where((p) => p.nym != nym).toList(),
          quota: result.quota,
          quotaStale: false,
          nostrPublishStatus: publishOnNostr
              ? NostrPublishStatus.pending
              : NostrPublishStatus.none,
        ),
      );
      if (publishOnNostr) {
        unawaited(_publishNostrInBackground(nym));
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
    final nym = currentAddress?.split('@').firstOrNull;
    if (nym == null) {
      emit(
        state.copyWith(
          registering: false,
          error: 'No Lightning Address is active',
        ),
      );
      return;
    }
    emit(state.copyWith(registering: true, error: null));
    try {
      final quota = await _delete.execute(nym: nym);
      if (isClosed) return;
      final previousNyms = [
        PreviousNym(nym: nym, createdAt: DateTime.now()),
        ...state.previousNyms.where((p) => p.nym != nym),
      ];
      emit(
        LightningAddressState(
          loading: false,
          walletExists: state.walletExists,
          previousNyms: previousNyms,
          quota: quota,
          quotaStale: false,
        ),
      );
      unawaited(_clearNostrOutcomeBestEffort());
      unawaited(_clearNostrInBackground());
    } on Exception catch (e, stack) {
      log.warning('delete LA failed', error: e, trace: stack);
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

  // Hydrates the publish-status row from persisted outcome. Unknown state
  // fails closed as no-publish; publishing only starts from explicit register
  // or republish actions.
  Future<void> _emitActivated({
    required String address,
    required bool walletExists,
    NymQuota? quota,
    List<PreviousNym>? previousNyms,
  }) async {
    final persisted = await _settings.getNostrPublishOutcome();
    if (isClosed) return;
    final status = persisted ?? NostrPublishStatus.none;
    emit(
      state.copyWith(
        loading: false,
        walletExists: walletExists,
        lightningAddress: address,
        previousNyms: previousNyms ?? state.previousNyms,
        quota: quota ?? state.quota,
        quotaStale: false,
        nostrPublishStatus: status,
      ),
    );
  }

  Future<void> _publishNostrInBackground(String nym) async {
    NostrPublishStatus outcome;
    try {
      await _publishProfile.execute(nym: nym);
      outcome = NostrPublishStatus.success;
    } on Exception catch (e, stack) {
      log.warning('LA nostr publish failed', error: e, trace: stack);
      outcome = NostrPublishStatus.failed;
    }
    if (!_isStillActiveAs(nym)) return;
    await _persistNostrOutcomeBestEffort(outcome);
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

  Future<void> _persistNostrOutcomeBestEffort(
    NostrPublishStatus outcome,
  ) async {
    try {
      await _settings.setNostrPublishOutcome(outcome);
    } on Exception catch (e, stack) {
      log.warning(
        'LA nostr publish outcome persistence failed',
        error: e,
        trace: stack,
      );
    }
  }

  Future<void> _clearNostrOutcomeBestEffort() async {
    try {
      await _settings.clearNostrPublishOutcome();
    } on Exception catch (e, stack) {
      log.warning(
        'LA nostr publish outcome clear failed',
        error: e,
        trace: stack,
      );
    }
  }

  String _mapError(Exception e) {
    if (e is LightningAddressRegistrationException) {
      return switch (e.message) {
        'This nym is not available' => e.message,
        'Too many distinct wallets have used this service from this network. Retry later, or switch networks.' =>
          e.message,
        _ => 'Could not update Lightning Address. Please try again.',
      };
    }
    if (e is ExternalReceiveWalletAlreadyExistsException) {
      return 'Wallet already exists';
    }
    if (e is LightningAddressNoDefaultWalletException ||
        e is ExternalReceiveWalletNoDefaultWalletException) {
      return 'No wallet available';
    }
    if (e is ExternalReceiveWalletSweepException) return e.message;
    return 'Something went wrong. Please try again.';
  }
}
