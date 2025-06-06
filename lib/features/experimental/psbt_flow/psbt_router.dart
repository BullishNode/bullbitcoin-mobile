import 'package:bb_mobile/features/experimental/psbt_flow/scan_signed_psbt/scan_signed_psbt_screen.dart';
import 'package:bb_mobile/features/experimental/psbt_flow/show_psbt/show_psbt_screen.dart';
import 'package:go_router/go_router.dart';

enum PsbtFlowRoutes {
  show('/show-psbt'),
  scanSignedPsbt('/scan-signed-psbt'),
  broadcastSignedPsbt('/broadcast-signed-psbt');

  final String path;
  const PsbtFlowRoutes(this.path);
}

class PsbtRouterConfig {
  static final route = ShellRoute(
    builder: (context, state, child) => child,
    routes: [
      GoRoute(
        name: PsbtFlowRoutes.show.name,
        path: PsbtFlowRoutes.show.path,
        builder: (context, state) {
          final psbt = state.extra as String?;
          return ShowPsbtScreen(psbt: psbt ?? '');
        },
      ),
      GoRoute(
        name: PsbtFlowRoutes.scanSignedPsbt.name,
        path: PsbtFlowRoutes.scanSignedPsbt.path,
        builder: (context, state) => const ScanSignedPsbtScreen(),
      ),
    ],
  );
}
