import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/constants.dart';
import 'package:bb_mobile/core/widgets/bottom_sheet/x.dart';
import 'package:bb_mobile/core/widgets/inputs/amount_input_formatter.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

class PriceInput extends StatelessWidget {
  const PriceInput({
    super.key,
    required this.currency,
    this.amountEquivalent,
    this.amountFieldKey,
    required this.availableCurrencies,
    required this.onCurrencyChanged,
    required this.onNoteChanged,
    required this.amountController,
    this.error,
    required this.focusNode,
    this.readOnly = false,
    this.isMax = false,
    this.amountDecimalPlaces,
  });

  final String currency;
  final String? amountEquivalent;
  final Key? amountFieldKey;
  final List<String> availableCurrencies;
  final Function(String)? onCurrencyChanged;
  final Function(String)? onNoteChanged;
  final TextEditingController amountController;
  final String? error;
  final FocusNode? focusNode;
  final bool readOnly;
  final bool isMax;
  final int? amountDecimalPlaces;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          error ?? '',
          style: context.font.bodyLarge?.copyWith(
            color: error != null
                ? context.appColors.error
                : context.appColors.transparent,
          ),
          maxLines: 2,
        ),
        const Gap(8),
        Row(
          mainAxisAlignment: .center,
          children: [
            const Gap(24),
            Flexible(
              child: FittedBox(
                fit: .scaleDown,
                child: Row(
                  mainAxisSize: .min,
                  children: [
                    IntrinsicWidth(
                      child: isMax
                          ? Text(
                              'MAX',
                              style: context.font.displaySmall!.copyWith(
                                fontSize: 36,
                                color: context.appColors.secondary,
                              ),
                            )
                          : TextField(
                              key: amountFieldKey,
                              controller: amountController,
                              focusNode: focusNode,
                              keyboardType:
                                  currency == BitcoinUnit.sats.code ||
                                      amountDecimalPlaces == 0
                                  ? TextInputType.number
                                  : const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                              inputFormatters: [
                                AmountInputFormatter(
                                  currency,
                                  decimalPlaces: amountDecimalPlaces,
                                ),
                              ],
                              showCursor: !readOnly,
                              readOnly: readOnly,
                              cursorColor: context.appColors.outline,
                              cursorOpacityAnimates: true,
                              cursorHeight: 30,
                              style: context.font.displaySmall!.copyWith(
                                fontSize: 36,
                                color: context.appColors.secondary,
                              ),
                              textAlign: .center,
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                isDense: false,
                                hintText:
                                    focusNode != null && focusNode!.hasFocus
                                    ? null
                                    : "0",
                                hintStyle: context.font.displaySmall!.copyWith(
                                  fontSize: 36,
                                  color: context.appColors.secondary,
                                ),
                              ),
                            ),
                    ),
                    const Gap(8),
                    Text(
                      currency,
                      style: context.font.displaySmall?.copyWith(
                        color: context.appColors.secondary,
                      ),
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
            ),
            const Gap(16),
            if (availableCurrencies.isNotEmpty && onCurrencyChanged != null)
              InkWell(
                onTap: () async {
                  final selected = await _openPopup(context, currency);
                  if (selected != null && onCurrencyChanged != null) {
                    onCurrencyChanged!(selected);
                  }
                },
                child: Icon(
                  Icons.arrow_drop_down,
                  color: context.appColors.secondary,
                  size: 40,
                ),
              ),
          ],
        ),
        if (amountEquivalent != null) ...[
          const Gap(14),
          Text(
            '~$amountEquivalent',
            style: context.font.bodyLarge?.copyWith(
              color: context.appColors.onSurfaceVariant,
            ),
          ),
          const Gap(14),
        ] else
          const Gap(14),
        if (onNoteChanged != null)
          Center(
            child: Container(
              height: 50,
              width: 200,
              alignment: Alignment.center,
              child: TextField(
                onChanged: onNoteChanged,
                textAlignVertical: TextAlignVertical.center,
                textAlign: .center,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(2),
                    borderSide: BorderSide.none,
                  ),
                  fillColor: context.appColors.secondaryFixedDim,
                  filled: true,
                  hintText: 'Add note',
                  hintStyle: context.font.labelSmall!.copyWith(
                    color: context.appColors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<String?> _openPopup(BuildContext context, String selected) async {
    final c = await BlurredBottomSheet.show<String?>(
      context: context,
      child: CurrencyBottomSheet(
        availableCurrencies: availableCurrencies,
        selectedValue: selected,
      ),
    );

    return c;
  }
}

class CurrencyBottomSheet extends StatelessWidget {
  const CurrencyBottomSheet({
    super.key,
    required this.availableCurrencies,
    required this.selectedValue,
  });

  final List<String> availableCurrencies;
  final String selectedValue;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Gap(16),
          Row(
            children: [
              const Gap(16 * 3),
              const Spacer(),
              Text(
                'Currency',
                style: context.font.headlineMedium?.copyWith(
                  color: context.appColors.onSurface,
                ),
              ),
              const Spacer(),
              IconButton(
                iconSize: 20,
                onPressed: () => Navigator.pop(context),
                color: context.appColors.onSurface,
                icon: const Icon(Icons.close),
              ),
              const Gap(16),
            ],
          ),
          const Gap(24),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: availableCurrencies.length,
              itemBuilder: (context, index) {
                final curr = availableCurrencies[index];
                return InkWell(
                  onTap: () => Navigator.pop(context, curr),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 24,
                      horizontal: 40,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          child: Text(
                            curr.currencyIcon,
                            style: context.font.headlineSmall,
                          ),
                        ),
                        const Gap(16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                curr.currencyName,
                                style: context.font.headlineSmall?.copyWith(
                                  color: selectedValue == curr
                                      ? context.appColors.primary
                                      : context.appColors.onSurface,
                                ),
                              ),
                              const Gap(2),
                              Text(
                                curr,
                                style: context.font.bodySmall?.copyWith(
                                  color: context.appColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const Gap(24),
        ],
      ),
    );
  }
}

extension _CurrencyStrEx on String {
  String get currencyIcon {
    switch (this) {
      case 'USD':
        return _countryFlag('US');
      case 'EUR':
        return _countryFlag('EU');
      case 'CAD':
        return _countryFlag('CA');
      case 'INR':
        return _countryFlag('IN');
      case 'CRC':
        return _countryFlag('CR');
      case 'MXN':
        return _countryFlag('MX');
      case 'ARS':
        return _countryFlag('AR');
      case 'COP':
        return _countryFlag('CO');
      case 'sats':
      case 'BTC':
      default:
        return '₿';
    }
  }

  String get currencyName {
    switch (this) {
      case 'USD':
        return _countryName('US', fallback: this);
      case 'EUR':
        return _countryName('EU', fallback: this);
      case 'CAD':
        return _countryName('CA', fallback: this);
      case 'CRC':
        return _countryName('CR', fallback: this);
      case 'MXN':
        return _countryName('MX', fallback: this);
      case 'ARS':
        return _countryName('AR', fallback: this);
      case 'COP':
        return _countryName('CO', fallback: this);
      case 'sats':
      case 'BTC':
      default:
        return this;
    }
  }

  String _countryFlag(String code) {
    return _countryValue(code, 'flag') ?? '¤';
  }

  String _countryName(String code, {required String fallback}) {
    return _countryValue(code, 'name') ?? fallback;
  }

  String? _countryValue(String code, String key) {
    final country = CountryConstants.countries.where(
      (element) => element['code'] == code,
    );
    return country.isEmpty ? null : country.first[key];
  }
}
