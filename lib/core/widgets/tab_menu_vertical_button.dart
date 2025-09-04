import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/widgets/text/text.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

class TabMenuVerticalButton extends StatelessWidget {
  final Widget? icon;
  final String title;
  final VoidCallback? onTap;

  const TabMenuVerticalButton({
    super.key,
    this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:
            onTap != null ? context.colour.onSecondary : context.colour.surface,
        borderRadius: BorderRadius.circular(2.76),
        border: Border.all(color: context.colour.surface, width: 0.69),
        boxShadow: [
          BoxShadow(color: context.colour.surface, offset: const Offset(0, 2)),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(2.76),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              if (icon != null) icon!,
              const Gap(8),
              BBText(title, style: context.font.headlineLarge),
            ],
          ),
        ),
      ),
    );
  }
}
