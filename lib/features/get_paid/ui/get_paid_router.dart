import 'package:bb_mobile/features/get_paid/presentation/get_paid_dashboard_cubit.dart';
import 'package:bb_mobile/features/get_paid/ui/screens/get_paid_dashboard_screen.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

enum GetPaidRoute {
  dashboard('/get-paid');

  final String path;

  const GetPaidRoute(this.path);
}

class GetPaidRouter {
  static final route = GoRoute(
    name: GetPaidRoute.dashboard.name,
    path: GetPaidRoute.dashboard.path,
    builder: (context, state) => BlocProvider(
      create: (_) => locator<GetPaidDashboardCubit>(),
      child: const GetPaidDashboardScreen(),
    ),
  );
}
