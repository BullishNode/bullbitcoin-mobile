import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_errors.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_key_derivation.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/delete_lightning_address_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/get_lightning_address_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/register_lightning_address_usecase.dart';
import 'package:bb_mobile/features/lightning_address/presentation/lightning_address_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class LightningAddressCubit extends Cubit<LightningAddressState> {
  final GetLightningAddressWalletUsecase _getWallet;
  final RegisterLightningAddressUsecase _register;
  final DeleteLightningAddressUsecase _delete;
  final PayServicePort _payService;
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;

  LightningAddressCubit({
    required GetLightningAddressWalletUsecase getWallet,
    required RegisterLightningAddressUsecase register,
    required DeleteLightningAddressUsecase delete,
    required PayServicePort payService,
    required WalletRepository walletRepository,
    required SeedRepository seedRepository,
  })  : _getWallet = getWallet,
        _register = register,
        _delete = delete,
        _payService = payService,
        _walletRepository = walletRepository,
        _seedRepository = seedRepository,
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
        return;
      }

      // No local state — check server for existing registration
      try {
        final nostr = await deriveNostrIdentityForLightningAddress(
          walletRepository: _walletRepository,
          seedRepository: _seedRepository,
        );
        if (nostr != null) {
          final lookup = await _payService.lookupByNpub(nostr.npubHex);
          if (lookup != null) {
            final address = '${lookup.nym}@$lightningAddressDomain';
            if (lookup.active) {
              await _payService.storeAddress(address);
              if (isClosed) return;
              emit(state.copyWith(
                loading: false,
                walletExists: wallet != null,
                lightningAddress: address,
              ));
              return;
            } else {
              if (isClosed) return;
              emit(state.copyWith(
                loading: false,
                walletExists: wallet != null,
                previousNym: lookup.nym,
              ));
              return;
            }
          }
        }
      } catch (e) {
        debugPrint('LA server lookup failed: $e');
      }

      if (isClosed) return;
      emit(state.copyWith(
        loading: false,
        walletExists: wallet != null,
      ));
    } on Exception catch (e) {
      if (isClosed) return;
      emit(state.copyWith(loading: false, error: _mapError(e)));
    }
  }

  Future<void> registerNym(String nym, Environment environment) async {
    if (nym.isEmpty) return;
    emit(state.copyWith(registering: true, error: null));

    try {
      final address = await _register.execute(
        nym: nym,
        environment: environment,
      );
      if (isClosed) return;
      emit(state.copyWith(
        registering: false,
        lightningAddress: address,
        previousNym: null,
      ));
    } catch (e, stack) {
      debugPrint('Lightning address registration error: $e');
      debugPrint('$stack');
      if (isClosed) return;
      final msg = e is Exception ? _mapError(e) : e.toString();
      emit(state.copyWith(registering: false, error: msg));
    }
  }

  Future<void> deleteAddress() async {
    final currentAddress = state.lightningAddress;
    emit(state.copyWith(registering: true, error: null));
    try {
      await _delete.execute();
      if (isClosed) return;
      // Extract nym from "nym@domain" for the previousNym banner
      final nym = currentAddress?.split('@').firstOrNull;
      emit(LightningAddressState(
        loading: false,
        walletExists: state.walletExists,
        previousNym: nym,
      ));
    } on Exception catch (e) {
      if (isClosed) return;
      emit(state.copyWith(registering: false, error: _mapError(e)));
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
