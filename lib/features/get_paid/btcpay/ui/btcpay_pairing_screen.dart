import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/core/widgets/buttons/button.dart';
import 'package:bb_mobile/core/widgets/snackbar_utils.dart';
import 'package:bb_mobile/features/get_paid/btcpay/application/prepare_btcpay_pairing_wallets_usecase.dart';
import 'package:bb_mobile/features/get_paid/btcpay/presentation/btcpay_pairing_cubit.dart';
import 'package:bb_mobile/features/get_paid/btcpay/presentation/btcpay_pairing_state.dart';
import 'package:bb_mobile/features/get_paid/btcpay/domain/samrock_pairing_request.dart';
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
        if (state.isSuccess) {
          SnackBarUtils.showSnackBar(context, context.loc.btcpayPairingSuccess);
          context.pop(true);
        } else if (state.isFailure) {
          SnackBarUtils.showSnackBar(context, _errorMessage(context, state));
        }
      },
      builder: (context, state) {
        return PopScope(
          canPop: !state.isSubmitting,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop || !state.isSubmitting) return;
            SnackBarUtils.showSnackBar(
              context,
              context.loc.btcpayPairingOperationInProgress,
            );
          },
          child: Scaffold(
            appBar: AppBar(title: Text(context.loc.btcpayPairingTitle)),
            body: SafeArea(
              child: SingleChildScrollView(
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

  String _serverUrl(SamRockPairingRequest request) => _serverUrlFor(request);

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

String _serverUrlFor(SamRockPairingRequest request) {
  final uri = request.protocolUri;
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host}$port';
}
