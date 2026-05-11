import 'package:flutter/material.dart';

class GetPaidSlotCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback? onPressed;

  const GetPaidSlotCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 4, color: theme.colorScheme.primary),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: theme.textTheme.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: theme.textTheme.bodyMedium,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: onPressed,
                        child: Text(actionLabel),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
