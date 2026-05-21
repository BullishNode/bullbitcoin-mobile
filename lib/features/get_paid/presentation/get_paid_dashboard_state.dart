import 'package:bb_mobile/features/get_paid/payment_page/domain/entities/payment_page.dart';
import 'package:bb_mobile/features/get_paid/btcpay/domain/btcpay_connection.dart';

class GetPaidDashboardState {
  final bool isLoading;
  final String? lightningAddress;
  final String? nym;
  final PaymentPage? paymentPage;
  final BtcpayConnection? btcpayConnection;
  final String? error;

  const GetPaidDashboardState({
    this.isLoading = false,
    this.lightningAddress,
    this.nym,
    this.paymentPage,
    this.btcpayConnection,
    this.error,
  });

  bool get hasLightningAddress => lightningAddress != null;
  bool get hasPaymentPage => paymentPage != null && !paymentPage!.isArchived;
  bool get hasBtcpayConnection => btcpayConnection != null;

  GetPaidDashboardState copyWith({
    bool? isLoading,
    String? lightningAddress,
    bool clearLightningAddress = false,
    String? nym,
    bool clearNym = false,
    PaymentPage? paymentPage,
    bool clearPaymentPage = false,
    BtcpayConnection? btcpayConnection,
    bool clearBtcpayConnection = false,
    String? error,
    bool clearError = false,
  }) {
    return GetPaidDashboardState(
      isLoading: isLoading ?? this.isLoading,
      lightningAddress: clearLightningAddress
          ? null
          : lightningAddress ?? this.lightningAddress,
      nym: clearNym ? null : nym ?? this.nym,
      paymentPage: clearPaymentPage ? null : paymentPage ?? this.paymentPage,
      btcpayConnection: clearBtcpayConnection
          ? null
          : btcpayConnection ?? this.btcpayConnection,
      error: clearError ? null : error ?? this.error,
    );
  }
}
