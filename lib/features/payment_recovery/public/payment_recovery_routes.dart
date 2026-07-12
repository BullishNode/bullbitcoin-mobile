import 'package:bb_mobile/features/payment_recovery/presentation/stuck_payment_detail_cubit.dart';
import 'package:bb_mobile/features/payment_recovery/presentation/stuck_payments_cubit.dart';
import 'package:bb_mobile/features/payment_recovery/public/payment_recovery_facade.dart';
import 'package:bb_mobile/features/payment_recovery/ui/screens/stuck_payment_detail_screen.dart';
import 'package:bb_mobile/features/payment_recovery/ui/screens/stuck_payments_screen.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

enum StuckPaymentsRoute {
  stuckPayments('/get-paid/recovery'),
  stuckPaymentDetail('detail/:id');

  final String path;

  const StuckPaymentsRoute(this.path);
}

/// The stuck-payments (recovery) route, pushed from the Get Paid hub banner,
/// with a per-invoice detail subroute.
class PaymentRecoveryRoutes {
  const PaymentRecoveryRoutes._();

  static final route = GoRoute(
    name: StuckPaymentsRoute.stuckPayments.name,
    path: StuckPaymentsRoute.stuckPayments.path,
    builder: (context, state) => BlocProvider(
      create: (_) => locator<StuckPaymentsCubit>()..refresh(),
      child: const StuckPaymentsScreen(),
    ),
    routes: [
      GoRoute(
        name: StuckPaymentsRoute.stuckPaymentDetail.name,
        path: StuckPaymentsRoute.stuckPaymentDetail.path,
        builder: (context, state) {
          final invoiceId = state.pathParameters['id']!;
          return BlocProvider(
            create: (_) => StuckPaymentDetailCubit(
              recovery: locator<PaymentRecoveryFacade>(),
              invoiceId: invoiceId,
            )..load(),
            child: const StuckPaymentDetailScreen(),
          );
        },
      ),
    ],
  );
}
