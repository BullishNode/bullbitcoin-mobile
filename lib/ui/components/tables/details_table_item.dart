import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';

class DetailsTableItem extends StatefulWidget {
  const DetailsTableItem({
    super.key,
    required this.label,
    required this.displayValue,
    this.copyValue,
    this.isUnderline = false,
    this.expandableChild,
  });

  final String label;
  final String displayValue;
  final String? copyValue;
  final bool isUnderline;
  final Widget? expandableChild;

  @override
  State<DetailsTableItem> createState() => _DetailsTableItemState();
}

class _DetailsTableItemState extends State<DetailsTableItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              // Label
              Expanded(
                flex: 2,
                child: Text(
                  widget.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.surfaceContainer,
                  ),
                ),
              ),

              // Value + copy icon + expand icon
              Expanded(
                flex: 3,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        widget.displayValue,
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.clip,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.outlineVariant,
                          decoration:
                              widget.isUnderline
                                  ? TextDecoration.underline
                                  : TextDecoration.none,
                        ),
                      ),
                    ),
                    const Gap(8),
                    if (widget.copyValue != null &&
                        widget.copyValue!.isNotEmpty)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          splashColor: theme.colorScheme.primary.withAlpha(30),
                          onTap: () {
                            Clipboard.setData(
                              ClipboardData(text: widget.copyValue!),
                            );
                          },
                          child: Icon(
                            Icons.copy_outlined,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    if (widget.expandableChild != null) ...[
                      const Gap(8),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _expanded = !_expanded;
                            });
                          },
                          child: Icon(
                            _expanded ? Icons.expand_less : Icons.expand_more,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_expanded && widget.expandableChild != null)
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
            child: widget.expandableChild,
          ),
      ],
    );
  }
}
