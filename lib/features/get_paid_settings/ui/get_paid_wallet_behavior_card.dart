import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:flutter/material.dart';

/// The reserved product wallet's two behavior switches — auto-sweep and
/// hide-on-home — as one card.
///
/// Every Get Paid surface shows exactly this card, whether inside the Advanced
/// Settings sheet or inline on a screen whose online product is unavailable, so
/// the labels, the ordering and the rule coupling the two switches are stated in
/// one place. It is presentational: the caller owns the writes.
class GetPaidWalletBehaviorCard extends StatelessWidget {
  const GetPaidWalletBehaviorCard({
    super.key,
    required this.behavior,
    required this.saving,
    required this.onAutoSweepChanged,
    required this.onHideOnHomeChanged,
  });

  final GetPaidWalletBehavior behavior;

  /// True while a behavior write is in flight — both switches are inert.
  final bool saving;

  final ValueChanged<bool> onAutoSweepChanged;
  final ValueChanged<bool> onHideOnHomeChanged;

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    return Card(
      margin: const EdgeInsets.only(top: 24),
      child: Column(
        children: [
          ListTile(title: Text(loc.getPaidWalletSettingsSectionTitle)),
          SwitchListTile(
            key: const Key('get_paid_auto_sweep_switch'),
            value: behavior.autoSweepEnabled,
            onChanged: saving ? null : onAutoSweepChanged,
            title: Text(loc.getPaidWalletAutoSweepLabel),
            subtitle: Text(loc.getPaidWalletAutoSweepInfo),
          ),
          SwitchListTile(
            key: const Key('get_paid_hide_on_home_switch'),
            value: behavior.hideOnHome,
            // Hiding needs auto-sweep on; unhiding is always allowed, so a
            // wallet left hidden by older data can still be brought back.
            onChanged:
                saving || !(behavior.canHideOnHome || behavior.hideOnHome)
                ? null
                : onHideOnHomeChanged,
            title: Text(loc.getPaidWalletHideOnHomeLabel),
            subtitle: Text(
              behavior.canHideOnHome
                  ? loc.getPaidWalletHideOnHomeInfo
                  : loc.getPaidWalletHideOnHomeNeedsAutoSweep,
            ),
          ),
        ],
      ),
    );
  }
}
