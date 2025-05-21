import 'dart:io';

import 'package:bb_mobile/core/utils/constants.dart';
import 'package:bb_mobile/features/app_startup/presentation/bloc/app_startup_bloc.dart';
import 'package:bb_mobile/features/app_unlock/ui/app_unlock_router.dart';
import 'package:bb_mobile/features/onboarding/ui/onboarding_router.dart';
import 'package:bb_mobile/features/onboarding/ui/screens/onboarding_splash.dart';
import 'package:bb_mobile/router.dart';
import 'package:bb_mobile/ui/components/buttons/button.dart';
import 'package:bb_mobile/ui/components/text/text.dart';
import 'package:bb_mobile/ui/themes/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AppStartupWidget extends StatefulWidget {
  const AppStartupWidget({super.key, required this.app});

  final Widget app;

  @override
  State<AppStartupWidget> createState() => _AppStartupWidgetState();
}

class _AppStartupWidgetState extends State<AppStartupWidget> {
  @override
  Widget build(BuildContext context) {
    return AppStartupListener(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: BlocBuilder<AppStartupBloc, AppStartupState>(
          builder: (context, state) {
            if (state is AppStartupInitial) {
              return const OnboardingSplash(loading: true);
            } else if (state is AppStartupLoadingInProgress) {
              return const OnboardingSplash(loading: true);
              // show status of migration
            } else if (state is AppStartupSuccess) {
              // if (!state.hasDefaultWallets) return const OnboardingScreen();
              // if (state.isPinCodeSet) return const PinCodeUnlockScreen();
              // return const HomeScreen();
              return widget.app;
            } else if (state is AppStartupFailure) {
              return const AppStartupFailureScreen();
            }

            // TODO: remove this when all states are handled and return the
            //  appropriate widget
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

class AppStartupListener extends StatelessWidget {
  const AppStartupListener({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<AppStartupBloc, AppStartupState>(
          listenWhen:
              (previous, current) =>
                  current is AppStartupSuccess && previous != current,
          listener: (context, state) {
            if (state is AppStartupSuccess && state.isPinCodeSet) {
              AppRouter.router.go(AppUnlockRoute.appUnlock.path);
            }

            if (state is AppStartupSuccess && !state.hasDefaultWallets) {
              AppRouter.router.go(OnboardingRoute.onboarding.path);
            }
          },
        ),
      ],
      child: child,
    );
  }
}

Future<void> _shareLogs(BuildContext context) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final logFile = File(
      '${dir.path}/${SettingsConstants.logFileName}',
    ); // Adjust to your filename

    if (!await logFile.exists()) {
      // ignore: use_build_context_synchronously
      final theme = Theme.of(context);
      ScaffoldMessenger.of(
        // ignore: use_build_context_synchronously
        context,
      ).showSnackBar(
        SnackBar(
          content: const Text(
            'No log file found.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.white),
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: theme.colorScheme.onSurface.withAlpha(204),
          behavior: SnackBarBehavior.floating,
          elevation: 4,
          margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      );
      return;
    }

    await SharePlus.instance.share(ShareParams(files: [XFile(logFile.path)]));
  } catch (e) {
    // ignore: use_build_context_synchronously
    final theme = Theme.of(context);
    ScaffoldMessenger.of(
      // ignore: use_build_context_synchronously
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(
          'Error sharing logs: $e',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: Colors.white),
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: theme.colorScheme.onSurface.withAlpha(204),
        behavior: SnackBarBehavior.floating,
        elevation: 4,
        margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}

class AppStartupFailureScreen extends StatelessWidget {
  const AppStartupFailureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              BBText(
                'Something went wrong during startup.',
                textAlign: TextAlign.center,
                style: context.font.headlineMedium,
              ),

              const SizedBox(height: 24),
              GestureDetector(
                onTap: () {
                  final url = Uri.parse('https://t.me/+gUHV3ZcQ-_RmZDdh');
                  // ignore: deprecated_member_use
                  launchUrl(url, mode: LaunchMode.externalApplication);
                },
                child: BBText(
                  'Contact Support',
                  style: context.font.headlineLarge,
                ),
              ),
              const SizedBox(height: 24),
              BBButton.big(
                onPressed: () async => await _shareLogs(context),
                label: 'Share Logs',
                borderColor: context.colour.secondary,
                outlined: true,
                bgColor: Colors.transparent,
                textColor: context.colour.secondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
