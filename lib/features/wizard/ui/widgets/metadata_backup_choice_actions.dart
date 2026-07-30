import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bull_ui/bull_ui.dart' show BullButton;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// Backup-specific weighted consent actions.
///
/// Reporting consent deliberately keeps its separate, equal-weight Yes/No
/// control. This choice makes backup opt-in prominent while keeping decline
/// explicit, accessible, and large enough to operate comfortably.
class MetadataBackupChoiceActions extends StatelessWidget {
  const MetadataBackupChoiceActions({
    super.key,
    required this.choice,
    required this.saving,
    required this.onEnable,
    required this.onDecline,
  });

  final bool? choice;
  final bool saving;
  final VoidCallback onEnable;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    if (saving) {
      return SizedBox(
        height: 52,
        child: Center(
          child: Semantics(
            label: context.loc.wizardMetadataBackupSaving,
            liveRegion: true,
            child: const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(),
            ),
          ),
        ),
      );
    }

    final colors = context.appColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          container: true,
          button: true,
          enabled: true,
          focusable: true,
          onTap: onEnable,
          selected: choice == true,
          label: context.loc.wizardMetadataBackupEnable,
          sortKey: OrdinalSortKey(0),
          child: ExcludeSemantics(
            child: SizedBox(
              width: double.infinity,
              child: BullButton.big(
                label: context.loc.wizardMetadataBackupEnable,
                onPressed: onEnable,
                iconData: choice == true ? Icons.check : null,
                bgColor: colors.primary,
                textColor: colors.onPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          container: true,
          button: true,
          enabled: true,
          focusable: true,
          onTap: onDecline,
          selected: choice == false,
          label: context.loc.wizardMetadataBackupDecline,
          sortKey: OrdinalSortKey(1),
          child: ExcludeSemantics(
            child: FractionallySizedBox(
              widthFactor: 0.82,
              child: BullButton.small(
                label: context.loc.wizardMetadataBackupDecline,
                onPressed: onDecline,
                iconData: choice == false ? Icons.check : null,
                bgColor: choice == false ? colors.error : colors.surface,
                textColor: choice == false ? colors.onError : colors.error,
                borderColor: colors.error,
                outlined: choice != false,
                height: 48,
                width: double.infinity,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
