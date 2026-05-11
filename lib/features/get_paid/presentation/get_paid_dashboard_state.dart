import 'package:bb_mobile/features/get_paid/payment_page/domain/entities/payment_page.dart';

class GetPaidDashboardState {
  final bool isLoading;
  final String? lightningAddress;
  final PaymentPage? paymentPage;
  final String? error;

  const GetPaidDashboardState({
    this.isLoading = false,
    this.lightningAddress,
    this.paymentPage,
    this.error,
  });

  bool get hasLightningAddress => lightningAddress != null;
  bool get hasPaymentPage => paymentPage != null && !paymentPage!.isArchived;
  String? get nym => lightningAddress?.split('@').firstOrNull;

  GetPaidDashboardState copyWith({
    bool? isLoading,
    String? lightningAddress,
    bool clearLightningAddress = false,
    PaymentPage? paymentPage,
    bool clearPaymentPage = false,
    String? error,
    bool clearError = false,
  }) {
    return GetPaidDashboardState(
      isLoading: isLoading ?? this.isLoading,
      lightningAddress: clearLightningAddress
          ? null
          : lightningAddress ?? this.lightningAddress,
      paymentPage: clearPaymentPage ? null : paymentPage ?? this.paymentPage,
      error: clearError ? null : error ?? this.error,
    );
  }
}
