import 'dart:async';

import 'package:bb_mobile/core/mixins/privacy_screen.dart';
import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/core/widgets/buttons/button.dart';
import 'package:bb_mobile/core/widgets/dialog/blurred_dialog.dart';
import 'package:bb_mobile/core/widgets/qr_display_widget.dart';
import 'package:bb_mobile/core/widgets/snackbar_utils.dart';
import 'package:bb_mobile/core/widgets/text/text.dart';
import 'package:bb_mobile/core/widgets/viewer_action_button.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/reveal_keychain_manifest_nostr_key_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/presentation/nostr_keys_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';

typedef _NsecMaterializer =
    Future<String> Function(KeychainManifestNostrKeyRecord record);

/// Presentation-only capability for showing a verified user nsec.
///
/// The globally registered object can present the sealed dialog, but has no
/// API that returns secret material to its caller.
final class NostrNsecRevealPresenter {
  final _NsecMaterializer _materialize;

  NostrNsecRevealPresenter({
    required RevealKeychainManifestNostrKeyUsecase reveal,
  }) : _materialize = reveal.execute;

  @visibleForTesting
  NostrNsecRevealPresenter.forTesting({required this._materialize});

  Future<void> show(
    BuildContext context, {
    required NostrKeysCubit cubit,
    required KeychainManifestNostrKeyRecord record,
  }) {
    return BlurredDialog.show<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: NostrNsecRevealDialog._(
          record: record,
          materialize: _materialize,
        ),
      ),
    );
  }
}

/// Shows a key's nsec only while this dialog is open.
///
/// The secret is derived only after screenshot protection succeeds. It is held
/// in this widget's state across ordinary rebuilds while the dialog remains
/// open, and cleared on copy, close, disposal, or loss of foreground.
class NostrNsecRevealDialog extends StatefulWidget {
  const NostrNsecRevealDialog._({
    required this.record,
    required this._materialize,
  });

  final KeychainManifestNostrKeyRecord record;
  final _NsecMaterializer _materialize;

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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_protectAndDerive()),
    );
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

  Future<void> _protectAndDerive() async {
    try {
      final protectionEnabled = await enableScreenPrivacy();
      if (!protectionEnabled) {
        if (mounted) context.read<NostrKeysCubit>().reportRevealFailure();
        _clearAndDismiss();
        return;
      }
      if (!mounted || _dismissQueued) {
        // A delayed platform response can arrive after the dialog has already
        // closed or the app has left the foreground. Disposal may have tried
        // to re-enable screenshots before this enable completed, so undo the
        // late enable again and never derive secret material.
        await disableScreenPrivacy();
        return;
      }
      final nsec = await widget._materialize(widget.record);
      if (!mounted || _dismissQueued) return;
      setState(() => _nsec = nsec);
    } on Exception {
      if (mounted) context.read<NostrKeysCubit>().reportRevealFailure();
      _clearAndDismiss();
    }
  }

  Future<void> _copyAndDismiss() async {
    final nsec = _nsec;
    if (nsec == null || _dismissQueued) return;
    await Clipboard.setData(ClipboardData(text: nsec));
    if (!mounted) return;
    SnackBarUtils.showCopiedSnackBar(context);
    _clearAndDismiss();
  }

  void _clearAndDismiss() {
    if (!mounted || _dismissQueued) return;
    _dismissQueued = true;
    _nsec = null;
    Navigator.of(context).pop();
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
        child: SingleChildScrollView(
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
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExcludeSemantics(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          QrDisplayWidget(data: nsec, size: 240),
                          const Gap(16),
                          BBText(
                            _groupSecret(nsec),
                            style: context.font.bodyLarge,
                            color: context.appColors.secondary,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const Gap(24),
                    Semantics(
                      container: true,
                      button: true,
                      label: context.loc.viewerTapToCopy,
                      onTap: _copyAndDismiss,
                      child: ExcludeSemantics(
                        child: ViewerActionButton(
                          key: const Key('nostr_nsec_copy_action'),
                          icon: Icons.copy,
                          label: context.loc.viewerTapToCopy,
                          onTap: _copyAndDismiss,
                        ),
                      ),
                    ),
                  ],
                ),
              const Gap(24),
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
      ),
    );
  }

  static String _groupSecret(String value) {
    final groups = <String>[];
    for (var index = 0; index < value.length; index += 4) {
      final end = index + 4 < value.length ? index + 4 : value.length;
      groups.add(value.substring(index, end));
    }
    return groups.join(' ');
  }
}
