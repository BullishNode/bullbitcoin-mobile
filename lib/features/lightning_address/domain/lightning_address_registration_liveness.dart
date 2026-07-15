/// Outcome kinds for the DG-3 registration liveness check.
enum LightningAddressRegistrationLiveness {
  /// Lookup returned active:true — nothing to do, nothing to render.
  live,

  /// A legacy registration was inactive with a known nym and a silent
  /// re-register succeeded. Permanent-name registrations never use this state.
  reregistered,

  /// Genuinely missing, an intentional permanent-name offline state, or a
  /// legacy re-register rejection — the UI offers a product reactivation
  /// affordance without offering a different name.
  needsReactivation,

  /// Network/timeout/5xx — liveness is UNKNOWN; degrade loudly, never heal
  /// blindly (never report [live] on a failure).
  unreachable,
}

class LightningAddressHealOutcome {
  final LightningAddressRegistrationLiveness liveness;
  final String? nym;
  final String? lightningAddress;

  const LightningAddressHealOutcome({
    required this.liveness,
    this.nym,
    this.lightningAddress,
  });
}
