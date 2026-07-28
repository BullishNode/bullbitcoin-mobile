import 'package:bb_mobile/core/failures/failure.dart';

sealed class OnboardingFailure extends Failure {
  const OnboardingFailure([super.logMessage]);
}

final class OnboardingUnexpectedFailure extends OnboardingFailure {
  const OnboardingUnexpectedFailure([super.logMessage]);
}

/// Default wallet records are on the device without their seed, so onboarding
/// cannot reuse them; the user has to restore from a backup (#137).
final class OnboardingInconsistentWalletStateFailure extends OnboardingFailure {
  const OnboardingInconsistentWalletStateFailure([super.logMessage]);
}

final class OnboardingBackupVerificationPersistenceFailure
    extends OnboardingFailure {
  const OnboardingBackupVerificationPersistenceFailure([super.logMessage]);
}
