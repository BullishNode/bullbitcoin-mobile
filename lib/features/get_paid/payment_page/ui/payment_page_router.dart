import 'package:bb_mobile/features/get_paid/payment_page/presentation/payment_page_cubit.dart';
import 'package:bb_mobile/features/get_paid/payment_page/ui/screens/payment_page_editor_screen.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

enum PaymentPageRoute {
  createPaymentPage('payment-page'),
  editor('payment-page/:nym');

  final String path;

  const PaymentPageRoute(this.path);
}

class PaymentPageRouter {
  static final createRoute = GoRoute(
    name: PaymentPageRoute.createPaymentPage.name,
    path: PaymentPageRoute.createPaymentPage.path,
    builder: (context, state) {
      return BlocProvider(
        create: (_) => locator<PaymentPageCubit>(),
        child: const PaymentPageEditorScreen(nym: ''),
      );
    },
  );

  static final editorRoute = GoRoute(
    name: PaymentPageRoute.editor.name,
    path: PaymentPageRoute.editor.path,
    builder: (context, state) {
      final nym = state.pathParameters['nym'] ?? '';
      return BlocProvider(
        create: (_) => locator<PaymentPageCubit>(),
        child: PaymentPageEditorScreen(nym: nym),
      );
    },
  );
}
