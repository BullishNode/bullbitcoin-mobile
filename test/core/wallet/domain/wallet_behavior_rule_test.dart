import 'package:bb_mobile/core/wallet/domain/wallet_behavior_rule.dart';
import 'package:test/test.dart';

void main() {
  group('hide-on-home is gated by auto-sweep', () {
    test('turning auto-sweep off also unhides the wallet', () {
      final resolved = resolveWalletBehaviorChange(
        hideOnHome: true,
        autoSweepEnabled: true,
        requestedAutoSweepEnabled: false,
      );

      expect(resolved.autoSweepEnabled, isFalse);
      expect(resolved.hideOnHome, isFalse);
    });

    test('hiding is refused while auto-sweep is off', () {
      final resolved = resolveWalletBehaviorChange(
        hideOnHome: false,
        autoSweepEnabled: false,
        requestedHideOnHome: true,
      );

      expect(resolved.hideOnHome, isFalse);
      expect(resolved.autoSweepEnabled, isFalse);
    });

    test('hiding is honored while auto-sweep is on', () {
      final resolved = resolveWalletBehaviorChange(
        hideOnHome: false,
        autoSweepEnabled: true,
        requestedHideOnHome: true,
      );

      expect(resolved.hideOnHome, isTrue);
    });

    test('one call may turn both on', () {
      final resolved = resolveWalletBehaviorChange(
        hideOnHome: false,
        autoSweepEnabled: false,
        requestedHideOnHome: true,
        requestedAutoSweepEnabled: true,
      );

      expect(resolved.hideOnHome, isTrue);
      expect(resolved.autoSweepEnabled, isTrue);
    });

    test('unhiding is always allowed, whatever auto-sweep is', () {
      for (final sweeps in [true, false]) {
        final resolved = resolveWalletBehaviorChange(
          hideOnHome: true,
          autoSweepEnabled: sweeps,
          requestedHideOnHome: false,
        );

        expect(resolved.hideOnHome, isFalse);
        expect(resolved.autoSweepEnabled, sweeps);
      }
    });

    test('a wallet left hidden without sweeping is corrected on any write', () {
      // Data written before the rule existed: hidden while accumulating. The
      // next write of either switch brings it back onto the home list.
      final resolved = resolveWalletBehaviorChange(
        hideOnHome: true,
        autoSweepEnabled: false,
      );

      expect(resolved.hideOnHome, isFalse);
    });

    test('an unrelated write leaves both switches as they are', () {
      final resolved = resolveWalletBehaviorChange(
        hideOnHome: true,
        autoSweepEnabled: true,
      );

      expect(resolved.hideOnHome, isTrue);
      expect(resolved.autoSweepEnabled, isTrue);
    });
  });
}
