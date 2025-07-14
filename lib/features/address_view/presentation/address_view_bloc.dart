import 'package:bb_mobile/core/wallet/domain/entities/wallet_address.dart';
import 'package:bb_mobile/core/wallet/domain/wallet_error.dart';
import 'package:bb_mobile/features/address_view/domain/usecases/get_address_list_usecase.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'address_view_bloc.freezed.dart';
part 'address_view_event.dart';
part 'address_view_state.dart';

class AddressViewBloc extends Bloc<AddressViewEvent, AddressViewState> {
  final String _walletId;
  final int _limit;
  final GetAddressListUsecase _getAddressListUseCase;

  AddressViewBloc({
    required String walletId,
    required GetAddressListUsecase getAddressListUseCase,
    int? limit,
  }) : _walletId = walletId,
       _limit = limit ?? 20, // Default limit if not provided
       _getAddressListUseCase = getAddressListUseCase,
       super(const AddressViewState()) {
    on<AddressViewInitialAddressesLoaded>(_onInitialAddressesLoaded);
    on<AddressViewMoreReceiveAddressesLoaded>(_onMoreReceiveAddressesLoaded);
    on<AddressViewMoreChangeAddressesLoaded>(_onMoreChangeAddressesLoaded);
  }

  Future<void> _onInitialAddressesLoaded(
    AddressViewInitialAddressesLoaded event,
    Emitter<AddressViewState> emit,
  ) async {
    debugPrint('Loading initial addresses for wallet: $_walletId');
    emit(state.copyWith(isLoading: true));

    try {
      // Fetch initial receive and change addresses
      final (receiveAddresses, changeAddresses) =
          await (
            _getAddressListUseCase.execute(
              walletId: _walletId,
              limit: _limit,
              offset: 0,
            ),
            _getAddressListUseCase.execute(
              walletId: _walletId,
              isChange: true,
              limit: _limit,
              offset: 0,
            ),
          ).wait;

      emit(
        state.copyWith(
          receiveAddresses: receiveAddresses,
          changeAddresses: changeAddresses,
        ),
      );
    } on WalletError catch (error) {
      emit(state.copyWith(error: error));
    } finally {
      emit(state.copyWith(isLoading: false));
    }
  }

  Future<void> _onMoreReceiveAddressesLoaded(
    AddressViewMoreReceiveAddressesLoaded event,
    Emitter<AddressViewState> emit,
  ) async {
    if (state.isLoading || state.hasReachedEndOfReceiveAddresses) {
      return; // Prevent loading more if already loading or reached end
    }

    try {
      emit(state.copyWith(isLoading: true));

      final offset = state.receiveAddresses.length;
      final moreReceiveAddresses = await _getAddressListUseCase.execute(
        walletId: _walletId,
        limit: _limit,
        offset: offset,
      );

      emit(
        state.copyWith(
          receiveAddresses: List.from(state.receiveAddresses)
            ..addAll(moreReceiveAddresses),
        ),
      );
    } on WalletError catch (error) {
      emit(state.copyWith(error: error));
    } finally {
      emit(state.copyWith(isLoading: false));
    }
  }

  Future<void> _onMoreChangeAddressesLoaded(
    AddressViewMoreChangeAddressesLoaded event,
    Emitter<AddressViewState> emit,
  ) async {
    if (state.isLoading || state.hasReachedEndOfChangeAddresses) {
      return; // Prevent loading more if already loading or reached end
    }

    try {
      emit(state.copyWith(isLoading: true));

      final offset = state.changeAddresses.length;
      final moreChangeAddresses = await _getAddressListUseCase.execute(
        walletId: _walletId,
        isChange: true,
        limit: _limit,
        offset: offset,
      );

      emit(
        state.copyWith(
          changeAddresses: List.from(state.changeAddresses)
            ..addAll(moreChangeAddresses),
        ),
      );
    } on WalletError catch (error) {
      emit(state.copyWith(error: error));
    } finally {
      emit(state.copyWith(isLoading: false));
    }
  }
}
