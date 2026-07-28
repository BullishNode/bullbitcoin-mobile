import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/core/widgets/address_viewer.dart';
import 'package:bb_mobile/core/widgets/buttons/button.dart';
import 'package:bb_mobile/core/widgets/snackbar_utils.dart';
import 'package:bb_mobile/core/widgets/tables/details_table.dart';
import 'package:bb_mobile/core/widgets/tables/details_table_item.dart';
import 'package:bb_mobile/core/widgets/text/text.dart';
import 'package:bb_mobile/core/widgets/warning_bottom_sheet.dart';
import 'package:bb_mobile/features/keychain_manifest/presentation/nostr_key_l10n.dart';
import 'package:bb_mobile/features/keychain_manifest/presentation/nostr_keys_cubit.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_routes.dart';
import 'package:bb_mobile/features/keychain_manifest/ui/widgets/nostr_nsec_reveal_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

/// One detail page for both key kinds; what differs is what it will show.
///
/// A user key is an identity: its npub is displayed, copyable, and shareable as
/// a QR, and its name and description can be edited. An app-owned key is not an
/// identity: its npub stays hidden behind a warning, it gets no QR, and it
/// offers no edit affordance at all — the domain guard is the backstop for that,
/// not the reason to omit it here.
class NostrKeyDetailScreen extends StatefulWidget {
  const NostrKeyDetailScreen({super.key, required this.record});

  final KeychainManifestNostrKeyRecord record;

  @override
  State<NostrKeyDetailScreen> createState() => _NostrKeyDetailScreenState();
}

class _NostrKeyDetailScreenState extends State<NostrKeyDetailScreen> {
  bool _npubRevealed = false;

  @override
  void initState() {
    super.initState();
    // Reloading gives one source of truth for the row after an edit; the
    // pushed record is only the starting point.
    context.read<NostrKeysCubit>().load();
  }

  /// The freshest stored copy of this key, falling back to the pushed record
  /// while the reload is in flight.
  KeychainManifestNostrKeyRecord _current(NostrKeysState state) {
    for (final key in state.keys) {
      if (key.entryId == widget.record.entryId) return key;
    }
    return widget.record;
  }

  Future<void> _openEdit(KeychainManifestNostrKeyRecord record) async {
    final updated = await context.pushNamed<bool>(
      KeychainManifestRoutes.nostrKeyEditName,
      extra: record,
    );
    if (!mounted || updated != true) return;
    SnackBarUtils.showSnackBar(context, context.loc.settingsNostrKeysUpdated);
  }

  Future<void> _revealNpub() async {
    await WarningBottomSheet.show(
      context,
      title: context.loc.settingsNostrKeysSystemNpubWarningTitle,
      message: context.loc.settingsNostrKeysSystemNpubWarningMessage,
      confirmLabel: context.loc.settingsNostrKeysWarningUnderstand,
      onConfirm: () {
        if (mounted) setState(() => _npubRevealed = true);
      },
    );
  }

  Future<void> _revealNsec(
    KeychainManifestNostrKeyRecord record, {
    required bool isSystem,
  }) async {
    final cubit = context.read<NostrKeysCubit>();
    // WarningBottomSheet runs onConfirm and THEN pops itself, so a route
    // pushed from inside onConfirm becomes the top route and is what that pop
    // closes — the dialog would vanish on the frame it appeared. Record the
    // choice instead, let the sheet finish closing, then present.
    var confirmed = false;
    await WarningBottomSheet.show(
      context,
      title: isSystem
          ? context.loc.settingsNostrKeysSystemNsecWarningTitle
          : context.loc.settingsNostrKeysUserNsecWarningTitle,
      message: isSystem
          ? context.loc.settingsNostrKeysSystemNsecWarningMessage
          : context.loc.settingsNostrKeysUserNsecWarningMessage,
      confirmLabel: context.loc.settingsNostrKeysWarningUnderstand,
      onConfirm: () => confirmed = true,
    );
    if (!confirmed || !mounted) return;
    await NostrNsecRevealDialog.show(context, cubit: cubit, record: record);
  }

  void _showFailure() {
    SnackBarUtils.showSnackBar(context, context.loc.settingsNostrKeysFailure);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<NostrKeysCubit, NostrKeysState>(
      listenWhen: (previous, current) =>
          previous.failureRevision != current.failureRevision,
      listener: (_, _) => _showFailure(),
      child: BlocBuilder<NostrKeysCubit, NostrKeysState>(
        builder: (context, state) {
          final record = _current(state);
          final display = KeychainManifestNostrKeyDisplay.of(record);
          final materialization = record.nostrKeyMaterialization;
          final npub = NostrPublicKeyEncoding.npubFromPublicKeyHex(
            materialization.publicKeyHex,
          );
          // A user key's own words; localized role copy for an app-owned one.
          final descriptionText = record.descriptionText(context);
          return Scaffold(
            appBar: AppBar(
              title: Text(context.loc.settingsNostrKeysDetailTitle),
            ),
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  DetailsTable(
                    items: [
                      DetailsTableItem(
                        label: context.loc.settingsNostrKeysName,
                        displayValue: record.displayName(context),
                      ),
                      if (descriptionText != null)
                        DetailsTableItem(
                          label: context.loc.settingsNostrKeysDescription,
                          displayValue: descriptionText,
                        ),
                      DetailsTableItem(
                        label: context.loc.settingsNostrKeysDerivationPath,
                        displayValue: record.entry.bip85DerivationPath,
                        copyValue: record.entry.bip85DerivationPath,
                      ),
                      _npubItem(
                        context,
                        npub: npub,
                        isSystem: display.isSystem,
                      ),
                    ],
                  ),
                  const Gap(24),
                  if (!display.isSystem)
                    BBButton.big(
                      label: context.loc.settingsNostrKeysEdit,
                      iconData: Icons.edit,
                      iconFirst: true,
                      onPressed: () => _openEdit(record),
                      disabled: state.busy,
                      bgColor: context.appColors.secondary,
                      textColor: context.appColors.onSecondary,
                    ),
                  const Gap(16),
                  BBButton.big(
                    label: context.loc.settingsNostrKeysShowPrivate,
                    iconData: Icons.visibility,
                    iconFirst: true,
                    onPressed: () =>
                        _revealNsec(record, isSystem: display.isSystem),
                    outlined: true,
                    bgColor: context.appColors.transparent,
                    textColor: context.appColors.onSurface,
                    borderColor: context.appColors.outline,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _npubItem(
    BuildContext context, {
    required String npub,
    required bool isSystem,
  }) {
    // A user npub is meant to be shared: tapping it opens the same viewer the
    // app uses for Bitcoin addresses, QR included. A system npub is not, so it
    // stays behind a warning and is never offered as a QR.
    if (!isSystem) {
      return DetailsTableItem(
        label: context.loc.settingsNostrKeysNpub,
        copyValue: npub,
        displayWidget: AddressViewer(
          npub,
          qrData: npub,
          showExplorerActions: false,
        ),
      );
    }
    if (!_npubRevealed) {
      return DetailsTableItem(
        label: context.loc.settingsNostrKeysNpub,
        displayWidget: Align(
          alignment: Alignment.centerRight,
          child: InkWell(
            onTap: _revealNpub,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: BBText(
                context.loc.settingsNostrKeysShowNpub,
                style: context.font.bodyMedium,
                color: context.appColors.primary,
              ),
            ),
          ),
        ),
      );
    }
    return DetailsTableItem(
      label: context.loc.settingsNostrKeysNpub,
      copyValue: npub,
      displayWidget: AddressViewer(npub, showExplorerActions: false),
    );
  }
}
