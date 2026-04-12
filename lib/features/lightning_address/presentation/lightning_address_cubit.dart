import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_errors.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/get_lightning_address_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/register_lightning_address_usecase.dart';
import 'package:bb_mobile/features/lightning_address/presentation/lightning_address_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class LightningAddressCubit extends Cubit<LightningAddressState> {
  final GetLightningAddressWalletUsecase _getWallet;
  final RegisterLightningAddressUsecase _register;

  LightningAddressCubit({
    required GetLightningAddressWalletUsecase getWallet,
    required RegisterLightningAddressUsecase register,
  })  : _getWallet = getWallet,
        _register = register,
        super(const LightningAddressState());

  Future<void> checkStatus(Environment environment) async {
    try {
      final wallet = await _getWallet.execute(environment: environment);
      if (isClosed) return;
      emit(state.copyWith(
        loading: false,
        lightningAddress: wallet != null
            ? '${wallet.label ?? ""}@$lightningAddressDomain'
            : null,
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
      emit(state.copyWith(registering: false, lightningAddress: address));
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
    return 'Something went wrong. Please try again.';
  }
}
