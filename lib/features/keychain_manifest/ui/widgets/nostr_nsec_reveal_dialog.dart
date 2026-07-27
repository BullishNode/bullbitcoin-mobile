import 'dart:async';

import 'package:bb_mobile/core/mixins/privacy_screen.dart';
import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/core/widgets/address_viewer.dart';
import 'package:bb_mobile/core/widgets/buttons/button.dart';
import 'package:bb_mobile/core/widgets/dialog/blurred_dialog.dart';
import 'package:bb_mobile/core/widgets/text/text.dart';
import 'package:bb_mobile/features/keychain_manifest/presentation/nostr_keys_cubit.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';

/// Shows a key's nsec for as long as the dialog is open, and no longer.
///
/// The secret is derived on demand, held only in this widget's state, and
/// cleared on close, copy, or the app leaving the foreground. It is never put
/// into cubit state, so it cannot survive a rebuild or be read back later.
class NostrNsecRevealDialog extends StatefulWidget {
  const NostrNsecRevealDialog({super.key, required this.record});

  final KeychainManifestNostrKeyRecord record;

  static Future<void> show(
    BuildContext context, {
    required NostrKeysCubit cubit,
    required KeychainManifestNostrKeyRecord record,
  }) {
    return BlurredDialog.show<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: NostrNsecRevealDialog(record: record),
      ),
    );
  }

  @override
  State<NostrNsecRevealDialog> createState() => _NostrNsecRevealDialogState();
}

class _NostrNsecRevealDialogState extends State<NostrNsecRevealDialog>
    with WidgetsBindingObserver, PrivacyScreen {
  String? _nsec;
  bool _dismissQueued = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(enableScreenPrivacy());
    WidgetsBinding.instance.addPostFrameCallback((_) => _derive());
  }

  @override
  void dispose() {
    _dismissQueued = true;
    WidgetsBinding.instance.removeObserver(this);
    _nsec = null;
    unawaited(disableScreenPrivacy());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) {
      _clearAndDismiss();
    }
  }

  Future<void> _derive() async {
    final nsec = await context.read<NostrKeysCubit>().reveal(widget.record);
    if (!mounted || _dismissQueued) return;
    if (nsec == null) {
      _clearAndDismiss();
      return;
    }
    setState(() => _nsec = nsec);
  }

  Future<void> _copy() async {
    final nsec = _nsec;
    if (nsec == null) return;
    _clearAndDismiss();
    await Clipboard.setData(ClipboardData(text: nsec));
  }

  void _clearAndDismiss() {
    if (!mounted || _dismissQueued) return;
    _dismissQueued = true;
    final hadSecret = _nsec != null;
    if (hadSecret) setState(() => _nsec = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final nsec = _nsec;
    return PopScope(
      canPop: nsec == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearAndDismiss();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BBText(
              context.loc.settingsNostrKeysShowPrivate,
              style: context.font.titleSmall,
              color: context.appColors.onSurface,
            ),
            const Gap(16),
            if (nsec == null)
              const SizedBox.square(
                dimension: 32,
                child: CircularProgressIndicator(),
              )
            else
              // Same presentation as the npub row — truncated value, tap for
              // the full value, and a QR — so a key's secret and public forms
              // are read the same way. The difference is the warning gate in
              // front of this dialog and the privacy/clear-on-exit rules above,
              // not a different-looking widget.
              ExcludeSemantics(
                child: AddressViewer(
                  nsec,
                  qrData: nsec,
                  showExplorerActions: false,
                ),
              ),
            const Gap(24),
            if (nsec != null) ...[
              BBButton.big(
                label: context.loc.settingsNostrKeysCopy,
                iconData: Icons.copy,
                iconFirst: true,
                onPressed: _copy,
                bgColor: context.appColors.primary,
                textColor: context.appColors.onPrimary,
              ),
              const Gap(12),
            ],
            BBButton.big(
              label: MaterialLocalizations.of(context).closeButtonLabel,
              onPressed: _clearAndDismiss,
              outlined: true,
              bgColor: context.appColors.transparent,
              textColor: context.appColors.onSurface,
              borderColor: context.appColors.outline,
            ),
          ],
        ),
      ),
    );
  }
}
