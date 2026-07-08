import 'package:bb_mobile/features/btcpay/domain/samrock_pairing_service_port.dart';
import 'package:bb_mobile/features/btcpay/domain/usecases/complete_btcpay_samrock_pairing_usecase.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_error.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/create_default_wallets_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/presentation/remote_keychain_recovery_cubit.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/presentation/remote_keychain_recovery_state.dart';
import 'package:get_it/get_it.dart';
import 'package:qa_matrix_engine/qa_matrix_engine.dart';

import '../../support/fake_bullnym_client.dart';
import '../../support/fake_nostr_relay.dart';
import '../../support/test_locator_overrides.dart';
import '../../support/wipe_app_state.dart';
import 'matrix_fixtures.dart';

/// Raised when a tuple names a state this in-process build cannot yet stage
/// (e.g. the two-relay `divergent` / `older-populated` cells, which need the E9
/// two-relay harness). The runner turns it into a non-fatal [CaseOutcome.blocked]
/// with this reason — distinct from a Fail, per the §12 rich-outcome model.
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
  Future<SamRockPairingResponse> submitSetup({
    required Object request,
    required Object payload,
  }) async => const SamRockPairingResponse(success: true);
}

/// The staged world for one tuple: the fake seams and the terminal recovery
/// state the run reached, kept together so the invariant assertions can inspect
/// both the outcome and the wire (captured frames, stored-event count, etc.).
class CompiledScenario {
  CompiledScenario({
    required this.tuple,
    required this.relay,
    required this.bullnym,
    required this.finalState,
    required this.publishedManifest,
    required this.interrupted,
  });

  final ScenarioTuple tuple;
  final FakeNostrRelay relay;
  final FakeBullnymClient bullnym;
  final RemoteKeychainRecoveryState finalState;

  /// True when a populated, authentic manifest was published to the relay under
  /// the correct seed during staging (so P2 knows a real backup existed).
  final bool publishedManifest;

  /// True when the recovery run was deliberately cut short (D7 interrupt).
  final bool interrupted;
}

/// Compiles a [ScenarioTuple] into a concrete fake configuration, stages the
/// pre-recovery world (wallets + published manifest + fault schedule), then
/// drives the real [RemoteKeychainRecoveryCubit] to a terminal state
/// (GETPAID-APP-E2E-FAILURE-MATRIX §5.3 steps 4-5). Single-relay S-INJECT only;
/// two-relay cells raise [ScenarioUnsupported].
class ScenarioCompiler {
  ScenarioCompiler(this.locator);

  final GetIt locator;

  Future<CompiledScenario> compileAndStage(ScenarioTuple tuple) async {
    _rejectUnsupported(tuple);

    final relay = FakeNostrRelay();
    final bullnym = FakeBullnymClient();
    _configureBullnym(bullnym, tuple);

    // --- Stage the pre-recovery world under the CORRECT seed --------------
    await wipeAppState(locator);
    await _installBoundaries(relay, bullnym);

    final manifestState = tuple.get(ParameterModel.dManifest);
    final backup = tuple.get(ParameterModel.dBackup);
    final wantManifest =
        manifestState == 'current' && backup.startsWith('on');

    await locator<CreateDefaultWalletsUsecase>().execute(
      mnemonicWords: matrixCorrectMnemonic,
    );
    var published = false;
    if (wantManifest) {
      await locator<GetPaidSettingsFacade>().acknowledgeBackupDisclosure(
        automatedBackupEnabled: true,
      );
      // Pairing records a keychain-manifest entry and publishes the snapshot —
      // the proven staging path (SPEC-RT-01), so the relay holds one populated
      // authentic NIP-33 event on the seed-derived coordinate.
      await locator<CompleteBtcpaySamRockPairingUsecase>().execute(
        pairingUrl: _pairingUrl,
      );
      published = relay.storedEventCount > 0;
    }

    // --- Apply the D3/D4 fault schedule that acts at FETCH time ------------
    _applyManifestFaults(relay, manifestState);
    _applyRelayFaults(relay, tuple.get(ParameterModel.dRelay));
    _applyNetwork(relay, bullnym, tuple.get(ParameterModel.dNetwork));

    // --- Simulate a fresh install, then recover ---------------------------
    await wipeAppState(locator);
    final recoverySeed = tuple.get(ParameterModel.dSeed) == 'correct'
        ? matrixCorrectMnemonic
        : matrixWrongMnemonic;
    await locator<CreateDefaultWalletsUsecase>().execute(
      mnemonicWords: recoverySeed,
    );

    final interrupt = tuple.get(ParameterModel.dInterrupt);
    final cubit = locator<RemoteKeychainRecoveryCubit>();
    var interrupted = false;
    try {
      if (interrupt != 'none') {
        // D7 (E10, test-driven cubit cancellation, §11-D2 option b): start the
        // flow, then close the cubit mid-run so any in-flight async result is
        // discarded by the _operationId/isClosed guard — no product change.
        interrupted = true;
        final future = cubit.start(acceptedThirdPartyRelayDisclosure: true);
        await cubit.close();
        await future;
        return CompiledScenario(
          tuple: tuple,
          relay: relay,
          bullnym: bullnym,
          finalState: cubit.state,
          publishedManifest: published,
          interrupted: interrupted,
        );
      }

      await cubit.start(acceptedThirdPartyRelayDisclosure: true);
      // A first start that stalls on the disclosure gate is driven past it.
      if (cubit.state.status ==
          RemoteKeychainRecoveryStatus.requiresRelayDisclosure) {
        await cubit.acceptRelayDisclosure();
      }
      // The "restore the older manifest?" branch is an explicit user step; the
      // oracle accepts the offer itself as the terminal verdict, so we do not
      // auto-accept here (that is a distinct RB permutation).
      return CompiledScenario(
        tuple: tuple,
        relay: relay,
        bullnym: bullnym,
        finalState: cubit.state,
        publishedManifest: published,
        interrupted: interrupted,
      );
    } finally {
      if (!cubit.isClosed) await cubit.close();
    }
  }

  // --- staging helpers -----------------------------------------------------

  Future<void> _installBoundaries(
    FakeNostrRelay relay,
    FakeBullnymClient bullnym,
  ) async {
    await overrideBoundariesForTest(locator, relay: relay, bullnym: bullnym);
    await locator.unregister<SamRockPairingServicePort>();
    locator.registerLazySingleton<SamRockPairingServicePort>(
      () => _FakePairingService(),
    );
  }

  void _rejectUnsupported(ScenarioTuple t) {
    final manifest = t.get(ParameterModel.dManifest);
    final relay = t.get(ParameterModel.dRelay);
    // Two-relay divergence (E9) is a Phase-1-remainder item: a single fake relay
    // enforces NIP-33 replacement, so it cannot hold an older-populated event
    // beside a newer empty/failed one.
    if (relay == 'divergent') {
      throw const ScenarioUnsupported('divergent needs the E9 two-relay harness');
    }
    if (manifest == 'older-populated') {
      throw const ScenarioUnsupported(
        'older-populated needs two coexisting events (E9 two-relay harness)',
      );
    }
    if (manifest == 'newer-version') {
      throw const ScenarioUnsupported(
        'newer-version needs a signed-but-newer fixture event (crafted staging)',
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
        bullnym.injectedRegistrationError =
            const BullnymException.unexpectedHttpStatus(statusCode: 500);
      case 'err-conflict':
        bullnym.injectedRegistrationError =
            const BullnymException.serverRejectedRequest(
              code: 'Conflict',
              diagnosticReason: 'nym already registered',
              statusCode: 409,
              retryable: false,
            );
      case 'err-ratelimited':
        bullnym.injectedRegistrationError =
            const BullnymException.serverRejectedRequest(
              code: 'RateLimitedSender',
              diagnosticReason: 'registration rate limit exceeded',
              statusCode: 429,
              retryable: true,
            );
      case 'soft-limit-bolt11':
        // A payer-side soft limit does not touch the recovery/heal path; treat
        // the server as live for the recovery lane.
        bullnym.mode = FakeBullnymMode.live;
    }
  }

  void _applyManifestFaults(FakeNostrRelay relay, String manifestState) {
    switch (manifestState) {
      case 'tampered':
      case 'corrupt-undecryptable':
        // Mutating stored content after signing breaks the NIP-01 id / BIP340
        // signature, so the authenticity boundary drops the event (P6).
        relay.tamperStoredContent = true;
      case 'forged-author':
        // A same-coordinate event under a different key: dropped by the author
        // filter / sig check, never materialised (P6).
        relay.forgedEvent = _forgedManifestEvent();
      case 'none':
      case 'current':
      case 'empty-newest':
        break;
    }
  }

  void _applyRelayFaults(FakeNostrRelay relay, String profile) {
    switch (profile) {
      case 'all-ok':
        break;
      case 'one-reject':
      case 'auth-required':
        relay.neverOk = true;
      case 'one-timeout':
      case 'never-eose':
        relay.eoseDelay = const Duration(seconds: 30);
      case 'one-flood':
        relay.floodCount = 64;
      case 'one-forge':
        relay.forgedEvent = _forgedManifestEvent();
      case 'size-cap':
        relay.oversizeContentBytes = 300 * 1024;
      case 'all-down':
        relay.offline = true;
      case 'divergent':
        break; // rejected earlier.
    }
  }

  void _applyNetwork(
    FakeNostrRelay relay,
    FakeBullnymClient bullnym,
    String network,
  ) {
    switch (network) {
      case 'online':
        break;
      case 'offline':
        relay.offline = true;
        bullnym.mode = FakeBullnymMode.serverUnreachable;
      case 'flaky-drop':
        // Deterministic stand-in: a dropped connection on the relay side.
        relay.dropAfterConnect = true;
    }
  }

  Map<String, dynamic> _forgedManifestEvent() => <String, dynamic>{
    'id': 'f' * 64,
    'pubkey': 'e' * 64,
    'created_at': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
    'kind': 30078,
    'tags': [
      ['d', 'manifest'],
    ],
    'content': 'forged',
    'sig': '0' * 128,
  };
}
