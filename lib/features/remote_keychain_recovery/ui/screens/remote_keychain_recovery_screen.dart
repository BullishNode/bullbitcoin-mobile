import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/features/get_paid_settings/public/automated_backup_consent.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_routes.dart';
import 'package:bb_mobile/features/payment_page/public/payment_page_facade.dart';
import 'package:bb_mobile/features/payment_page/public/payment_page_routes.dart';
import 'package:bb_mobile/features/pos/public/pos_facade.dart';
import 'package:bb_mobile/features/pos/public/pos_routes.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/presentation/remote_keychain_recovery_cubit.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/presentation/remote_keychain_recovery_state.dart';
import 'package:bb_mobile/features/wallet/ui/wallet_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class RemoteKeychainRecoveryScreen extends StatefulWidget {
  const RemoteKeychainRecoveryScreen({super.key, required this.fromOnboarding});

  final bool fromOnboarding;

  @override
  State<RemoteKeychainRecoveryScreen> createState() =>
      _RemoteKeychainRecoveryScreenState();
}

class _RemoteKeychainRecoveryScreenState
    extends State<RemoteKeychainRecoveryScreen> {
  @override
  void initState() {
    super.initState();
    context.read<RemoteKeychainRecoveryCubit>().start();
  }

  Future<void> _handleDisclosure() async {
    final cubit = context.read<RemoteKeychainRecoveryCubit>();
    final accepted = await ensureAutomatedBackupConsent(context);
    if (!mounted) return;
    if (accepted) {
      await cubit.acceptRelayDisclosure();
    } else {
      await cubit.skip();
    }
  }

  void _exit() {
    if (widget.fromOnboarding) {
      context.goNamed(WalletRoute.walletHome.name);
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.loc.remoteKeychainRecoveryScreenTitle),
      ),
      body: SafeArea(
        child:
            BlocConsumer<
              RemoteKeychainRecoveryCubit,
              RemoteKeychainRecoveryState
            >(
              listenWhen: (previous, current) =>
                  previous.status != current.status &&
                  (current.status ==
                      RemoteKeychainRecoveryStatus.requiresRelayDisclosure),
              listener: (context, state) {
                if (state.status ==
                    RemoteKeychainRecoveryStatus.requiresRelayDisclosure) {
                  _handleDisclosure();
                }
              },
              builder: (context, state) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  child: _content(context, state),
                );
              },
            ),
      ),
    );
  }

  Widget _content(BuildContext context, RemoteKeychainRecoveryState state) {
    final cubit = context.read<RemoteKeychainRecoveryCubit>();
    // Exhaustive switch: a future status addition fails compilation, so no
    // produced signal can go unsurfaced (PR11/PR14 lesson).
    return switch (state.status) {
      RemoteKeychainRecoveryStatus.idle ||
      RemoteKeychainRecoveryStatus.checking => _progress(
        context,
        context.loc.remoteKeychainRecoveryChecking,
      ),
      RemoteKeychainRecoveryStatus.requiresRelayDisclosure => _progress(
        context,
        context.loc.remoteKeychainRecoveryDisclosureBlocked,
      ),
      RemoteKeychainRecoveryStatus.restoring => _progress(
        context,
        context.loc.remoteKeychainRecoveryRestoring,
      ),
      RemoteKeychainRecoveryStatus.olderManifestAvailable => _olderWarning(
        context,
        state,
        cubit,
      ),
      RemoteKeychainRecoveryStatus.restored => _restored(context, state),
      RemoteKeychainRecoveryStatus.partiallyRestored => _partiallyRestored(
        context,
        state,
      ),
      RemoteKeychainRecoveryStatus.nothingToRestore ||
      RemoteKeychainRecoveryStatus.noRecoverableManifest => _message(
        context,
        context.loc.remoteKeychainRecoveryNothingToRestore,
        actionLabel: context.loc.remoteKeychainRecoveryDoneAction,
        onAction: _exit,
      ),
      RemoteKeychainRecoveryStatus.noManifestFound => _message(
        context,
        context.loc.remoteKeychainRecoveryNoManifestFound,
        actionLabel: context.loc.remoteKeychainRecoveryDoneAction,
        onAction: _exit,
      ),
      RemoteKeychainRecoveryStatus.relaysUnavailable => _message(
        context,
        context.loc.remoteKeychainRecoveryRelaysUnavailable,
        actionLabel: context.loc.remoteKeychainRecoveryRetryAction,
        onAction: cubit.start,
      ),
      RemoteKeychainRecoveryStatus.unsupportedNewerManifest => _message(
        context,
        context.loc.remoteKeychainRecoveryUnsupportedNewerManifest,
        actionLabel: context.loc.remoteKeychainRecoveryDoneAction,
        onAction: _exit,
      ),
      RemoteKeychainRecoveryStatus.defaultWalletUnavailable => _message(
        context,
        state.failure?.toTranslated(context) ??
            context.loc.remoteKeychainRecoveryDefaultWalletUnavailable,
        actionLabel: context.loc.remoteKeychainRecoveryDoneAction,
        onAction: _exit,
      ),
      RemoteKeychainRecoveryStatus.restoreFailed => _message(
        context,
        state.failure?.toTranslated(context) ??
            context.loc.remoteKeychainRecoveryRestoreFailed,
        actionLabel: context.loc.remoteKeychainRecoveryRetryAction,
        onAction: cubit.start,
      ),
      RemoteKeychainRecoveryStatus.failed => _message(
        context,
        state.failure?.toTranslated(context) ??
            context.loc.remoteKeychainRecoveryCheckFailed,
        actionLabel: context.loc.remoteKeychainRecoveryRetryAction,
        onAction: cubit.start,
      ),
      RemoteKeychainRecoveryStatus.skipped => _message(
        context,
        context.loc.remoteKeychainRecoverySkipped,
        actionLabel: context.loc.remoteKeychainRecoveryDoneAction,
        onAction: _exit,
      ),
      RemoteKeychainRecoveryStatus.checkingMetadata => _progress(
        context,
        context.loc.walletMetadataRecoveryChecking,
      ),
      RemoteKeychainRecoveryStatus.restoringMetadata => _progress(
        context,
        context.loc.walletMetadataRecoveryRestoring,
      ),
      RemoteKeychainRecoveryStatus.metadataRestored ||
      RemoteKeychainRecoveryStatus.metadataPartiallyRestored => _metadataResult(
        context,
        state,
      ),
      RemoteKeychainRecoveryStatus.metadataNoSnapshot => _message(
        context,
        context.loc.walletMetadataRecoveryNoSnapshot,
        actionLabel: context.loc.remoteKeychainRecoveryDoneAction,
        onAction: _exit,
      ),
      RemoteKeychainRecoveryStatus.metadataRelaysUnavailable => _message(
        context,
        context.loc.walletMetadataRecoveryRelaysUnavailable,
        actionLabel: context.loc.remoteKeychainRecoveryRetryAction,
        onAction: cubit.startMetadataRecovery,
      ),
      RemoteKeychainRecoveryStatus.metadataNoCompleteSnapshot => _message(
        context,
        context.loc.walletMetadataRecoveryNoCompleteSnapshot,
        actionLabel: context.loc.remoteKeychainRecoveryDoneAction,
        onAction: _exit,
      ),
      RemoteKeychainRecoveryStatus.metadataUpdateRequired => _message(
        context,
        context.loc.walletMetadataRecoveryUpdateRequired,
        actionLabel: context.loc.remoteKeychainRecoveryDoneAction,
        onAction: _exit,
      ),
      RemoteKeychainRecoveryStatus.metadataFailed => _message(
        context,
        context.loc.walletMetadataRecoveryFailed,
        actionLabel: context.loc.remoteKeychainRecoveryRetryAction,
        onAction: cubit.startMetadataRecovery,
      ),
    };
  }

  Widget _progress(BuildContext context, String message) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        if (message.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
        ],
      ],
    );
  }

  Widget _message(
    BuildContext context,
    String message, {
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        FilledButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }

  Widget _olderWarning(
    BuildContext context,
    RemoteKeychainRecoveryState state,
    RemoteKeychainRecoveryCubit cubit,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          context.loc.remoteKeychainRecoveryOlderWarningTitle,
          style: context.font.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          context.loc.remoteKeychainRecoveryOlderWarningBody,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: cubit.restoreOlderManifest,
          child: Text(context.loc.remoteKeychainRecoveryRestoreOlderAction),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: cubit.skip,
          child: Text(context.loc.remoteKeychainRecoverySkipAction),
        ),
      ],
    );
  }

  Widget _restored(BuildContext context, RemoteKeychainRecoveryState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          context.loc.remoteKeychainRecoveryRestoredCount(state.restoredCount),
          textAlign: TextAlign.center,
        ),
        if (state.isOlderRestore) ...[
          const SizedBox(height: 8),
          Text(
            context.loc.remoteKeychainRecoveryRestoredFromOlderNote,
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 8),
        Text(
          context.loc.remoteKeychainRecoveryRestoredDefaultsNote,
          style: context.font.bodySmall?.copyWith(
            color: context.appColors.textMuted,
          ),
          textAlign: TextAlign.center,
        ),
        ..._healRows(context, state),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _exit,
          child: Text(context.loc.remoteKeychainRecoveryDoneAction),
        ),
      ],
    );
  }

  Widget _partiallyRestored(
    BuildContext context,
    RemoteKeychainRecoveryState state,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          context.loc.remoteKeychainRecoveryPartiallyRestored(
            state.restoredCount,
            state.failedCount,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          context.loc.remoteKeychainRecoveryRestoredDefaultsNote,
          style: context.font.bodySmall?.copyWith(
            color: context.appColors.textMuted,
          ),
          textAlign: TextAlign.center,
        ),
        ..._healRows(context, state),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _exit,
          child: Text(context.loc.remoteKeychainRecoveryDoneAction),
        ),
      ],
    );
  }

  Widget _metadataResult(
    BuildContext context,
    RemoteKeychainRecoveryState state,
  ) {
    final skipped = state.metadataUnsupportedCount + state.metadataInvalidCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (state.restoredCount > 0) ...[
          Text(
            state.failedCount > 0
                ? context.loc.remoteKeychainRecoveryPartiallyRestored(
                    state.restoredCount,
                    state.failedCount,
                  )
                : context.loc.remoteKeychainRecoveryRestoredCount(
                    state.restoredCount,
                  ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
        ],
        Text(
          context.loc.walletMetadataRecoveryRestoredCount(
            state.metadataRestoredCount,
            state.metadataAlreadyPresentCount,
          ),
          style: context.font.titleMedium,
          textAlign: TextAlign.center,
        ),
        if (state.metadataIsOlder) ...[
          const SizedBox(height: 12),
          Text(
            context.loc.walletMetadataRecoveryOlderResult,
            textAlign: TextAlign.center,
          ),
        ],
        if (state.status ==
            RemoteKeychainRecoveryStatus.metadataPartiallyRestored) ...[
          const SizedBox(height: 12),
          Text(
            context.loc.walletMetadataRecoveryResultDetails(
              state.metadataConflictCount,
              state.metadataDeferredCount,
              skipped,
              state.metadataFailedCount,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _exit,
          child: Text(context.loc.remoteKeychainRecoveryDoneAction),
        ),
      ],
    );
  }

  // DG-3 rendering: live/reregistered/archivedByUser/null render NOTHING (no
  // prompt, no affordance); needsReactivation offers a re-activate route;
  // unreachable degrades loudly without an auto-prompt.
  List<Widget> _healRows(
    BuildContext context,
    RemoteKeychainRecoveryState state,
  ) {
    return [
      ..._lightningAddressHealRows(context, state),
      ..._paymentPageHealRows(context, state),
      ..._posHealRows(context, state),
    ];
  }

  List<Widget> _lightningAddressHealRows(
    BuildContext context,
    RemoteKeychainRecoveryState state,
  ) {
    final outcome = state.healOutcome;
    if (outcome == null) return const [];
    switch (outcome.liveness) {
      case LightningAddressRegistrationLiveness.live:
      case LightningAddressRegistrationLiveness.reregistered:
        return const [];
      case LightningAddressRegistrationLiveness.needsReactivation:
        return [
          const SizedBox(height: 16),
          Text(
            context.loc.remoteKeychainRecoveryHealNeedsReactivation,
            style: TextStyle(color: context.appColors.error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => context.goNamed(
              LightningAddressRoute.lightningAddressSettings.name,
            ),
            child: Text(
              context.loc.remoteKeychainRecoveryHealNeedsReactivationAction,
            ),
          ),
        ];
      case LightningAddressRegistrationLiveness.unreachable:
        return [
          const SizedBox(height: 16),
          Text(
            context.loc.remoteKeychainRecoveryHealUnreachable,
            style: TextStyle(color: context.appColors.error),
            textAlign: TextAlign.center,
          ),
        ];
    }
  }

  List<Widget> _paymentPageHealRows(
    BuildContext context,
    RemoteKeychainRecoveryState state,
  ) {
    final outcome = state.paymentPageHealOutcome;
    if (outcome == null) return const [];
    switch (outcome.liveness) {
      case PaymentPageLiveness.live:
      case PaymentPageLiveness.archivedByUser:
        return const [];
      case PaymentPageLiveness.needsReactivation:
        return [
          const SizedBox(height: 16),
          Text(
            context.loc.paymentPageHealNeedsReactivation,
            style: TextStyle(color: context.appColors.error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () =>
                context.goNamed(PaymentPageRoute.paymentPageSettings.name),
            child: Text(context.loc.paymentPageHealNeedsReactivationAction),
          ),
        ];
      case PaymentPageLiveness.unreachable:
        return [
          const SizedBox(height: 16),
          Text(
            context.loc.paymentPageHealUnreachable,
            style: TextStyle(color: context.appColors.error),
            textAlign: TextAlign.center,
          ),
        ];
    }
  }

  List<Widget> _posHealRows(
    BuildContext context,
    RemoteKeychainRecoveryState state,
  ) {
    final outcome = state.posHealOutcome;
    if (outcome == null) return const [];
    switch (outcome.liveness) {
      case PosLiveness.live:
      case PosLiveness.archivedByUser:
        return const [];
      case PosLiveness.needsReactivation:
        return [
          const SizedBox(height: 16),
          Text(
            context.loc.posHealNeedsReactivation,
            style: TextStyle(color: context.appColors.error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => context.goNamed(PosRoute.posSettings.name),
            child: Text(context.loc.posHealNeedsReactivationAction),
          ),
        ];
      case PosLiveness.unreachable:
        return [
          const SizedBox(height: 16),
          Text(
            context.loc.posHealUnreachable,
            style: TextStyle(color: context.appColors.error),
            textAlign: TextAlign.center,
          ),
        ];
    }
  }
}
