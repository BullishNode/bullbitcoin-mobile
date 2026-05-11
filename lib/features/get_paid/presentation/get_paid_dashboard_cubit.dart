import 'package:bb_mobile/features/get_paid/payment_page/application/payment_page_application_error.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/find_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_dashboard_state.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class GetPaidDashboardCubit extends Cubit<GetPaidDashboardState> {
  final LightningAddressFacade _lightningAddressFacade;
  final FindPaymentPageUsecase _findPaymentPage;

  GetPaidDashboardCubit({
    required LightningAddressFacade lightningAddressFacade,
    required FindPaymentPageUsecase findPaymentPage,
  }) : _lightningAddressFacade = lightningAddressFacade,
       _findPaymentPage = findPaymentPage,
       super(const GetPaidDashboardState());

  Future<void> refresh() async {
    emit(state.copyWith(isLoading: true, clearError: true));
    String? lightningAddress;
    try {
      lightningAddress = await _lightningAddressFacade
          .getCurrentLightningAddress();
      final nym = lightningAddress?.split('@').firstOrNull;

      if (nym == null || nym.isEmpty) {
        if (isClosed) return;
        emit(
          state.copyWith(
            isLoading: false,
            clearLightningAddress: true,
            clearPaymentPage: true,
          ),
        );
        return;
      }

      final paymentPage = await _findPaymentPage.execute(nym: nym);
      if (isClosed) return;
      emit(
        state.copyWith(
          isLoading: false,
          lightningAddress: lightningAddress,
          paymentPage: paymentPage?.isArchived == true ? null : paymentPage,
          clearPaymentPage: paymentPage == null || paymentPage.isArchived,
        ),
      );
    } on PaymentPageApplicationError catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(
          isLoading: false,
          lightningAddress: lightningAddress,
          error: e.message,
        ),
      );
    } on Exception catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(
          isLoading: false,
          lightningAddress: lightningAddress,
          error: e.toString(),
        ),
      );
    }
  }
}
