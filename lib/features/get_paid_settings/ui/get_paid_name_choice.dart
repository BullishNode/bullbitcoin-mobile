import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/core/widgets/buttons/button.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

/// The explicit nym-versus-alias choice a surface offers while no alias has been
/// claimed: reuse the already-claimed nym, or claim one permanent alias.
///
/// Shared by the Donation Page and Point of Sale so the wording, ordering, and
/// affordances stay identical; only [body] differs, because it names the product.
class GetPaidNameChoice extends StatelessWidget {
  final String nym;
  final String body;
  final VoidCallback onUseNym;
  final VoidCallback onChooseAlias;

  const GetPaidNameChoice({
    super.key,
    required this.nym,
    required this.body,
    required this.onUseNym,
    required this.onChooseAlias,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.loc.getPaidNameChoiceTitle(nym),
            style: context.font.titleMedium,
          ),
          const Gap(8),
          Text(
            body,
            style: context.font.bodyMedium?.copyWith(
              color: context.appColors.textMuted,
            ),
          ),
          const Gap(16),
          BBButton.big(
            key: const Key('get_paid_use_my_nym'),
            label: context.loc.getPaidNameChoiceUseNym,
            onPressed: onUseNym,
            bgColor: context.appColors.secondary,
            textColor: context.appColors.onSecondary,
          ),
          const Gap(8),
          TextButton(
            key: const Key('get_paid_choose_an_alias'),
            onPressed: onChooseAlias,
            child: Text(context.loc.getPaidNameChoiceChooseAlias),
          ),
        ],
      ),
    );
  }
}
