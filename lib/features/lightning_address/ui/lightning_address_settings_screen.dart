import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/features/lightning_address/presentation/lightning_address_cubit.dart';
import 'package:bb_mobile/features/lightning_address/presentation/lightning_address_state.dart';
import 'package:bb_mobile/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';

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
          Icon(
            Icons.bolt,
            color: context.appColors.success,
            size: 64,
          ),
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
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
                      Icon(
                        Icons.copy,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
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
                  : () => context.read<LightningAddressCubit>().deleteAddress(),
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

class _RegistrationView extends StatelessWidget {
  final TextEditingController controller;
  final bool registering;
  final String? error;
  final VoidCallback onRegister;

  const _RegistrationView({
    required this.controller,
    required this.registering,
    required this.error,
    required this.onRegister,
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
