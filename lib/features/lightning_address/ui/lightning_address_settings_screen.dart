import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/features/lightning_address/data/datasources/lightning_address_settings_datasource.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:bb_mobile/features/lightning_address/domain/primitives/nostr_publish_status.dart';
import 'package:bb_mobile/features/lightning_address/domain/value_objects/nym_quota.dart';
import 'package:bb_mobile/features/lightning_address/domain/value_objects/previous_nym.dart';
import 'package:bb_mobile/features/lightning_address/presentation/lightning_address_cubit.dart';
import 'package:bb_mobile/features/lightning_address/presentation/lightning_address_state.dart';
import 'package:bb_mobile/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:bb_mobile/generated/flutter_gen/assets.gen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:get_it/get_it.dart';
import 'package:gif/gif.dart';

class LightningAddressSettingsScreen extends StatefulWidget {
  const LightningAddressSettingsScreen({super.key});

  @override
  State<LightningAddressSettingsScreen> createState() =>
      _LightningAddressSettingsScreenState();
}

class _LightningAddressSettingsScreenState
    extends State<LightningAddressSettingsScreen> {
  final _nymController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final env =
        context.read<SettingsCubit>().state.environment ?? Environment.mainnet;
    context.read<LightningAddressCubit>().checkStatus(env);
  }

  @override
  void dispose() {
    _nymController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.loc.lightningAddressTitle)),
      body: SafeArea(
        child: BlocBuilder<LightningAddressCubit, LightningAddressState>(
          builder: (context, state) {
            if (state.loading) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Gif(
                      autostart: Autostart.loop,
                      height: 123,
                      image: AssetImage(Assets.animations.cubesLoading.path),
                    ),
                    const Gap(24),
                    Text(
                      context.loc.lightningAddressLoading,
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }
            // Heavy "Creating your Nostr identity" loader is only relevant
            // the first time — it covers the slow path that runs the BIP85
            // derivation and persists the LA wallet. On re-register the
            // wallet already exists; the inline button spinner in
            // _RegistrationView is the right indicator.
            if (state.registering &&
                state.lightningAddress == null &&
                !state.walletExists) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Gif(
                      autostart: Autostart.loop,
                      height: 123,
                      image: AssetImage(Assets.animations.cubesLoading.path),
                    ),
                    const Gap(24),
                    Text(
                      context.loc.lightningAddressCreating,
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const Gap(8),
                    Text(
                      context.loc.lightningAddressCreatingDesc,
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }
            if (state.lightningAddress != null) {
              return _ActivatedView(
                address: state.lightningAddress!,
                deleting: state.registering,
              );
            }
            return _RegistrationView(
              controller: _nymController,
              registering: state.registering,
              error: state.error,
              previousNyms: state.previousNyms,
              onRegister: (publishOnNostr) {
                final env =
                    context.read<SettingsCubit>().state.environment ??
                        Environment.mainnet;
                context.read<LightningAddressCubit>().registerNym(
                      _nymController.text.trim().toLowerCase(),
                      env,
                      publishOnNostr: publishOnNostr,
                    );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ActivatedView extends StatefulWidget {
  final String address;
  final bool deleting;
  const _ActivatedView({
    required this.address,
    this.deleting = false,
  });

  @override
  State<_ActivatedView> createState() => _ActivatedViewState();
}

class _ActivatedViewState extends State<_ActivatedView> {
  bool _autoSweep = true;
  bool _hideWallet = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = GetIt.I<LightningAddressSettingsDatasource>();
    final autoSweep = await settings.getAutoSweep();
    final hideWallet = await settings.getHideWallet();
    if (mounted) {
      setState(() {
        _autoSweep = autoSweep;
        _hideWallet = hideWallet;
      });
    }
  }

  Future<void> _saveAutoSweep(bool value) async {
    setState(() => _autoSweep = value);
    await GetIt.I<LightningAddressSettingsDatasource>().setAutoSweep(value);
  }

  Future<void> _saveHideWallet(bool value) async {
    setState(() => _hideWallet = value);
    await GetIt.I<LightningAddressSettingsDatasource>().setHideWallet(value);
  }

  void _showHowItWorksSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) => SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  context.loc.lightningAddressHowItWorksTitle,
                  style: theme.textTheme.titleLarge,
                ),
                const Gap(12),
                Text(
                  context.loc.lightningAddressHowItWorksBody,
                  style: theme.textTheme.bodyMedium,
                ),
                const Gap(24),
                Text(
                  context.loc.lightningAddressSecurityTitle,
                  style: theme.textTheme.titleLarge,
                ),
                const Gap(12),
                Text(
                  context.loc.lightningAddressSecurityBody1,
                  style: theme.textTheme.bodyMedium,
                ),
                const Gap(8),
                Text(
                  context.loc.lightningAddressSecurityBold,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Gap(8),
                Text(
                  context.loc.lightningAddressSecurityBody2,
                  style: theme.textTheme.bodyMedium,
                ),
                const Gap(24),
                Text(
                  context.loc.lightningAddressFeesTitle,
                  style: theme.textTheme.titleLarge,
                ),
                const Gap(12),
                Text(
                  context.loc.lightningAddressFeesBody,
                  style: theme.textTheme.bodyMedium,
                ),
                const Gap(24),
                Text(
                  context.loc.lightningAddressPrivacyTitle,
                  style: theme.textTheme.titleLarge,
                ),
                const Gap(12),
                Text(
                  context.loc.lightningAddressPrivacyBody,
                  style: theme.textTheme.bodyMedium,
                ),
                const Gap(32),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Gap(32),
          Icon(Icons.bolt, color: context.appColors.success, size: 64),
          const Gap(16),
          Text(
            context.loc.lightningAddressActive,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const Gap(24),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: widget.address));
            },
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              decoration: BoxDecoration(
                color: context.appColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: context.appColors.success.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    widget.address,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const Gap(12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.copy,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant),
                      const Gap(4),
                      Text(
                        context.loc.lightningAddressTapToCopy,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Gap(24),
          GestureDetector(
            onTap: () => _showHowItWorksSheet(context),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const Gap(6),
                Text(
                  context.loc.lightningAddressHowItWorksLink,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    decoration: TextDecoration.underline,
                    decorationColor: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const Gap(16),
          switch (context.watch<LightningAddressCubit>().state.nostrPublishStatus) {
            NostrPublishStatus.pending => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const Gap(8),
                  Text(
                    context.loc.lightningAddressNostrPublishing,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            NostrPublishStatus.success => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 16,
                    color: context.appColors.success,
                  ),
                  const Gap(8),
                  Text(
                    context.loc.lightningAddressNostrPublished,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            NostrPublishStatus.failed => SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () =>
                      context.read<LightningAddressCubit>().republishOnNostr(),
                  child: Text(
                    context.loc.lightningAddressNostrRepublish,
                    style: TextStyle(color: context.appColors.warning),
                  ),
                ),
              ),
            NostrPublishStatus.none => const SizedBox.shrink(),
          },
          const Gap(32),
          _OptionTile(
            title: context.loc.lightningAddressAutoSweep,
            subtitle: context.loc.lightningAddressAutoSweepSub,
            value: _autoSweep,
            onChanged: _saveAutoSweep,
            onInfoTap: () => _showBottomSheet(
              context,
              context.loc.lightningAddressAutoSweep,
              context.loc.lightningAddressAutoSweepInfo,
            ),
          ),
          const Gap(16),
          _OptionTile(
            title: context.loc.lightningAddressHideWallet,
            subtitle: context.loc.lightningAddressHideWalletSub,
            value: _hideWallet,
            onChanged: _saveHideWallet,
            onInfoTap: () => _showBottomSheet(
              context,
              context.loc.lightningAddressHideWallet,
              context.loc.lightningAddressHideWalletInfo,
            ),
          ),
          const Gap(32),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: widget.deleting
                  ? null
                  : () async {
                      final quotaState = context
                          .read<LightningAddressCubit>()
                          .state
                          .quota
                          ?.state();
                      final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(context.loc.lightningAddressDeactivateTitle),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.loc.lightningAddressDeactivateBody(widget.address),
                                  ),
                                  if (quotaState case QuotaState.lastSlot ||
                                      QuotaState.exhausted) ...[
                                    const Gap(12),
                                    Text(
                                      switch (quotaState) {
                                        QuotaState.lastSlot => context.loc
                                            .lightningAddressDeactivateLastSlotWarning,
                                        QuotaState.exhausted => context.loc
                                            .lightningAddressDeactivateExhaustedWarning,
                                        _ => '',
                                      },
                                      style: TextStyle(
                                        color: Theme.of(ctx).colorScheme.error,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(ctx).pop(false),
                                  child: Text(context.loc.lightningAddressDeactivateCancel),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(ctx).pop(true),
                                  child: Text(
                                    context.loc.lightningAddressDeactivateConfirm,
                                    style: TextStyle(
                                      color: Theme.of(ctx).colorScheme.error,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ) ??
                          false;
                      if (confirmed && context.mounted) {
                        context
                            .read<LightningAddressCubit>()
                            .deleteAddress();
                      }
                    },
              child: widget.deleting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      context.loc.lightningAddressDelete,
                      style: TextStyle(color: context.appColors.error),
                    ),
            ),
          ),
          const Gap(16),
        ],
      ),
    );
  }
}

void _showBottomSheet(BuildContext context, String title, String content) {
  showModalBottomSheet(
    context: context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(ctx).textTheme.titleMedium),
          const Gap(16),
          Text(content),
          const Gap(24),
        ],
      ),
    ),
  );
}

class _RegistrationView extends StatefulWidget {
  final TextEditingController controller;
  final bool registering;
  final String? error;
  final List<PreviousNym> previousNyms;
  final ValueChanged<bool> onRegister;

  const _RegistrationView({
    required this.controller,
    required this.registering,
    required this.error,
    required this.onRegister,
    this.previousNyms = const [],
  });

  @override
  State<_RegistrationView> createState() => _RegistrationViewState();
}

class _RegistrationViewState extends State<_RegistrationView> {
  bool _publishOnNostr = true;

  void _submit() => widget.onRegister(_publishOnNostr);

  Future<void> _showPreviousNymsSheet(
    BuildContext context,
    List<PreviousNym> nyms,
  ) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  context.loc.lightningAddressPreviousDetectedTitle,
                  style: theme.textTheme.titleLarge,
                ),
                const Gap(12),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: nyms.length,
                    itemBuilder: (_, i) => ListTile(
                      leading: const Icon(Icons.history),
                      title: Text(
                        '${nyms[i].nym}@$lightningAddressDomain',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(ctx).pop(nyms[i].nym),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null && context.mounted) {
      final env = context.read<SettingsCubit>().state.environment ??
          Environment.mainnet;
      context.read<LightningAddressCubit>().registerNym(selected, env);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Gap(16),
          if (widget.previousNyms.isNotEmpty) ...[
            GestureDetector(
              onTap: () =>
                  _showPreviousNymsSheet(context, widget.previousNyms),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.loc.lightningAddressPreviousDetectedTitle,
                      style: theme.textTheme.titleSmall,
                    ),
                    const Gap(4),
                    Text(
                      context.loc.lightningAddressPreviousDetectedBody,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const Gap(16),
          ],
          Text(
            context.loc.lightningAddressChooseNym,
            style: theme.textTheme.titleLarge,
          ),
          const Gap(24),
          TextField(
            controller: widget.controller,
            enabled: !widget.registering,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9\-]')),
              LengthLimitingTextInputFormatter(32),
            ],
            decoration: InputDecoration(
              hintText: context.loc.lightningAddressNymHint,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (widget.error != null) ...[
            const Gap(12),
            Text(widget.error!,
                style: TextStyle(color: context.appColors.error)),
          ],
          const Gap(8),
          Row(
            children: [
              Expanded(
                child: Text(
                  context.loc.lightningAddressPublishNostrTitle,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              Switch(
                value: _publishOnNostr,
                onChanged: widget.registering
                    ? null
                    : (v) => setState(() => _publishOnNostr = v),
              ),
            ],
          ),
          const Gap(16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: widget.registering ? null : _submit,
              child: widget.registering
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.loc.lightningAddressRegister),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final VoidCallback onInfoTap;

  const _OptionTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.onInfoTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        title: Row(
          children: [
            Expanded(child: Text(title)),
            IconButton(
              icon: const Icon(Icons.info_outline, size: 20),
              onPressed: onInfoTap,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        subtitle: Text(subtitle),
        trailing: Switch(value: value, onChanged: onChanged),
      ),
    );
  }
}
