import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/wallet/presentation/bloc/wallet_bloc.dart';
import 'package:bb_mobile/features/wallet/ui/wallet_router.dart';
import 'package:bb_mobile/ui/components/cards/wallet_card.dart';
import 'package:bb_mobile/ui/themes/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

class HomeWalletCards extends StatelessWidget {
  const HomeWalletCards({super.key});

  static Color cardDetails(BuildContext context, Wallet wallet) {
    final isTestnet = wallet.isTestnet;
    final isLiquid = wallet.isLiquid;
    final isWatchOnly = wallet.isWatchOnly;

    final watchonlyColor = context.colour.secondary;

    if (isWatchOnly && !isTestnet) return watchonlyColor;
    if (isWatchOnly && isTestnet) return watchonlyColor;

    if (isLiquid) return context.colour.tertiary;

    if (isTestnet) return context.colour.onTertiary;
    return context.colour.onTertiary;
  }

  @override
  Widget build(BuildContext context) {
    final wallets = context.select((WalletBloc bloc) => bloc.state.wallets);
    final isSyncing = context.select((WalletBloc bloc) => bloc.state.isSyncing);

    return Padding(
      padding: const EdgeInsets.all(13.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final w in wallets) ...[
            WalletCard(
              tagColor: cardDetails(context, w),
              title: w.getLabel() ?? '',
              description: w.getWalletTypeString(),
              wallet: w,
              isSyncing: isSyncing,
              onTap: () {
                context.pushNamed(
                  WalletRoute.walletDetail.name,
                  pathParameters: {'walletId': w.id},
                );
              },
            ),
            const Gap(8),
          ],
        ],
      ),
    );
  }
}
