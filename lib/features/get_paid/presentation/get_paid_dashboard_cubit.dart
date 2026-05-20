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
  int _refreshGeneration = 0;

  GetPaidDashboardCubit({
    required LightningAddressFacade lightningAddressFacade,
    required FindPaymentPageUsecase findPaymentPage,
  }) : _lightningAddressFacade = lightningAddressFacade,
       _findPaymentPage = findPaymentPage,
       super(const GetPaidDashboardState());

  Future<void> refresh() async {
    final generation = ++_refreshGeneration;
    emit(state.copyWith(isLoading: true, clearError: true));
    String? lightningAddress;
    String? nym;
    try {
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
        ),
      );
    } on PaymentPageApplicationError catch (e) {
      if (_isStale(generation)) return;
      emit(
        state.copyWith(
          isLoading: false,
          lightningAddress: lightningAddress,
          nym: nym,
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
          error: 'Something went wrong. Please try again.',
        ),
      );
    }
  }

  bool _isStale(int generation) {
    return isClosed || generation != _refreshGeneration;
  }
}
