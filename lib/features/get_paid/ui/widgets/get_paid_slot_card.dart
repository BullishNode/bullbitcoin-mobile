import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

class GetPaidSlotCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? statusLabel;
  final bool statusActive;
  final VoidCallback? onPressed;

  const GetPaidSlotCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.statusLabel,
    this.statusActive = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.58,
      child: Semantics(
        button: true,
        enabled: enabled,
        child: Material(
          color: context.appColors.surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: context.appColors.border),
            borderRadius: BorderRadius.circular(2),
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(2),
            child: DecoratedBox(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: context.appColors.border,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        icon,
                        color: context.appColors.primary,
                        size: 32,
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: context.font.headlineMedium),
                          const Gap(8),
                          Text(
                            subtitle,
                            style: context.font.bodySmall?.copyWith(
                              color: context.appColors.textMuted,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (statusLabel != null) ...[
                            const Gap(10),
                            _StatusIndicator(
                              label: statusLabel!,
                              active: statusActive,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (enabled) ...[
                      const Gap(12),
                      Icon(
                        Icons.arrow_forward,
                        color: context.appColors.onSurface,
                        size: 24,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  final String label;
  final bool active;

  const _StatusIndicator({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? context.appColors.success
                : context.appColors.textMuted,
          ),
        ),
        const Gap(8),
        Text(
          label,
          style: context.font.bodySmall?.copyWith(
            color: context.appColors.onSurface,
          ),
        ),
      ],
    );
  }
}
