import 'package:bb_mobile/features/get_paid/btcpay/application/get_btcpay_connection_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/payment_page_application_error.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/find_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/presentation/payment_page_error_message.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_dashboard_state.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class GetPaidDashboardCubit extends Cubit<GetPaidDashboardState> {
  final LightningAddressFacade _lightningAddressFacade;
  final FindPaymentPageUsecase _findPaymentPage;
  final GetBtcpayConnectionUsecase _getBtcpayConnection;
  int _refreshGeneration = 0;

  GetPaidDashboardCubit({
    required LightningAddressFacade lightningAddressFacade,
    required FindPaymentPageUsecase findPaymentPage,
    required GetBtcpayConnectionUsecase getBtcpayConnection,
  }) : _lightningAddressFacade = lightningAddressFacade,
       _findPaymentPage = findPaymentPage,
       _getBtcpayConnection = getBtcpayConnection,
       super(const GetPaidDashboardState());

  Future<void> refresh() async {
    final generation = ++_refreshGeneration;
    emit(state.copyWith(isLoading: true, clearError: true));
    String? lightningAddress;
    String? nym;
    var btcpayConnection = state.btcpayConnection;
    try {
      btcpayConnection = await _getBtcpayConnection.execute();
      lightningAddress = await _lightningAddressFacade
          .getCurrentLightningAddress();
      nym = lightningAddress?.split('@').firstOrNull;

      if (nym == null || nym.isEmpty) {
        if (_isStale(generation)) return;
        emit(
          state.copyWith(
            isLoading: false,
            clearLightningAddress: true,
            clearNym: true,
            clearPaymentPage: true,
            btcpayConnection: btcpayConnection,
            clearBtcpayConnection: btcpayConnection == null,
          ),
        );
        return;
      }

      if (_isStale(generation)) return;
      final paymentPage = await _findPaymentPage.execute(nym: nym);
      if (_isStale(generation)) return;
      emit(
        state.copyWith(
          isLoading: false,
          lightningAddress: lightningAddress,
          nym: nym,
          paymentPage: paymentPage?.isArchived == true ? null : paymentPage,
          clearPaymentPage: paymentPage == null || paymentPage.isArchived,
          btcpayConnection: btcpayConnection,
          clearBtcpayConnection: btcpayConnection == null,
        ),
      );
    } on PaymentPageApplicationError catch (e) {
      if (_isStale(generation)) return;
      emit(
        state.copyWith(
          isLoading: false,
          lightningAddress: lightningAddress,
          nym: nym,
          btcpayConnection: btcpayConnection,
          clearBtcpayConnection: btcpayConnection == null,
          error: paymentPageErrorMessage(e),
        ),
      );
    } on Exception catch (e) {
      if (_isStale(generation)) return;
      log.warning('Get Paid dashboard refresh failed', error: e);
      emit(
        state.copyWith(
          isLoading: false,
          lightningAddress: lightningAddress,
          nym: nym,
          btcpayConnection: btcpayConnection,
          clearBtcpayConnection: btcpayConnection == null,
          error: 'Something went wrong. Please try again.',
        ),
      );
    }
  }

  bool _isStale(int generation) {
    return isClosed || generation != _refreshGeneration;
  }
}
