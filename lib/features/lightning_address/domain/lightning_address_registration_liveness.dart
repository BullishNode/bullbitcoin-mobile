/// Outcome kinds for the DG-3 registration liveness check.
enum LightningAddressRegistrationLiveness {
  /// Lookup returned active:true — nothing to do, nothing to render.
  live,

  /// Was inactive with a known nym; a silent re-register succeeded.
  reregistered,

  /// Genuinely missing (NymNotFound) or a re-register was rejected (e.g.
  /// NymTaken) — the UI offers a re-activation affordance.
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
