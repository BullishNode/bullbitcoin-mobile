import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:flutter/material.dart';

/// One wallet's two behavior switches — auto-sweep and hide-on-home — with the
/// rule that couples them stated on the switch it restricts.
///
/// [resolveWalletBehaviorChange] refuses to persist a hidden wallet that keeps
/// its funds, so every surface offering these switches renders them through this
/// widget: hiding is not offered while auto-sweep is off, and it says what it
/// depends on instead of accepting a tap the store will drop and letting the
/// value snap back on the next reload. Unhiding is always offered, so a wallet
/// left hidden by older data can still be brought back.
///
/// It is presentational: the caller owns the writes and supplies the labels its
/// surface uses, but never the refusal copy — that stays in one place.
class WalletBehaviorSwitches extends StatelessWidget {
  const WalletBehaviorSwitches({
    super.key,
    required this.hideOnHome,
    required this.autoSweepEnabled,
    required this.canHideOnHome,
    required this.saving,
    required this.autoSweepLabel,
    required this.hideOnHomeLabel,
    required this.onAutoSweepChanged,
    required this.onHideOnHomeChanged,
    this.autoSweepInfo,
    this.hideOnHomeInfo,
    this.autoSweepSwitchKey,
    this.hideOnHomeSwitchKey,
  });

  final bool hideOnHome;
  final bool autoSweepEnabled;

  /// Whether hiding is currently available — the wallet's own reading of the
  /// coupling rule.
  final bool canHideOnHome;

  /// True while a behavior write is in flight — both switches are inert.
  final bool saving;

  final String autoSweepLabel;
  final String hideOnHomeLabel;
  final String? autoSweepInfo;

  /// Shown under the hide switch while hiding is available; the rule's own
  /// explanation takes its place when it is not.
  final String? hideOnHomeInfo;

  final Key? autoSweepSwitchKey;
  final Key? hideOnHomeSwitchKey;

  final ValueChanged<bool> onAutoSweepChanged;
  final ValueChanged<bool> onHideOnHomeChanged;

  @override
  Widget build(BuildContext context) {
    final autoSweepInfo = this.autoSweepInfo;
    final hideOnHomeSubtitle = canHideOnHome
        ? hideOnHomeInfo
        : context.loc.getPaidWalletHideOnHomeNeedsAutoSweep;
    return Column(
      children: [
        SwitchListTile(
          key: autoSweepSwitchKey,
          value: autoSweepEnabled,
          onChanged: saving ? null : onAutoSweepChanged,
          title: Text(autoSweepLabel),
          subtitle: autoSweepInfo == null ? null : Text(autoSweepInfo),
        ),
        SwitchListTile(
          key: hideOnHomeSwitchKey,
          value: hideOnHome,
          onChanged: saving || !(canHideOnHome || hideOnHome)
              ? null
              : onHideOnHomeChanged,
          title: Text(hideOnHomeLabel),
          subtitle: hideOnHomeSubtitle == null
              ? null
              : Text(hideOnHomeSubtitle),
        ),
      ],
    );
  }
}
