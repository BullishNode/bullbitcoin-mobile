import 'package:bb_mobile/core/exchange/domain/entity/user_summary.dart';
import 'package:bb_mobile/features/exchange/presentation/exchange_cubit.dart';
import 'package:bb_mobile/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:bb_mobile/ui/components/cards/action_card.dart';
import 'package:bb_mobile/ui/components/text/text.dart';
import 'package:bb_mobile/ui/themes/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';

class ExchangeHomeTopSection extends StatelessWidget {
  const ExchangeHomeTopSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final defaultCurrency = context.select(
      (SettingsCubit settings) => settings.state.currencyCode,
    );
    final balances = context.select(
      (ExchangeCubit cubit) =>
          cubit.state.balances.isNotEmpty
              ? cubit.state.balances
              : (defaultCurrency != null
                  ? [UserBalance(amount: 0, currencyCode: defaultCurrency)]
                  : []),
    );
    final balanceTextStyle =
        balances.length > 1
            ? theme.textTheme.displaySmall
            : theme.textTheme.displayMedium;
    return SizedBox(
      height: 264 + 78 + 46,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: Colors.black,
                height: 264 + 78,
                // color: Colors.red,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Gap(46),
                        ...balances.map(
                          (b) => BBText(
                            '${b.amount} ${b.currencyCode}',
                            style: balanceTextStyle?.copyWith(
                              color: theme.colorScheme.onPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // const Gap(40),
            ],
          ),
          const Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 13.0),
              child: ActionCard(),
            ),
          ),
        ],
      ),
    );
  }
}
