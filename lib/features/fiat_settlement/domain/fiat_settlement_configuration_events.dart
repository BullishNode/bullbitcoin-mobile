import 'dart:async';

/// Process-wide signal shared by fiat-settlement writers and read-only
/// summaries. It emits only after a successful configuration mutation.
///
/// This is an application-domain event rather than presentation state: writers
/// publish it and presentation consumers decide when and how to refresh.
final class FiatSettlementConfigurationEvents {
  final StreamController<void> _changes = StreamController<void>.broadcast(
    sync: true,
  );

  Stream<void> get changes => _changes.stream;

  void notifyChanged() => _changes.add(null);
}
