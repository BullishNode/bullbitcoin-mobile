import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/get_lightning_address_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/register_lightning_address_usecase.dart';
import 'package:bb_mobile/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:bb_mobile/locator.dart';
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
  bool _loading = true;
  String? _lightningAddress;
  String? _error;
  final _nymController = TextEditingController();
  bool _registering = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  @override
  void dispose() {
    _nymController.dispose();
    super.dispose();
  }

  Environment get _environment =>
      context.read<SettingsCubit>().state.environment ?? Environment.mainnet;

  Future<void> _checkStatus() async {
    try {
      final wallet = await locator<GetLightningAddressWalletUsecase>().execute(
        environment: _environment,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (wallet != null && wallet.label == lightningAddressWalletLabel) {
          // TODO: persist and retrieve the registered nym locally
          // For now we just show the wallet is active
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _register() async {
    final nym = _nymController.text.trim().toLowerCase();
    if (nym.isEmpty) return;

    setState(() {
      _registering = true;
      _error = null;
    });

    try {
      final address =
          await locator<RegisterLightningAddressUsecase>().execute(
        nym: nym,
        environment: _environment,
      );
      if (!mounted) return;
      setState(() {
        _lightningAddress = address;
        _registering = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _registering = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lightning Address')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _lightningAddress != null
                  ? _buildActivatedView(context)
                  : _buildRegistrationView(context),
        ),
      ),
    );
  }

  Widget _buildActivatedView(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_circle, color: context.appColors.success, size: 48),
        const SizedBox(height: 16),
        Text(
          'Lightning Address is active',
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
                  _lightningAddress!,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: _lightningAddress!),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRegistrationView(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose your Lightning Address',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nymController,
          enabled: !_registering,
          autocorrect: false,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9\-]')),
            LengthLimitingTextInputFormatter(32),
          ],
          decoration: InputDecoration(
            suffixText: '@$lightningAddressDomain',
            hintText: 'yourname',
          ),
          onSubmitted: (_) => _register(),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _registering ? null : _register,
            child: _registering
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Activate'),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: context.appColors.error)),
        ],
      ],
    );
  }
}
