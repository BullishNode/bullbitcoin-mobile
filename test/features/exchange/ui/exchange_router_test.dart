import 'package:bb_mobile/features/exchange/ui/exchange_router.dart';
import 'package:bb_mobile/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test('auth route is registered at the root instead of in the shell', () {
    final topLevelRoutes = AppRouter.router.configuration.routes;
    final appShellRoute = topLevelRoutes.whereType<ShellRoute>().singleWhere(
      (shell) => shell.routes.whereType<GoRoute>().any(
        (route) => route.name == ExchangeRoute.exchangeHome.name,
      ),
    );

    expect(topLevelRoutes, contains(same(ExchangeRouter.authRoute)));
    expect(
      appShellRoute.routes,
      isNot(contains(same(ExchangeRouter.authRoute))),
    );
  });
}
