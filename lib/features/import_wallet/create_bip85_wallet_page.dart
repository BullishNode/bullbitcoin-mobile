import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/core/widgets/buttons/button.dart';
import 'package:bb_mobile/core/widgets/snackbar_utils.dart';
import 'package:bb_mobile/core/widgets/text/text.dart';
import 'package:bb_mobile/features/import_wallet/create_bip85_wallet_cubit.dart';
import 'package:bb_mobile/features/import_wallet/create_bip85_wallet_state.dart';
import 'package:bb_mobile/features/wallet_manifest/public/create_manual_bip85_wallets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

class CreateBip85WalletPage extends StatefulWidget {
  const CreateBip85WalletPage({super.key});

  @override
  State<CreateBip85WalletPage> createState() => _CreateBip85WalletPageState();
}

class _CreateBip85WalletPageState extends State<CreateBip85WalletPage> {
  final _formKey = GlobalKey<FormState>();
  final _bitcoinLabelController = TextEditingController();
  final _liquidLabelController = TextEditingController();
  final _indexController = TextEditingController();

  ManualBip85WalletNetworkSelection _networkSelection =
      ManualBip85WalletNetworkSelection.liquid;
  bool _selectIndexManually = false;

  @override
  void dispose() {
    _bitcoinLabelController.dispose();
    _liquidLabelController.dispose();
    _indexController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showBitcoin =
        _networkSelection == ManualBip85WalletNetworkSelection.bitcoin ||
        _networkSelection == ManualBip85WalletNetworkSelection.both;
    final showLiquid =
        _networkSelection == ManualBip85WalletNetworkSelection.liquid ||
        _networkSelection == ManualBip85WalletNetworkSelection.both;

    return BlocConsumer<CreateBip85WalletCubit, CreateBip85WalletState>(
      listener: (context, state) {
        if (state.succeeded && state.result != null) {
          _handleSuccess(context, state.result!);
        } else if (state.failed) {
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
              context.loc.importWalletCreateManualBip85OperationInProgress,
            );
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(context.loc.importWalletCreateManualBip85Title),
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      BBText(
                        context.loc.importWalletCreateManualBip85Description,
                        style: context.font.bodyMedium?.copyWith(
                          color: context.appColors.textMuted,
                        ),
                      ),
                      const Gap(24),
                      BBText(
                        context.loc.importWalletCreateManualBip85NetworkLabel,
                        style: context.font.titleMedium,
                      ),
                      const Gap(8),
                      DropdownButtonFormField<
                        ManualBip85WalletNetworkSelection
                      >(
                        initialValue: _networkSelection,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: ManualBip85WalletNetworkSelection.liquid,
                            child: Text(
                              context.loc.importWalletCreateManualBip85Liquid,
                            ),
                          ),
                          DropdownMenuItem(
                            value: ManualBip85WalletNetworkSelection.bitcoin,
                            child: Text(
                              context.loc.importWalletCreateManualBip85Bitcoin,
                            ),
                          ),
                          DropdownMenuItem(
                            value: ManualBip85WalletNetworkSelection.both,
                            child: Text(
                              context.loc.importWalletCreateManualBip85Both,
                            ),
                          ),
                        ],
                        onChanged: state.isSubmitting
                            ? null
                            : (selection) {
                                if (selection == null) return;
                                setState(() => _networkSelection = selection);
                              },
                      ),
                      const Gap(24),
                      if (showBitcoin) ...[
                        _WalletLabelField(
                          controller: _bitcoinLabelController,
                          label: context
                              .loc
                              .importWalletCreateManualBip85BitcoinLabel,
                          enabled: !state.isSubmitting,
                        ),
                        const Gap(16),
                      ],
                      if (showLiquid) ...[
                        _WalletLabelField(
                          controller: _liquidLabelController,
                          label: context
                              .loc
                              .importWalletCreateManualBip85LiquidLabel,
                          enabled: !state.isSubmitting,
                        ),
                        const Gap(16),
                      ],
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _selectIndexManually,
                        title: Text(
                          context.loc.importWalletCreateManualBip85SelectIndex,
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: state.isSubmitting
                            ? null
                            : (value) {
                                setState(() {
                                  _selectIndexManually = value ?? false;
                                  if (!_selectIndexManually) {
                                    _indexController.clear();
                                  }
                                });
                              },
                      ),
                      if (_selectIndexManually) ...[
                        const Gap(8),
                        TextFormField(
                          controller: _indexController,
                          enabled: !state.isSubmitting,
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            labelText:
                                context.loc.importWalletCreateManualBip85Index,
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            final parsed = int.tryParse(value?.trim() ?? '');
                            if (parsed == null) {
                              return context
                                  .loc
                                  .importWalletCreateManualBip85InvalidIndex;
                            }
                            if (parsed < 0) {
                              return context
                                  .loc
                                  .importWalletCreateManualBip85IndexMin;
                            }
                            return null;
                          },
                        ),
                      ],
                      const Gap(32),
                      BBButton.big(
                        label: state.isSubmitting
                            ? context.loc.importWalletCreateManualBip85Creating
                            : context.loc.importWalletCreateManualBip85Submit,
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

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    context.read<CreateBip85WalletCubit>().submit(
      CreateManualBip85WalletsCommand(
        networkSelection: _networkSelection,
        index: _selectIndexManually
            ? int.parse(_indexController.text.trim())
            : null,
        bitcoinLabel: _bitcoinLabelController.text,
        liquidLabel: _liquidLabelController.text,
      ),
    );
  }

  Future<void> _handleSuccess(
    BuildContext context,
    CreateManualBip85WalletsResult result,
  ) async {
    final message = _successMessage(context, result);
    if (result.partialFailure || result.manifestPublishFailed) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(dialogContext.loc.importWalletCreateManualBip85Title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                MaterialLocalizations.of(dialogContext).okButtonLabel,
              ),
            ),
          ],
        ),
      );
      if (!context.mounted) return;
      context.pop(true);
      return;
    }

    SnackBarUtils.showSnackBar(context, message);
    context.pop(true);
  }

  String _successMessage(
    BuildContext context,
    CreateManualBip85WalletsResult result,
  ) {
    final partialWarning = result.partialFailure
        ? ' ${context.loc.importWalletCreateManualBip85PartialWarning}'
        : '';
    final publishWarning = result.manifestPublishFailed
        ? ' ${context.loc.importWalletCreateManualBip85ManifestWarning}'
        : '';
    return context.loc.importWalletCreateManualBip85Success(
      result.wallets.length,
      result.index,
      partialWarning,
      publishWarning,
    );
  }

  String _errorMessage(BuildContext context, CreateBip85WalletState state) {
    return switch (state.failure) {
      CreateManualBip85WalletsFailure.labelRequired =>
        context.loc.importWalletCreateManualBip85LabelRequired,
      CreateManualBip85WalletsFailure.reservedLabel =>
        context.loc.importWalletCreateManualBip85ReservedLabel,
      CreateManualBip85WalletsFailure.invalidIndex =>
        context.loc.importWalletCreateManualBip85InvalidBip85Index,
      CreateManualBip85WalletsFailure.indexUnavailable =>
        context.loc.importWalletCreateManualBip85IndexUnavailable,
      CreateManualBip85WalletsFailure.walletCreation =>
        context.loc.importWalletCreateManualBip85CreationFailed,
      _ => context.loc.importWalletCreateManualBip85CreationFailed,
    };
  }
}

class _WalletLabelField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool enabled;

  const _WalletLabelField({
    required this.controller,
    required this.label,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: label,
      ),
      textInputAction: TextInputAction.next,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return context.loc.importWalletCreateManualBip85LabelRequired;
        }
        return null;
      },
    );
  }
}
