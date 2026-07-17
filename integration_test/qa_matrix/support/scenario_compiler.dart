import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_failure.dart';
import 'package:bb_mobile/features/btcpay/domain/samrock_pairing_request.dart';
import 'package:bb_mobile/features/btcpay/domain/samrock_pairing_service_port.dart';
import 'package:bb_mobile/features/btcpay/domain/usecases/complete_btcpay_samrock_pairing_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/create_default_wallets_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_result.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/public/remote_keychain_recovery_facade.dart';
import 'package:get_it/get_it.dart';
import 'package:qa_matrix_engine/qa_matrix_engine.dart';

import '../../support/fake_bullnym_client.dart';
import '../../support/test_locator_overrides.dart';
import '../../support/wipe_app_state.dart';
import 'matrix_fixtures.dart';

/// Raised when a tuple names a state this in-process build cannot yet stage
/// (e.g. the two-relay `divergent` / `older-populated` cells, which need the E9
/// two-relay harness — or, as of this port, a fault dimension whose old
/// mechanism (a raw Nostr relay double) no longer exists in the product). The
/// runner turns it into a non-fatal [CaseOutcome.blocked] with this reason —
/// distinct from a Fail, per the §12 rich-outcome model.
class ScenarioUnsupported implements Exception {
  const ScenarioUnsupported(this.reason);
  final String reason;
  @override
  String toString() => 'ScenarioUnsupported: $reason';
}

const _pairingUrl =
    'https://btcpay.example.com/plugins/store123/samrock/protocol'
    '?otp=123&setup=btc,lbtc,btcln';

class _FakePairingService implements SamRockPairingServicePort {
  @override
  Future<Result<void, BtcpayFailure>> submitSetup({
    required SamRockPairingRequest request,
    required Map<String, Object?> payload,
  }) async => const Ok(null);
}

/// The staged world for one tuple: the fake seam and the terminal recovery
/// result the run reached, kept together so the invariant assertions can
/// inspect both the outcome and the wire (the Bullnym backup-store calls).
class CompiledScenario {
  CompiledScenario({
    required this.tuple,
    required this.bullnym,
    required this.finalState,
    required this.publishedManifest,
    required this.interrupted,
  });

  final ScenarioTuple tuple;
  final FakeBullnymClient bullnym;
  final RemoteKeychainRecoveryResult finalState;

  /// True when a populated, authentic backup was stored under the correct
  /// seed during staging (so P2 knows a real backup existed).
  final bool publishedManifest;

  /// True when the recovery run was deliberately cut short (D7 interrupt).
  final bool interrupted;
}

/// Compiles a [ScenarioTuple] into a concrete fake configuration, stages the
/// pre-recovery world (wallets + stored backup + fault schedule), then drives
/// the real [RemoteKeychainRecoveryFacade] to its (always-terminal) result
/// (GETPAID-APP-E2E-FAILURE-MATRIX §5.3 steps 4-5). Single-relay S-INJECT
/// only; two-relay cells and relay-transport-level fault cells raise
/// [ScenarioUnsupported].
///
/// PORT NOTE (2026-07-17): re-derived against the current PR #132 tip. The
/// staged, relay-consent-gated `RemoteKeychainRecoveryCubit` this file used to
/// drive is gone — recovery is now one synchronous
/// `RemoteKeychainRecoveryFacade.recover()` call with no disclosure gate, so
/// the old "start, then accept the relay disclosure if offered" two-step
/// collapses to a single call. More significantly, backup I/O no longer runs
/// over a raw Nostr relay the harness can puppet (`FakeNostrRelay` is gone —
/// see the overlay NOTES): both the keychain-manifest and wallet-metadata
/// backup paths now go through `BullnymClientPort` alone, which
/// `FakeBullnymClient` already fakes in full for the happy path plus the
/// server-mode faults below. The D3 (manifest state) and D4 (relay fault)
/// dimensions this file used to drive via the relay double have NO equivalent
/// fault-injection surface on `FakeBullnymClient` today (it has no hook to
/// return tampered/forged/oversize/slow ciphertext from `fetchBackup`), so
/// every cell in those two dimensions is routed to [ScenarioUnsupported]
/// rather than guessed at. Adding that surface is new test-double engineering
/// (candidate WP-DET-INSTR/WP-A3 follow-up), not a mechanical port, and
/// should not be improvised unreviewed on a money-adjacent fake. Flag this
/// whole file for Fable review before it scores anything money-bearing.
class ScenarioCompiler {
  ScenarioCompiler(this.locator);

  final GetIt locator;

  Future<CompiledScenario> compileAndStage(ScenarioTuple tuple) async {
    _rejectUnsupported(tuple);

    final bullnym = FakeBullnymClient();
    _configureBullnym(bullnym, tuple);

    // --- Stage the pre-recovery world under the CORRECT seed --------------
    await wipeAppState(locator);
    await _installBoundaries(bullnym);

    final manifestState = tuple.get(ParameterModel.dManifest);
    final backup = tuple.get(ParameterModel.dBackup);
    final wantManifest =
        manifestState == 'current' && backup.startsWith('on');

    await locator<CreateDefaultWalletsUsecase>().execute(
      mnemonicWords: matrixCorrectMnemonic,
    );
    var published = false;
    if (wantManifest) {
      await locator<GetPaidSettingsFacade>().setAutomatedBackupEnabled(true);
      // Pairing records a keychain-manifest entry and publishes the snapshot —
      // the proven staging path (SPEC-RT-01), so Bullnym holds one populated
      // authentic backup blob for this seed.
      final pairing = await locator<CompleteBtcpaySamRockPairingUsecase>()
          .execute(pairingUrl: _pairingUrl);
      published = pairing is Ok && bullnym.backupStoreCalls.isNotEmpty;
    }

    // --- Apply the D5 network fault schedule that acts at FETCH time ------
    _applyNetwork(bullnym, tuple.get(ParameterModel.dNetwork));

    // --- Simulate a fresh install, then recover ---------------------------
    await wipeAppState(locator);
    final recoverySeed = tuple.get(ParameterModel.dSeed) == 'correct'
        ? matrixCorrectMnemonic
        : matrixWrongMnemonic;
    await locator<CreateDefaultWalletsUsecase>().execute(
      mnemonicWords: recoverySeed,
    );

    final interrupt = tuple.get(ParameterModel.dInterrupt);
    if (interrupt != 'none') {
      // D7 interrupt: this in-process lane has no cubit to cancel mid-flight
      // anymore (recovery is one synchronous call), so an interrupted cell has
      // no staging mechanism today.
      throw const ScenarioUnsupported(
        'interrupt mid-recovery needs a cancellable recovery seam; the '
        'synchronous RemoteKeychainRecoveryFacade.recover() call has none',
      );
    }

    final result = await locator<RemoteKeychainRecoveryFacade>().recover();
    return CompiledScenario(
      tuple: tuple,
      bullnym: bullnym,
      finalState: result,
      publishedManifest: published,
      interrupted: false,
    );
  }

  // --- staging helpers -----------------------------------------------------

  Future<void> _installBoundaries(FakeBullnymClient bullnym) async {
    await overrideBoundariesForTest(locator, bullnym: bullnym);
    await locator.unregister<SamRockPairingServicePort>();
    locator.registerLazySingleton<SamRockPairingServicePort>(
      () => _FakePairingService(),
    );
  }

  void _rejectUnsupported(ScenarioTuple t) {
    final manifest = t.get(ParameterModel.dManifest);
    final relay = t.get(ParameterModel.dRelay);
    // Two-relay divergence (E9) is a Phase-1-remainder item.
    if (relay == 'divergent') {
      throw const ScenarioUnsupported('divergent needs the E9 two-relay harness');
    }
    if (manifest == 'older-populated') {
      throw const ScenarioUnsupported(
        'older-populated needs two coexisting backups (E9 two-relay harness)',
      );
    }
    if (manifest == 'newer-version') {
      throw const ScenarioUnsupported(
        'newer-version needs a signed-but-newer fixture backup (crafted staging)',
      );
    }
    // D3 (manifest integrity) and D4 (relay-transport fault) cells relied on
    // FakeNostrRelay hooks (tamper/forge/timeout/flood/size-cap/offline) that
    // have no equivalent on FakeBullnymClient today — see the class doc.
    if (manifest == 'tampered' ||
        manifest == 'corrupt-undecryptable' ||
        manifest == 'forged-author') {
      throw const ScenarioUnsupported(
        'manifest-integrity fault needs a FakeBullnymClient fetchBackup fault '
        'hook; no equivalent to the retired FakeNostrRelay tamper/forge seam '
        'exists yet',
      );
    }
    if (relay != 'all-ok') {
      throw const ScenarioUnsupported(
        'relay-transport fault dimension needs a FakeBullnymClient fault hook; '
        'the FakeNostrRelay transport it was staged against no longer exists',
      );
    }
  }

  void _configureBullnym(FakeBullnymClient bullnym, ScenarioTuple t) {
    switch (t.get(ParameterModel.dServer)) {
      case 'up-live':
        bullnym.mode = FakeBullnymMode.live;
      case 'up-lapsed':
        bullnym.mode = FakeBullnymMode.inactiveWithPreviousNym;
      case 'down':
        bullnym.mode = FakeBullnymMode.serverUnreachable;
      case 'err-500':
      case 'err-conflict':
      case 'err-ratelimited':
        // These drove a per-call `injectedRegistrationError` the current
        // FakeBullnymClient has no equivalent field for; registration faults
        // are exercised deterministically elsewhere (bullnym-tests), so this
        // in-process recovery lane defers rather than guesses at a new hook.
        throw ScenarioUnsupported(
          '${t.get(ParameterModel.dServer)} needs a registration-error '
          'injection hook FakeBullnymClient does not expose today',
        );
      case 'soft-limit-bolt11':
        // A payer-side soft limit does not touch the recovery/heal path; treat
        // the server as live for the recovery lane.
        bullnym.mode = FakeBullnymMode.live;
    }
  }

  void _applyNetwork(FakeBullnymClient bullnym, String network) {
    switch (network) {
      case 'online':
        break;
      case 'offline':
        bullnym.mode = FakeBullnymMode.serverUnreachable;
      case 'flaky-drop':
        // No dropped-connection-after-connect seam on FakeBullnymClient today
        // (the old stand-in lived on the retired relay double); fold onto the
        // nearest supported fault rather than invent new fake behaviour.
        bullnym.mode = FakeBullnymMode.serverUnreachable;
    }
  }
}
