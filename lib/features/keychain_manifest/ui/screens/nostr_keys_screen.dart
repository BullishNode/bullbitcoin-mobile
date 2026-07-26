import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/core/widgets/settings_entry_item.dart';
import 'package:bb_mobile/core/widgets/snackbar_utils.dart';
import 'package:bb_mobile/core/widgets/text/text.dart';
import 'package:bb_mobile/core/widgets/warning_bottom_sheet.dart';
import 'package:bb_mobile/features/keychain_manifest/presentation/nostr_key_l10n.dart';
import 'package:bb_mobile/features/keychain_manifest/presentation/nostr_keys_cubit.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// The Nostr keys list. Rows carry the key NAME only — no npub, no hex, no
/// path — and open the detail page; everything else about a key lives there.
///
/// App-owned keys are deliberately hard to reach: they are troubleshooting and
/// recovery material, not identities, so they stay collapsed behind a muted
/// footer affordance gated by a warning, and render subdued when revealed.
class NostrKeysScreen extends StatefulWidget {
  const NostrKeysScreen({super.key});

  @override
  State<NostrKeysScreen> createState() => _NostrKeysScreenState();
}

class _NostrKeysScreenState extends State<NostrKeysScreen> {
  @override
  void initState() {
    super.initState();
    context.read<NostrKeysCubit>().load();
  }

  Future<void> _openCreate() async {
    final cubit = context.read<NostrKeysCubit>();
    final created = await context.pushNamed<bool>(
      KeychainManifestRoutes.nostrKeyCreateName,
    );
    await cubit.load();
    if (!mounted || created != true) return;
    SnackBarUtils.showSnackBar(context, context.loc.settingsNostrKeysCreated);
  }

  Future<void> _openDetail(KeychainManifestNostrKeyRecord key) async {
    final cubit = context.read<NostrKeysCubit>();
    await context.pushNamed(
      KeychainManifestRoutes.nostrKeyDetailName,
      extra: key,
    );
    await cubit.load();
  }

  Future<void> _toggleSystemKeys(bool shown) async {
    final cubit = context.read<NostrKeysCubit>();
    if (shown) {
      // Hiding needs no confirmation; only the reveal is gated.
      cubit.setShowSystemKeys(false);
      return;
    }
    await WarningBottomSheet.show(
      context,
      title: context.loc.settingsNostrKeysSystemKeysWarningTitle,
      message: context.loc.settingsNostrKeysSystemKeysWarningMessage,
      confirmLabel: context.loc.settingsNostrKeysWarningUnderstand,
      onConfirm: () => cubit.setShowSystemKeys(true),
    );
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
        builder: (context, state) => Scaffold(
          appBar: AppBar(
            title: Text(context.loc.settingsNostrKeysTitle),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: context.loc.settingsNostrKeysCreate,
                onPressed: state.loading || state.busy ? null : _openCreate,
              ),
            ],
          ),
          body: SafeArea(
            child: state.loading
                ? const Center(child: CircularProgressIndicator())
                : _body(context, state),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, NostrKeysState state) {
    final userKeys = state.userKeys;
    final systemKeys = state.systemKeys;
    return ListView(
      children: [
        if (userKeys.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: BBText(
              context.loc.settingsNostrKeysEmpty,
              style: context.font.bodyMedium,
              color: context.appColors.textMuted,
              textAlign: TextAlign.center,
            ),
          )
        else
          for (final key in userKeys)
            SettingsEntryItem(
              icon: Icons.key,
              title: key.displayName(context),
              onTap: () => _openDetail(key),
            ),
        if (state.showSystemKeys && systemKeys.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              top: 24,
              bottom: 4,
            ),
            child: BBText(
              context.loc.settingsNostrKeysSystemKeysSection,
              style: context.font.labelSmall,
              color: context.appColors.textMuted,
            ),
          ),
          for (final key in systemKeys)
            SettingsEntryItem(
              icon: Icons.settings_suggest,
              title: key.displayName(context),
              iconColor: context.appColors.textMuted,
              textColor: context.appColors.textMuted,
              onTap: () => _openDetail(key),
            ),
        ],
        if (systemKeys.isNotEmpty) _systemKeysToggle(context, state),
      ],
    );
  }

  /// Low-prominence footer affordance, styled after the all-settings footer
  /// rather than a settings row so it never reads as a key.
  Widget _systemKeysToggle(BuildContext context, NostrKeysState state) {
    final label = state.showSystemKeys
        ? context.loc.settingsNostrKeysHideSystemKeys
        : context.loc.settingsNostrKeysShowSystemKeys;
    return Padding(
      padding: const EdgeInsets.only(top: 32, bottom: 24),
      child: Center(
        child: InkWell(
          onTap: () => _toggleSystemKeys(state.showSystemKeys),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: BBText(
              label,
              style: context.font.labelMedium,
              color: context.appColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
