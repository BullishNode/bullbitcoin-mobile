import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:bb_mobile/features/lightning_address/presentation/lightning_address_cubit.dart';
import 'package:bb_mobile/features/lightning_address/presentation/lightning_address_state.dart';
import 'package:bb_mobile/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: BlocBuilder<LightningAddressCubit, LightningAddressState>(
            builder: (context, state) {
              if (state.loading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state.lightningAddress != null) {
                return _ActivatedView(address: state.lightningAddress!);
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
      ),
    );
  }
}

class _ActivatedView extends StatelessWidget {
  final String address;
  const _ActivatedView({required this.address});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_circle, color: context.appColors.success, size: 48),
        const SizedBox(height: 16),
        Text(
          context.loc.lightningAddressActive,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.appColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  address,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: address));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.loc.lightningAddressCopied),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.loc.lightningAddressChoose,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: controller,
          enabled: !registering,
          autocorrect: false,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9\-]')),
            LengthLimitingTextInputFormatter(32),
          ],
          decoration: InputDecoration(
            suffixText: '@$lightningAddressDomain',
            hintText: context.loc.lightningAddressHint,
          ),
          onSubmitted: (_) => onRegister(),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: registering ? null : onRegister,
            child: registering
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(context.loc.lightningAddressActivate),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(error!, style: TextStyle(color: context.appColors.error)),
        ],
      ],
    );
  }
}
