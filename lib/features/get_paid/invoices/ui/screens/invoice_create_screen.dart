import 'dart:convert';

import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/widgets/buttons/button.dart';
import 'package:bb_mobile/core/widgets/inputs/copy_input.dart';
import 'package:bb_mobile/core/widgets/price_input/price_input.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/invoice_constants.dart';
import 'package:bb_mobile/features/get_paid/invoices/presentation/invoice_create_cubit.dart';
import 'package:bb_mobile/features/get_paid/invoices/presentation/invoice_create_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';

class InvoiceCreateScreen extends StatefulWidget {
  final String? paymentPageNym;

  const InvoiceCreateScreen({super.key, this.paymentPageNym});

  @override
  State<InvoiceCreateScreen> createState() => _InvoiceCreateScreenState();
}

class _InvoiceCreateScreenState extends State<InvoiceCreateScreen> {
  static const _satsCurrency = 'sats';

  final _amountController = TextEditingController();
  final _amountFocusNode = FocusNode();
  final _publicDescriptionController = TextEditingController();
  final _recipientNameController = TextEditingController();
  final _invoiceNumberController = TextEditingController();
  final _privateMemoController = TextEditingController();

  bool _linkToPaymentPage = false;
  bool _showDetails = false;
  late final DateTime _expiryReferenceTime;

  @override
  void initState() {
    super.initState();
    _expiryReferenceTime = DateTime.now().toUtc();
    _linkToPaymentPage = widget.paymentPageNym != null;
    _amountController.addListener(_syncAmount);
    final cubit = context.read<InvoiceCreateCubit>();
    cubit.setExpiresAt(_expiresAtForDays(_expiryDaysFrom(cubit.state)));
    if (_linkToPaymentPage) {
      cubit.setLinkToPageNym(widget.paymentPageNym!);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _amountFocusNode.dispose();
    _publicDescriptionController.dispose();
    _recipientNameController.dispose();
    _invoiceNumberController.dispose();
    _privateMemoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InvoiceCreateCubit, InvoiceCreateState>(
      builder: (context, state) {
        return PopScope(
          canPop: !_showDetails && !state.created,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (state.created) {
              Navigator.of(context).pop(true);
              return;
            }
            if (_showDetails) {
              setState(() => _showDetails = false);
            }
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(_showDetails ? 'Invoice details' : 'Create invoice'),
            ),
            body: SafeArea(
              child: state.created
                  ? _InvoiceCreatedView(state: state)
                  : GestureDetector(
                      onTap: FocusScope.of(context).unfocus,
                      behavior: HitTestBehavior.translucent,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (!_showDetails)
                            ..._amountStep(context, state)
                          else
                            ..._detailsStep(context, state),
                        ],
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }

  bool _hasValidAmount(InvoiceCreateState state) {
    final sats = state.amountSat;
    if (sats != null) return sats > 0;
    final fiat = state.fiatAmountMinor;
    if (fiat == null) return false;
    return fiat > 0 && fiat <= invoiceMaxFiatAmountMinor;
  }

  bool _hasRail(InvoiceCreateState state) {
    return state.acceptBtc || state.acceptLn || state.acceptLiquid;
  }

  InputCounterWidgetBuilder _byteCounter(
    TextEditingController controller,
    int maxBytes,
  ) {
    return (context, {required currentLength, required isFocused, maxLength}) {
      final bytes = utf8.encode(controller.text).length;
      return Text(
        '$bytes/$maxBytes bytes',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: bytes > maxBytes ? context.appColors.error : null,
        ),
      );
    };
  }

  List<TextInputFormatter> _byteLimit(int maxBytes) {
    return [_Utf8ByteLimitFormatter(maxBytes)];
  }

  List<Widget> _amountStep(BuildContext context, InvoiceCreateState state) {
    final currency = _selectedCurrency(state);
    return [
      PriceInput(
        currency: currency,
        amountDecimalPlaces: currency == _satsCurrency
            ? null
            : invoiceFiatCurrencyPrecision(currency),
        amountEquivalent: currency == _satsCurrency
            ? 'fiat rate set at creation'
            : 'sats amount set at creation',
        availableCurrencies: [
          BitcoinUnit.sats.code,
          ...invoiceSupportedFiatCurrencies,
        ],
        onCurrencyChanged: state.isBusy
            ? null
            : (currency) {
                _amountController.clear();
                if (currency == _satsCurrency) {
                  context.read<InvoiceCreateCubit>().setAmountSat(null);
                } else {
                  context.read<InvoiceCreateCubit>().setFiatAmount(
                    minor: null,
                    currency: currency,
                  );
                }
              },
        onNoteChanged: null,
        amountController: _amountController,
        focusNode: _amountFocusNode,
        error: state.error,
        readOnly: state.isBusy,
      ),
      const Gap(24),
      BBButton.big(
        label: 'Continue',
        disabled: state.isBusy || !_hasValidAmount(state),
        onPressed: () => setState(() => _showDetails = true),
        bgColor: context.appColors.secondary,
        textColor: context.appColors.onSecondary,
      ),
    ];
  }

  List<Widget> _detailsStep(BuildContext context, InvoiceCreateState state) {
    return [
      _SelectedAmountRow(
        label: _selectedAmountLabel(state),
        onEdit: state.isBusy
            ? null
            : () {
                _setAmountControllerFromState(state);
                context.read<InvoiceCreateCubit>().clearError();
                setState(() => _showDetails = false);
              },
      ),
      const Gap(16),
      if (state.error != null) ...[
        Text(state.error!, style: TextStyle(color: context.appColors.error)),
        const Gap(16),
      ],
      TextField(
        controller: _publicDescriptionController,
        decoration: const InputDecoration(labelText: 'Public description'),
        enabled: !state.isBusy,
        maxLength: invoicePublicDescriptionMaxBytes,
        maxLengthEnforcement: MaxLengthEnforcement.none,
        buildCounter: _byteCounter(
          _publicDescriptionController,
          invoicePublicDescriptionMaxBytes,
        ),
        inputFormatters: _byteLimit(invoicePublicDescriptionMaxBytes),
        maxLines: 3,
        onChanged: context.read<InvoiceCreateCubit>().setPublicDescription,
      ),
      const Gap(12),
      TextField(
        controller: _recipientNameController,
        decoration: const InputDecoration(labelText: 'Recipient'),
        enabled: !state.isBusy,
        maxLength: invoiceRecipientNameMaxBytes,
        maxLengthEnforcement: MaxLengthEnforcement.none,
        buildCounter: _byteCounter(
          _recipientNameController,
          invoiceRecipientNameMaxBytes,
        ),
        inputFormatters: _byteLimit(invoiceRecipientNameMaxBytes),
        onChanged: context.read<InvoiceCreateCubit>().setRecipientName,
      ),
      const Gap(12),
      TextField(
        controller: _invoiceNumberController,
        decoration: const InputDecoration(labelText: 'Invoice #'),
        enabled: !state.isBusy,
        maxLength: invoiceNumberMaxBytes,
        maxLengthEnforcement: MaxLengthEnforcement.none,
        buildCounter: _byteCounter(
          _invoiceNumberController,
          invoiceNumberMaxBytes,
        ),
        inputFormatters: _byteLimit(invoiceNumberMaxBytes),
        onChanged: context.read<InvoiceCreateCubit>().setInvoiceNumber,
      ),
      const Gap(12),
      _ExpirySelector(
        state: state,
        selectedDays: _expiryDaysFrom(state),
        onChanged: (days) {
          context.read<InvoiceCreateCubit>().setExpiresAt(
            _expiresAtForDays(days),
          );
        },
      ),
      const Gap(12),
      SwitchListTile(
        value: state.acceptBtc,
        title: const Text('Bitcoin on-chain'),
        onChanged: state.isBusy
            ? null
            : context.read<InvoiceCreateCubit>().setAcceptBtc,
      ),
      SwitchListTile(
        value: state.acceptLn,
        title: const Text('Lightning'),
        onChanged: state.isBusy
            ? null
            : context.read<InvoiceCreateCubit>().setAcceptLn,
      ),
      SwitchListTile(
        value: state.acceptLiquid,
        title: const Text('Liquid'),
        onChanged: state.isBusy
            ? null
            : context.read<InvoiceCreateCubit>().setAcceptLiquid,
      ),
      if (widget.paymentPageNym != null)
        SwitchListTile(
          value: _linkToPaymentPage,
          title: Text('Link to ${widget.paymentPageNym}'),
          onChanged: state.isBusy
              ? null
              : (value) {
                  setState(() => _linkToPaymentPage = value);
                  context.read<InvoiceCreateCubit>().setLinkToPageNym(
                    value ? widget.paymentPageNym! : '',
                  );
                },
        ),
      const Gap(12),
      TextField(
        controller: _privateMemoController,
        decoration: const InputDecoration(labelText: 'Private memo'),
        enabled: !state.isBusy,
        maxLines: 2,
        onChanged: context.read<InvoiceCreateCubit>().setPrivateMemo,
      ),
      const Gap(24),
      BBButton.big(
        label: state.isSubmitting ? 'Creating...' : 'Create invoice',
        disabled: state.isBusy || !_hasRail(state) || !_hasValidAmount(state),
        onPressed: context.read<InvoiceCreateCubit>().submit,
        bgColor: context.appColors.secondary,
        textColor: context.appColors.onSecondary,
      ),
    ];
  }

  void _syncAmount() {
    final cubit = context.read<InvoiceCreateCubit>();
    final text = _amountController.text.trim();
    final currency = _selectedCurrency(cubit.state);
    if (currency == _satsCurrency) {
      cubit.setAmountSat(text.isEmpty ? null : int.tryParse(text));
      return;
    }
    cubit.setFiatAmount(
      minor: _parseFiatMinor(text, currency),
      currency: currency,
    );
  }

  int? _parseFiatMinor(String value, String currency) {
    if (value.isEmpty) return null;
    final normalized = value.replaceAll(',', '.');
    final parts = normalized.split('.');
    if (parts.length > 2) return null;
    final major = int.tryParse(parts.first);
    if (major == null) return null;
    final centsText = parts.length == 1 ? '' : parts.last;
    final precision = invoiceFiatCurrencyPrecision(currency);
    if (centsText.length > precision) return null;
    final cents = centsText.isEmpty
        ? 0
        : int.tryParse(centsText.padRight(precision, '0'));
    if (cents == null) return null;
    return major * invoiceMajorToMinorUnitFactor(currency) + cents;
  }

  String _selectedCurrency(InvoiceCreateState state) {
    return state.fiatCurrency ?? _satsCurrency;
  }

  void _setAmountControllerFromState(InvoiceCreateState state) {
    final nextText =
        state.amountSat?.toString() ??
        (state.fiatAmountMinor != null && state.fiatCurrency != null
            ? invoiceFiatMinorToMajorString(
                state.fiatAmountMinor!,
                state.fiatCurrency!,
              )
            : '');
    if (_amountController.text == nextText) return;
    _amountController.removeListener(_syncAmount);
    _amountController.text = nextText;
    _amountController.addListener(_syncAmount);
  }

  String _selectedAmountLabel(InvoiceCreateState state) {
    if (state.amountSat != null) return '${state.amountSat} sats';
    final fiatAmount = state.fiatAmountMinor;
    final fiatCurrency = state.fiatCurrency;
    if (fiatAmount != null && fiatCurrency != null) {
      return '${invoiceFiatMinorToMajorString(fiatAmount, fiatCurrency)} $fiatCurrency';
    }
    return 'No amount';
  }

  int _expiryDaysFrom(InvoiceCreateState state) {
    final remaining = state.expiresAt.difference(_expiryReferenceTime);
    if (remaining <= Duration.zero) return 1;
    return (remaining.inSeconds / Duration.secondsPerDay)
        .ceil()
        .clamp(1, 7)
        .toInt();
  }

  DateTime _expiresAtForDays(int days) {
    return _expiryReferenceTime.add(Duration(days: days));
  }
}

class _SelectedAmountRow extends StatelessWidget {
  final String label;
  final VoidCallback? onEdit;

  const _SelectedAmountRow({required this.label, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: context.font.headlineSmall)),
        TextButton(onPressed: onEdit, child: const Text('Edit amount')),
      ],
    );
  }
}

class _ExpirySelector extends StatelessWidget {
  final InvoiceCreateState state;
  final int selectedDays;
  final ValueChanged<int> onChanged;

  const _ExpirySelector({
    required this.state,
    required this.selectedDays,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      initialValue: selectedDays,
      decoration: const InputDecoration(labelText: 'Expires in'),
      items: [
        for (var day = 1; day <= 7; day++)
          DropdownMenuItem(
            value: day,
            child: Text('$day day${day == 1 ? '' : 's'}'),
          ),
      ],
      onChanged: state.isBusy
          ? null
          : (days) {
              if (days == null) return;
              onChanged(days);
            },
    );
  }
}

class _InvoiceCreatedView extends StatelessWidget {
  final InvoiceCreateState state;

  const _InvoiceCreatedView({required this.state});

  @override
  Widget build(BuildContext context) {
    final result = state.result!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Invoice created', style: context.font.headlineSmall),
        const Gap(16),
        CopyInput(text: result.shareUrl.value, silent: true),
        const Gap(24),
        BBButton.big(
          label: 'Done',
          onPressed: () => Navigator.of(context).pop(true),
          bgColor: context.appColors.secondary,
          textColor: context.appColors.onSecondary,
        ),
      ],
    );
  }
}

class _Utf8ByteLimitFormatter extends TextInputFormatter {
  final int maxBytes;

  _Utf8ByteLimitFormatter(this.maxBytes);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (utf8.encode(newValue.text).length <= maxBytes) {
      return newValue;
    }
    return oldValue;
  }
}
