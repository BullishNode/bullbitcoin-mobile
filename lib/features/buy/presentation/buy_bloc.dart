import 'package:bb_mobile/core/errors/exchange_errors.dart';
import 'package:bb_mobile/core/exchange/domain/entity/order.dart';
import 'package:bb_mobile/core/exchange/domain/entity/user_summary.dart';
import 'package:bb_mobile/core/exchange/domain/usecases/accelerate_buy_order_usecase.dart';
import 'package:bb_mobile/core/exchange/domain/usecases/confirm_buy_order_usecase.dart';
import 'package:bb_mobile/core/exchange/domain/usecases/convert_sats_to_currency_amount_usecase.dart';
import 'package:bb_mobile/core/exchange/domain/usecases/create_buy_order_usecase.dart';
import 'package:bb_mobile/core/exchange/domain/usecases/get_exchange_user_summary_usecase.dart';
import 'package:bb_mobile/core/exchange/domain/usecases/refresh_buy_order_usecase.dart';
import 'package:bb_mobile/core/fees/domain/fees_entity.dart';
import 'package:bb_mobile/core/fees/domain/get_network_fees_usecase.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_receive_address_use_case.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallets_usecase.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'buy_bloc.freezed.dart';
part 'buy_event.dart';
part 'buy_state.dart';

class BuyBloc extends Bloc<BuyEvent, BuyState> {
  BuyBloc({
    required GetWalletsUsecase getWalletsUsecase,
    required GetReceiveAddressUsecase getReceiveAddressUsecase,
    required GetExchangeUserSummaryUsecase getExchangeUserSummaryUsecase,
    required ConfirmBuyOrderUsecase confirmBuyOrderUsecase,
    required CreateBuyOrderUsecase createBuyOrderUsecase,
    required RefreshBuyOrderUsecase refreshBuyOrderUsecase,
    required GetNetworkFeesUsecase getNetworkFeesUsecase,
    required ConvertSatsToCurrencyAmountUsecase
    convertSatsToCurrencyAmountUsecase,
    required AccelerateBuyOrderUsecase accelerateBuyOrderUsecase,
  }) : _getWalletsUsecase = getWalletsUsecase,
       _getReceiveAddressUsecase = getReceiveAddressUsecase,
       _getExchangeUserSummaryUsecase = getExchangeUserSummaryUsecase,
       _confirmBuyOrderUsecase = confirmBuyOrderUsecase,
       _createBuyOrderUsecase = createBuyOrderUsecase,
       _refreshBuyOrderUsecase = refreshBuyOrderUsecase,
       _getNetworkFeesUsecase = getNetworkFeesUsecase,
       _convertSatsToCurrencyAmountUsecase = convertSatsToCurrencyAmountUsecase,
       _accelerateBuyOrderUsecase = accelerateBuyOrderUsecase,
       super(const BuyState()) {
    on<_BuyStarted>(_onStarted);
    on<_BuyAmountInputChanged>(_onAmountInputChanged);
    on<_BuyCurrencyInputChanged>(_onCurrencyInputChanged);
    on<_BuySelectedWalletChanged>(_onSelectedWalletChanged);
    on<_BuyBitcoinAddressInputChanged>(_onBitcoinAddressInputChanged);
    on<_BuyCreateOrder>(_onCreateOrder);
    on<_BuyRefreshOrder>(_onRefreshOrder);
    on<_BuyConfirmOrder>(_onConfirmOrder);
    on<_BuyAccelerateTransactionPressed>(_onAccelerateTransactionPressed);
    on<_BuyAccelerateTransactionConfirmed>(_onAccelerateTransactionConfirmed);
  }

  final GetWalletsUsecase _getWalletsUsecase;
  final GetReceiveAddressUsecase _getReceiveAddressUsecase;
  final GetExchangeUserSummaryUsecase _getExchangeUserSummaryUsecase;
  final ConfirmBuyOrderUsecase _confirmBuyOrderUsecase;
  final CreateBuyOrderUsecase _createBuyOrderUsecase;
  final RefreshBuyOrderUsecase _refreshBuyOrderUsecase;
  final GetNetworkFeesUsecase _getNetworkFeesUsecase;
  final ConvertSatsToCurrencyAmountUsecase _convertSatsToCurrencyAmountUsecase;
  final AccelerateBuyOrderUsecase _accelerateBuyOrderUsecase;

  Future<void> _onStarted(_BuyStarted event, Emitter<BuyState> emit) async {
    try {
      final summary = await _getExchangeUserSummaryUsecase.execute();
      emit(
        state.copyWith(
          userSummary: summary,
          apiKeyException: null,
          getUserSummaryException: null,
          currencyInput: summary.currency,
        ),
      );

      final wallets = await _getWalletsUsecase.execute();
      emit(
        state.copyWith(
          wallets: wallets,
          selectedWallet: wallets.isNotEmpty ? wallets.first : null,
        ),
      );
    } catch (e) {
      log.severe('[BuyBloc] _onStarted error: $e');
      if (e is ApiKeyException) {
        // If the API key is invalid, we should not proceed with the buy flow.
        emit(state.copyWith(apiKeyException: e));
      }
      if (e is GetExchangeUserSummaryException) {
        emit(state.copyWith(getUserSummaryException: e));
      } else if (e is GetWalletsException) {
        emit(state.copyWith(getWalletsException: e));
      }
    } finally {
      emit(state.copyWith(isStarted: true));
    }
  }

  Future<void> _onAmountInputChanged(
    _BuyAmountInputChanged event,
    Emitter<BuyState> emit,
  ) async {
    try {
      emit(state.copyWith(amountInput: event.amount));
    } catch (e) {
      log.severe('[BuyBloc] _onAmountInputChanged error: $e');
    }
  }

  Future<void> _onCurrencyInputChanged(
    _BuyCurrencyInputChanged event,
    Emitter<BuyState> emit,
  ) async {
    try {
      emit(state.copyWith(currencyInput: event.currencyCode));
    } catch (e) {
      log.severe('[BuyBloc] _onCurrencyInputChanged error: $e');
    }
  }

  Future<void> _onSelectedWalletChanged(
    _BuySelectedWalletChanged event,
    Emitter<BuyState> emit,
  ) async {
    try {
      emit(state.copyWith(selectedWallet: event.wallet));
    } catch (e) {
      log.severe('[BuyBloc] _onSelectedWalletChanged error: $e');
      if (e is GetReceiveAddressException) {
        emit(state.copyWith(getReceiveAddressException: e));
      }
    }
  }

  Future<void> _onBitcoinAddressInputChanged(
    _BuyBitcoinAddressInputChanged event,
    Emitter<BuyState> emit,
  ) async {
    try {
      emit(state.copyWith(bitcoinAddressInput: event.bitcoinAddress));
    } catch (e) {
      log.severe('[BuyBloc] _onBitcoinAddressInputChanged error: $e');
    }
  }

  Future<void> _onCreateOrder(
    _BuyCreateOrder event,
    Emitter<BuyState> emit,
  ) async {
    try {
      // Clear any previous exceptions and reset the buy order so that we create
      //  a new one on every Continue button press as the data may have changed.
      emit(
        state.copyWith(
          isCreatingOrder: true,
          buyOrder: null,
          getReceiveAddressException: null,
          createBuyOrderException: null,
        ),
      );

      final wallet = state.selectedWallet;
      String toAddress;
      if (wallet != null) {
        // If a wallet is selected, fetch the receive address for it.
        final walletAddress = await _getReceiveAddressUsecase.execute(
          walletId: wallet.id,
        );
        toAddress = walletAddress.address;
      } else {
        // If no wallet is selected, use the bitcoin address input.
        toAddress = state.bitcoinAddressInput;
      }
      final order = await _createBuyOrderUsecase.execute(
        toAddress: toAddress,
        orderAmount: FiatAmount(state.amount!),
        currency: state.currency,
        isLiquid: state.selectedWallet?.network.isLiquid == true,
        isOwner: true,
      );

      emit(state.copyWith(buyOrder: order));
    } catch (e) {
      if (e is GetReceiveAddressException) {
        emit(state.copyWith(getReceiveAddressException: e));
      } else if (e is CreateBuyOrderException) {
        emit(state.copyWith(createBuyOrderException: e));
      }
    } finally {
      emit(state.copyWith(isCreatingOrder: false));
    }
  }

  Future<void> _onRefreshOrder(
    _BuyRefreshOrder event,
    Emitter<BuyState> emit,
  ) async {
    try {
      final orderId = event.orderId ?? state.buyOrder!.orderId;

      emit(
        state.copyWith(isRefreshingOrder: true, refreshBuyOrderException: null),
      );

      final order = await _refreshBuyOrderUsecase.execute(orderId: orderId);

      emit(state.copyWith(buyOrder: order));
    } catch (e) {
      log.severe('[BuyBloc] _onRefreshOrder error: $e');
      if (e is RefreshBuyOrderException) {
        emit(state.copyWith(refreshBuyOrderException: e));
      }
    } finally {
      emit(state.copyWith(isRefreshingOrder: false));
    }
  }

  Future<void> _onConfirmOrder(
    _BuyConfirmOrder event,
    Emitter<BuyState> emit,
  ) async {
    try {
      emit(
        state.copyWith(isConfirmingOrder: true, confirmBuyOrderException: null),
      );

      final order = await _confirmBuyOrderUsecase.execute(
        orderId: state.buyOrder!.orderId,
      );

      emit(state.copyWith(buyOrder: order));
    } catch (e) {
      log.severe('[BuyBloc] _onConfirmOrder error: $e');
      if (e is ConfirmBuyOrderException) {
        emit(state.copyWith(confirmBuyOrderException: e));
      }
    } finally {
      emit(state.copyWith(isConfirmingOrder: false));
    }
  }

  Future<void> _onAccelerateTransactionPressed(
    _BuyAccelerateTransactionPressed event,
    Emitter<BuyState> emit,
  ) async {
    try {
      emit(
        state.copyWith(
          refreshBuyOrderException: null,
          getNetworkFeesException: null,
          convertSatsToCurrencyAmountException: null,
        ),
      );

      final order = await _refreshBuyOrderUsecase.execute(
        orderId: event.orderId,
      );

      final (networkFees, exchangeRate) =
          await (
            _getNetworkFeesUsecase.execute(isLiquid: false),
            _convertSatsToCurrencyAmountUsecase.execute(
              currencyCode: order.payinCurrency,
            ),
          ).wait;

      emit(
        state.copyWith(
          buyOrder: order,
          accelerationNetworkFees: networkFees,
          exchangeRate: exchangeRate,
        ),
      );
    } catch (e) {
      log.severe('[BuyBloc] _onAccelerateTransactionPressed error: $e');

      if (e is RefreshBuyOrderException) {
        emit(state.copyWith(refreshBuyOrderException: e));
      } else if (e is GetNetworkFeesException) {
        emit(state.copyWith(getNetworkFeesException: e));
      } else if (e is ConvertSatsToCurrencyAmountException) {
        emit(state.copyWith(convertSatsToCurrencyAmountException: e));
      }
    }
  }

  Future<void> _onAccelerateTransactionConfirmed(
    _BuyAccelerateTransactionConfirmed event,
    Emitter<BuyState> emit,
  ) async {
    try {
      emit(
        state.copyWith(
          isAcceleratingOrder: true,
          accelerateBuyOrderException: null,
        ),
      );

      BuyOrder order = await _accelerateBuyOrderUsecase.execute(
        state.buyOrder!.orderId,
      );

      while (order.unbatchedBuyOnchainFees == null) {
        // Wait for the unbatched fees to be available
        await Future.delayed(const Duration(seconds: 3));
        order = await _refreshBuyOrderUsecase.execute(orderId: order.orderId);
      }

      emit(state.copyWith(buyOrder: order));
    } catch (e) {
      log.severe('[BuyBloc] _onAccelerateOrder error: $e');
      if (e is AccelerateBuyOrderException) {
        emit(state.copyWith(accelerateBuyOrderException: e));
      }
    } finally {
      emit(state.copyWith(isAcceleratingOrder: false));
    }
  }
}
