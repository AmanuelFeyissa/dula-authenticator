import 'package:dula_auth/core/config/deployment_config.dart';

/// Failed-unlock lockout policy: how long a credential is refused after N
/// consecutive wrong attempts.
///
/// Deployer-configurable via `assets/config/deployment_config.json`'s
/// `security.lockoutSteps` (see docs/adr/0016-deployment-configuration.md).
/// A mutable static configured once at startup, not a constructor parameter,
/// for the same reason as `PinPolicy`/`PassphrasePolicy`: consumed from
/// `AuthNotifier` with no existing dependency-injection path for policy
/// objects.
class LockoutPolicy {
  static List<LockoutStep> _steps = DeploymentConfig.fallback.lockoutSteps;

  /// Replaces the default lockout steps. Call once at startup, before any
  /// unlock attempt is processed. An empty list disables lockout entirely.
  static void configure(List<LockoutStep> steps) {
    _steps = steps;
  }

  /// Restores the default steps. Test-only — call in `tearDown` after any
  /// test that calls [configure], so configuration never leaks between
  /// tests in the same file.
  static void resetForTesting() {
    _steps = DeploymentConfig.fallback.lockoutSteps;
  }

  /// The lockout duration after [attempts] consecutive failures, or `null`
  /// if [attempts] hasn't reached the first configured threshold yet.
  static Duration? durationFor(int attempts) {
    Duration? result;
    for (final step in _steps) {
      if (attempts >= step.attempts) result = step.lockoutDuration;
    }
    return result;
  }
}
