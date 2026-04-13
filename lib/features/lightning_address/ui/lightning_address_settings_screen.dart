import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/features/lightning_address/data/datasources/lightning_address_settings_datasource.dart';
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
        child: BlocListener<LightningAddressCubit, LightningAddressState>(
          listenWhen: (prev, curr) =>
              prev.lightningAddress != null &&
              curr.lightningAddress == null &&
              !curr.loading,
          listener: (context, state) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Lightning Address deleted')),
            );
          },
          child: BlocBuilder<LightningAddressCubit, LightningAddressState>(
            builder: (context, state) {
              if (state.loading) {
                return const Center(child: CircularProgressIndicator());
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
              );
            },
          ),
        ),
      ),
    );
  }
}

// --- Activated view ---

Future<bool> _showDeleteConfirmation(
    BuildContext context, String address) async {
  return await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete Lightning Address?'),
          content: Text(
            'People will no longer be able to send funds to $address. '
            'This action cannot be undone — the address cannot be reclaimed by someone else.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                'Delete',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
            ),
          ],
        ),
      ) ??
      false;
}

class _ActivatedView extends StatelessWidget {
  final String address;
  final bool deleting;
  const _ActivatedView({required this.address, this.deleting = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
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
              Clipboard.setData(ClipboardData(text: address));
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
                    address,
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
                        context.loc.lightningAddressCopied,
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
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: deleting
                  ? null
                  : () async {
                      final confirmed =
                          await _showDeleteConfirmation(context, address);
                      if (confirmed && context.mounted) {
                        context
                            .read<LightningAddressCubit>()
                            .deleteAddress();
                      }
                    },
              child: deleting
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

// --- Registration view with options ---

class _RegistrationView extends StatefulWidget {
  final TextEditingController controller;
  final bool registering;
  final String? error;

  const _RegistrationView({
    required this.controller,
    required this.registering,
    required this.error,
  });

  @override
  State<_RegistrationView> createState() => _RegistrationViewState();
}

class _RegistrationViewState extends State<_RegistrationView> {
  bool _showOptions = false;
  bool _autoSweep = true;
  bool _hideWallet = true;
  List<String> _nymHistory = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = GetIt.I<LightningAddressSettingsDatasource>();
    final autoSweep = await settings.getAutoSweep();
    final hideWallet = await settings.getHideWallet();
    final history = await settings.getNymHistory();
    if (mounted) {
      setState(() {
        _autoSweep = autoSweep;
        _hideWallet = hideWallet;
        _nymHistory = history;
      });
    }
  }

  Future<void> _onRegister() async {
    if (_showOptions) {
      // Persist settings and register
      final settings = GetIt.I<LightningAddressSettingsDatasource>();
      await settings.setAutoSweep(_autoSweep);
      await settings.setHideWallet(_hideWallet);

      final nym = widget.controller.text.trim().toLowerCase();
      await settings.addToNymHistory(nym);

      if (!mounted) return;
      final env = context.read<SettingsCubit>().state.environment ??
          Environment.mainnet;
      context.read<LightningAddressCubit>().registerNym(nym, env);
    } else {
      // Show options step
      setState(() => _showOptions = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_showOptions) {
      return _buildOptionsStep(theme);
    }
    return _buildNymEntryStep(theme);
  }

  Widget _buildNymEntryStep(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Gap(16),
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
            onSubmitted: (_) => _onRegister(),
          ),
          if (widget.error != null) ...[
            const Gap(12),
            Text(widget.error!,
                style: TextStyle(color: context.appColors.error)),
          ],
          if (_nymHistory.isNotEmpty) ...[
            const Gap(24),
            Text('Previous addresses',
                style: theme.textTheme.titleSmall),
            const Gap(8),
            ..._nymHistory.map(
              (nym) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('$nym@bullpay.ca',
                    style: theme.textTheme.bodyMedium),
                trailing: TextButton(
                  onPressed: widget.registering
                      ? null
                      : () {
                          widget.controller.text = nym;
                          _onRegister();
                        },
                  child: const Text('Reactivate'),
                ),
              ),
            ),
          ],
          const Gap(24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: widget.registering ? null : _onRegister,
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

  Widget _buildOptionsStep(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Gap(16),
          Text('Settings', style: theme.textTheme.titleLarge),
          const Gap(8),
          Text(
            'Configure your Lightning Address before activating.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Gap(24),
          _OptionTile(
            title: 'Auto-sweep to Instant Payments',
            subtitle: 'Automatically move received funds for privacy',
            value: _autoSweep,
            onChanged: (v) => setState(() => _autoSweep = v),
            onInfoTap: () => _showAutoSweepInfo(context),
          ),
          const Gap(16),
          _OptionTile(
            title: 'Hide wallet on home',
            subtitle: 'Keep home screen clean',
            value: _hideWallet,
            onChanged: (v) => setState(() => _hideWallet = v),
            onInfoTap: () => _showHideWalletInfo(context),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: widget.registering ? null : _onRegister,
              child: widget.registering
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Activate Lightning Address'),
            ),
          ),
          const Gap(8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => setState(() => _showOptions = false),
              child: const Text('Back'),
            ),
          ),
          const Gap(16),
        ],
      ),
    );
  }

  void _showAutoSweepInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Auto-sweep to Instant Payments',
                style: Theme.of(ctx).textTheme.titleMedium),
            const Gap(16),
            const Text(
              'All funds received via your Lightning Address are automatically '
              'sent to your Instant Payments wallet.\n\n'
              'Why? The Lightning Address server knows the public key (xpub) of '
              'your Lightning Address wallet, which means it can see all '
              'transactions in that wallet. Sweeping to your Instant Payments '
              'wallet protects your privacy.\n\n'
              'Downside: You pay a small Liquid Network fee (~20 sats) each '
              'time funds are swept.',
            ),
            const Gap(24),
          ],
        ),
      ),
    );
  }

  void _showHideWalletInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hide Lightning Address wallet',
                style: Theme.of(ctx).textTheme.titleMedium),
            const Gap(16),
            const Text(
              'The Lightning Address wallet is a dedicated wallet used only '
              'for receiving Lightning Address payments. Hiding it keeps your '
              'home screen clean — funds are auto-swept to your Instant '
              'Payments wallet anyway.\n\n'
              'You can always find this wallet in Settings > Wallets.',
            ),
            const Gap(24),
          ],
        ),
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
