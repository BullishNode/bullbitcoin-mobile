import 'package:bb_mobile/features/bullnym/domain/bullnym_client_port.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_error.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_registration.dart';

enum FakeBullnymMode {
  /// Lookup returns an active registration.
  live,

  /// Lookup returns active:false with the previous nym (a lapsed registration).
  inactiveWithPreviousNym,

  /// Lookup returns a NymNotFound rejection (genuinely missing).
  registrationMissing,

  /// Lookup and register fail with a non-NymNotFound server error.
  serverUnreachable,
}

/// In-memory [BullnymClientPort] for L1 tests (HARNESS §2.2). It survives the
/// simulated app-state wipe (the fake object outlives it), records register
/// calls, and is toggle-driven so a single instance can drive the DG-3 heal
/// matrix (live / lapsed / missing / unreachable).
class FakeBullnymClient implements BullnymClientPort {
  FakeBullnymMode mode = FakeBullnymMode.live;
  String nym = 'alice';

  final List<String> registeredNyms = [];

  String get _lightningAddress => '$nym@example.invalid';

  @override
  Future<BullnymRegisterResult> register(BullnymRegisterRequest request) async {
    registeredNyms.add(request.nym);
    if (mode == FakeBullnymMode.serverUnreachable) {
      throw const BullnymException.serverRejectedRequest(
        code: 'ServiceUnavailable',
        diagnosticReason: 'fake relay unreachable',
        statusCode: 503,
        retryable: true,
      );
    }
    nym = request.nym;
    mode = FakeBullnymMode.live;
    return BullnymRegisterResult(nym: nym, lightningAddress: _lightningAddress);
  }

  @override
  Future<void> deleteRegistration(
    BullnymDeleteRegistrationRequest request,
  ) async {}

  @override
  Future<BullnymLookupResult> lookupRegistration({
    required String npubHex,
  }) async {
    switch (mode) {
      case FakeBullnymMode.live:
        return BullnymLookupResult(
          nym: nym,
          active: true,
          lightningAddress: _lightningAddress,
        );
      case FakeBullnymMode.inactiveWithPreviousNym:
        return BullnymLookupResult(nym: nym, active: false);
      case FakeBullnymMode.registrationMissing:
        throw const BullnymException.serverRejectedRequest(
          code: 'NymNotFound',
          diagnosticReason: 'no registration for npub',
          statusCode: 404,
          retryable: false,
        );
      case FakeBullnymMode.serverUnreachable:
        throw const BullnymException.serverRejectedRequest(
          code: 'ServiceUnavailable',
          diagnosticReason: 'fake relay unreachable',
          statusCode: 503,
          retryable: true,
        );
    }
  }
}
