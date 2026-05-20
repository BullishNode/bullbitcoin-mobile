import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/widgets/cards/wallet_card.dart';
import 'package:bb_mobile/features/ark/router.dart';
import 'package:bb_mobile/features/external_receive_wallets/public/external_receive_wallets.dart';
import 'package:bb_mobile/features/wallet/presentation/bloc/wallet_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

class WalletCards extends StatelessWidget {
  const WalletCards({
    super.key,
    this.padding,
    this.onTap,
    this.localSignersOnly = false,
    this.fiatCurrency,
  });

  final EdgeInsetsGeometry? padding;
  final bool localSignersOnly;
  final Function(Wallet wallet)? onTap;
  final String? fiatCurrency;

  static List<Wallet> visibleWallets({
    required Iterable<Wallet> wallets,
    required bool localSignersOnly,
    required ExternalReceiveWalletIds externalReceiveWalletIds,
  }) {
    Iterable<Wallet> ws = wallets;
    if (localSignersOnly) ws = ws.where((w) => w.signsLocally);
    ws = ws.where((w) => !externalReceiveWalletIds.isHiddenOnHome(w.id));
    return ws.toList();
  }

  static Color cardDetails(BuildContext context, Wallet wallet) {
    final isTestnet = wallet.isTestnet;
    final isLiquid = wallet.isLiquid;
    final watchOrSignsRemotely = wallet.isWatchOnly || wallet.signsRemotely;

    final watchonlyColor = context.appColors.secondary;

    if (watchOrSignsRemotely && !isTestnet) return watchonlyColor;
    if (watchOrSignsRemotely && isTestnet) return watchonlyColor;

    if (isLiquid) return context.appColors.tertiary;

    if (isTestnet) return context.appColors.onTertiary;
    return context.appColors.onTertiary;
  }

  @override
  Widget build(BuildContext context) {
    final wallets = context.select((WalletBloc bloc) {
      return visibleWallets(
        wallets: bloc.state.wallets,
        localSignersOnly: localSignersOnly,
        externalReceiveWalletIds: bloc.state.externalReceiveWalletIds,
      );
    });
    final syncStatus = context.select(
      (WalletBloc bloc) => bloc.state.syncStatus,
    );

    final arkBalanceSat = context.select(
      (WalletBloc bloc) => bloc.state.arkBalanceSat,
    );
    final isArkWalletSetup = context.select(
      (WalletBloc bloc) => bloc.state.isArkWalletSetup,
    );
    final isArkWalletLoading = context.select(
      (WalletBloc bloc) => bloc.state.isArkWalletLoading,
    );
    final arkWallet = context.select((WalletBloc bloc) => bloc.state.arkWallet);

    return Padding(
      padding: padding ?? const EdgeInsets.all(13.0),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          for (final w in wallets) ...[
            WalletCard(
              tagColor: cardDetails(context, w),
              title: w.displayLabel(context),
              description: w.walletTypeString,
              balanceSat: w.balanceSat.toInt(),
              isSyncing: syncStatus[w.id] ?? false,
              fiatCurrency: fiatCurrency,
              onTap: () => onTap?.call(w),
            ),
            const Gap(8),
          ],
          if (isArkWalletSetup) ...[
            WalletCard(
              tagColor: context.appColors.tertiary,
              title: context.loc.walletArkInstantPayments,
              description: context.loc.walletArkExperimental,
              balanceSat: arkBalanceSat,
              isSyncing: isArkWalletLoading,
              onTap: () {
                if (arkWallet == null) return;
                context.pushNamed(ArkRoute.arkWalletDetail.name);
              },
            ),
            const Gap(8),
          ],
        ],
      ),
    );
  }
}
