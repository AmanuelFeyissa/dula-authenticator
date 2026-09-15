import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dula_auth/core/security/linux_secret_service_probe.dart';
import 'package:dula_auth/core/vault/gated_secret_store.dart';
import 'package:dula_auth/core/vault/secret_store.dart';

/// The gate every production [SecretStore] call passes through.
///
/// Callers: [secretStoreProvider] below, and
/// `lib/core/widgets/app_lifecycle_wrapper.dart`, which resets it from the
/// blocking screen's RETRY and on resume. Overridden in widget tests with a
/// scripted gate.
///
/// Linux is the only platform gated (ADR-0018): it is the only one whose
/// backend can block the platform thread when its daemon is absent. Elsewhere
/// the gate is permanently open and costs nothing — the platforms are not
/// assumed alike, they are known to differ (ADR-0004, ADR-0005).
final secretStoreGateProvider = Provider<SecretStoreGate>((ref) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
    return SecretStoreGate(LinuxSecretServiceProbe().isAvailable);
  }
  return SecretStoreGate.alwaysOpen;
});

/// The single production [SecretStore] shared by the auth and account
/// repositories and the startup canary, so all of them sit behind one gate
/// and one verdict.
final secretStoreProvider = Provider<SecretStore>((ref) {
  const store = FlutterSecretStore();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
    return GatedSecretStore(store, ref.watch(secretStoreGateProvider));
  }
  return store;
});
