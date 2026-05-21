import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/core/widgets/buttons/button.dart';
import 'package:bb_mobile/core/widgets/snackbar_utils.dart';
import 'package:bb_mobile/features/get_paid/btcpay/application/prepare_btcpay_pairing_wallets_usecase.dart';
import 'package:bb_mobile/features/get_paid/btcpay/domain/btcpay_connection.dart';
import 'package:bb_mobile/features/get_paid/btcpay/domain/samrock_pairing_request.dart';
import 'package:bb_mobile/features/get_paid/btcpay/presentation/btcpay_pairing_cubit.dart';
import 'package:bb_mobile/features/get_paid/btcpay/presentation/btcpay_pairing_state.dart';
import 'package:bb_mobile/features/get_paid/btcpay/ui/btcpay_pairing_scanner_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

class BtcpayPairingScreen extends StatefulWidget {
  const BtcpayPairingScreen({super.key});

  @override
  State<BtcpayPairingScreen> createState() => _BtcpayPairingScreenState();
}

class _BtcpayPairingScreenState extends State<BtcpayPairingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<BtcpayPairingCubit, BtcpayPairingState>(
      listener: (context, state) {
        if (state.isFailure) {
          SnackBarUtils.showSnackBar(context, _errorMessage(context, state));
        }
      },
      builder: (context, state) {
        return PopScope(
          canPop: !state.isSubmitting && !state.isSuccess,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (state.isSuccess) {
              context.pop(true);
              return;
            }
            if (!state.isSubmitting) return;
            SnackBarUtils.showSnackBar(
              context,
              context.loc.btcpayPairingOperationInProgress,
            );
          },
          child: Scaffold(
            appBar: AppBar(title: Text(context.loc.btcpayPairingTitle)),
            body: SafeArea(
              child: state.isSuccess
                  ? const _BtcpayPairingSuccessView()
                  : state.shouldShowConnection
                  ? _BtcpayConnectionView(connection: state.connection!)
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _urlController,
                              enabled: !state.isSubmitting,
                              keyboardType: TextInputType.url,
                              textInputAction: TextInputAction.done,
                              autocorrect: false,
                              enableSuggestions: false,
                              minLines: 3,
                              maxLines: 5,
                              onFieldSubmitted: (_) =>
                                  state.isSubmitting ? null : _submit(),
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                labelText: context.loc.btcpayPairingUrlLabel,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return context.loc.btcpayPairingUrlRequired;
                                }
                                return null;
                              },
                            ),
                            const Gap(12),
                            BBButton.big(
                              label: context.loc.btcpayPairingScanQr,
                              iconData: Icons.qr_code_scanner,
                              iconFirst: true,
                              onPressed: _scanPairingCode,
                              disabled: state.isSubmitting,
                              bgColor: context.appColors.secondary,
                              textColor: context.appColors.onSecondary,
                            ),
                            const Gap(24),
                            BBButton.big(
                              label: state.isSubmitting
                                  ? context.loc.btcpayPairingSubmitting
                                  : context.loc.btcpayPairingSubmit,
                              onPressed: _submit,
                              disabled: state.isSubmitting,
                              bgColor: context.appColors.primary,
                              textColor: context.appColors.onPrimary,
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final pairingUrl = _urlController.text.trim();
    final SamRockPairingRequest request;
    try {
      request = const SamRockPairingRequestParser().parse(pairingUrl);
    } on SamRockPairingRequestException {
      context.read<BtcpayPairingCubit>().submit(pairingUrl);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: Text(context.loc.btcpayPairingConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.loc.btcpayPairingConfirmBody(
                _walletSummary(context, request),
                _serverUrl(request),
              ),
            ),
            const Gap(12),
            Text(
              _capabilitySummary(context, request),
              style: Theme.of(
                dialogContext,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.loc.btcpayPairingConfirmCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              context.loc.btcpayPairingConfirmSubmit,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    context.read<BtcpayPairingCubit>().submit(pairingUrl);
  }

  Future<void> _scanPairingCode() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const BtcpayPairingScannerScreen(),
      ),
    );
    if (scanned == null || !mounted) return;
    _urlController.text = scanned;
  }

  String _capabilitySummary(
    BuildContext context,
    SamRockPairingRequest request,
  ) {
    final capabilities = <String>[
      if (request.supportsBitcoinChain) context.loc.btcpayPairingRailBitcoin,
      if (request.supportsLiquidChain) context.loc.btcpayPairingRailLiquid,
      if (request.supportsLightning) context.loc.btcpayPairingRailLightning,
    ];
    return context.loc.btcpayPairingConfirmRails(capabilities.join(', '));
  }

  String _walletSummary(BuildContext context, SamRockPairingRequest request) {
    final networks = requestedBtcpayPairingWalletNetworks(request);
    final createsBitcoin = networks.contains(
      BtcpayPairingWalletNetwork.bitcoin,
    );
    final createsLiquid = networks.contains(BtcpayPairingWalletNetwork.liquid);
    if (createsBitcoin && createsLiquid) {
      return context.loc.btcpayPairingWalletsBitcoinAndLiquid;
    }
    if (createsBitcoin) return context.loc.btcpayPairingWalletsBitcoin;
    return context.loc.btcpayPairingWalletsLiquid;
  }

  String _serverUrl(SamRockPairingRequest request) =>
      btcpayServerUrlFor(request);

  String _errorMessage(BuildContext context, BtcpayPairingState state) {
    return switch (state.failure) {
      BtcpayPairingFailure.invalidRequest =>
        context.loc.btcpayPairingInvalidRequestError,
      BtcpayPairingFailure.rejected =>
        state.failureMessage ?? context.loc.btcpayPairingRejectedError,
      _ => context.loc.btcpayPairingGenericError,
    };
  }
}

class _BtcpayConnectionView extends StatelessWidget {
  final BtcpayConnection connection;

  const _BtcpayConnectionView({required this.connection});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(context.loc.btcpayConnectionTitle, style: context.font.titleLarge),
        const Gap(16),
        _BtcpayConnectionRow(
          label: context.loc.btcpayConnectionServer,
          value: connection.serverUrl,
        ),
        const Gap(12),
        _BtcpayConnectionRow(
          label: context.loc.btcpayConnectionRails,
          value: _capabilities(context),
        ),
        const Gap(12),
        _BtcpayConnectionRow(
          label: context.loc.btcpayConnectionWallets,
          value: _wallets(context),
        ),
        const Gap(12),
        _BtcpayConnectionRow(
          label: context.loc.btcpayConnectionPairedAt,
          value: connection.pairedAt.toLocal().toString().substring(0, 16),
        ),
        const Gap(24),
        BBButton.big(
          label: context.loc.btcpayPairNew,
          onPressed: context.read<BtcpayPairingCubit>().pairNew,
          bgColor: context.appColors.secondary,
          textColor: context.appColors.onSecondary,
        ),
      ],
    );
  }

  String _capabilities(BuildContext context) {
    final labels = [
      if (connection.capabilities.contains(SamRockSetupCapability.bitcoinChain))
        context.loc.btcpayPairingRailBitcoin,
      if (connection.capabilities.contains(SamRockSetupCapability.liquidChain))
        context.loc.btcpayPairingRailLiquid,
      if (connection.capabilities.contains(
        SamRockSetupCapability.bitcoinLightning,
      ))
        context.loc.btcpayPairingRailLightning,
    ];
    return labels.join(', ');
  }

  String _wallets(BuildContext context) {
    final createsBitcoin = connection.walletNetworks.contains(
      BtcpayPairingWalletNetwork.bitcoin,
    );
    final createsLiquid = connection.walletNetworks.contains(
      BtcpayPairingWalletNetwork.liquid,
    );
    if (createsBitcoin && createsLiquid) {
      return context.loc.btcpayPairingWalletsBitcoinAndLiquid;
    }
    if (createsBitcoin) return context.loc.btcpayPairingWalletsBitcoin;
    return context.loc.btcpayPairingWalletsLiquid;
  }
}

class _BtcpayConnectionRow extends StatelessWidget {
  final String label;
  final String value;

  const _BtcpayConnectionRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: context.font.bodySmall?.copyWith(
            color: context.appColors.textMuted,
          ),
        ),
        const Gap(4),
        Text(value, style: context.font.bodyMedium),
      ],
    );
  }
}

class _BtcpayPairingSuccessView extends StatelessWidget {
  const _BtcpayPairingSuccessView();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Icon(Icons.check_circle, color: context.appColors.success, size: 72),
          const Gap(24),
          Text(
            context.loc.btcpayPairingSuccessTitle,
            style: context.font.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const Gap(8),
          Text(
            context.loc.btcpayPairingSuccess,
            style: context.font.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          BBButton.big(
            label: context.loc.doneButton,
            onPressed: () => context.pop(true),
            bgColor: context.appColors.secondary,
            textColor: context.appColors.onSecondary,
          ),
        ],
      ),
    );
  }
}
