import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/widgets/loading/status_screen.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/features/lightning_address/data/datasources/lightning_address_settings_datasource.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:bb_mobile/features/lightning_address/presentation/lightning_address_cubit.dart';
import 'package:bb_mobile/features/lightning_address/presentation/lightning_address_state.dart';
import 'package:bb_mobile/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:get_it/get_it.dart';

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
        child: BlocConsumer<LightningAddressCubit, LightningAddressState>(
          listenWhen: (prev, curr) =>
              // Registration succeeded
              (prev.lightningAddress == null && curr.lightningAddress != null) ||
              // Deactivation succeeded
              (prev.lightningAddress != null &&
                  curr.lightningAddress == null &&
                  !curr.loading),
          listener: (context, state) {
            if (state.lightningAddress != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    context.loc.lightningAddressActivated(
                        state.lightningAddress!),
                  ),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(context.loc.lightningAddressDeactivated),
                ),
              );
            }
          },
          builder: (context, state) {
            if (state.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.registering && state.lightningAddress == null) {
              return StatusScreen(
                title: context.loc.lightningAddressCreating,
                description: context.loc.lightningAddressCreatingDesc,
              );
            }
            if (state.lightningAddress != null) {
              return _ActivatedView(
                address: state.lightningAddress!,
                deleting: state.registering,
              );
            }
            // Pre-fill nym controller if we found a previous registration
            if (state.previousNym != null && _nymController.text.isEmpty) {
              _nymController.text = state.previousNym!;
            }
            return _RegistrationView(
              controller: _nymController,
              registering: state.registering,
              error: state.error,
              previousNym: state.previousNym,
              onRegister: () {
                final env =
                    context.read<SettingsCubit>().state.environment ??
                        Environment.mainnet;
                context.read<LightningAddressCubit>().registerNym(
                      _nymController.text.trim().toLowerCase(),
                      env,
                    );
              },
            );
          },
        ),
      ),
    );
  }
}

// --- Activated view with settings ---

class _ActivatedView extends StatefulWidget {
  final String address;
  final bool deleting;
  const _ActivatedView({required this.address, this.deleting = false});

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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.loc.lightningAddressCopied)),
              );
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
          Text(
            context.loc.lightningAddressReceiveInfo,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
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
                      final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(context.loc.lightningAddressDeactivateTitle),
                              content: Text(
                                context.loc.lightningAddressDeactivateBody(widget.address),
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

// --- Simple registration view ---

class _RegistrationView extends StatelessWidget {
  final TextEditingController controller;
  final bool registering;
  final String? error;
  final String? previousNym;
  final VoidCallback onRegister;

  const _RegistrationView({
    required this.controller,
    required this.registering,
    required this.error,
    required this.onRegister,
    this.previousNym,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Gap(16),
          if (previousNym != null) ...[
            Container(
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
                    context.loc.lightningAddressPreviousFound,
                    style: theme.textTheme.titleSmall,
                  ),
                  const Gap(4),
                  Text(
                    context.loc.lightningAddressPreviousBody(
                      previousNym ?? '', lightningAddressDomain),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
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
            controller: controller,
            enabled: !registering,
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
            onSubmitted: (_) => onRegister(),
          ),
          if (error != null) ...[
            const Gap(12),
            Text(error!, style: TextStyle(color: context.appColors.error)),
          ],
          const Gap(24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: registering ? null : onRegister,
              child: registering
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

// --- Shared option tile ---

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
