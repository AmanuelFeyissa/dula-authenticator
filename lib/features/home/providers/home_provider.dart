import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dula_auth/core/models/otp_account.dart';
import 'package:dula_auth/core/repositories/account_repository.dart';
import 'package:dula_auth/features/auth/providers/auth_provider.dart';

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  return AccountRepository();
});

class AccountListNotifier extends StateNotifier<AsyncValue<List<OtpAccount>>> {
  final AccountRepository _repository;
  final Ref _ref;

  AccountListNotifier(this._repository, this._ref) : super(const AsyncValue.loading()) {
    // We don't load immediately during construction if the masterKey isn't ready
    // Instead, the provider definition or initial load will handle it.
  }

  Future<void> loadAccounts() async {
    try {
      final authState = _ref.read(authStateProvider);
      
      // If we are locked or setup is required, or NO master key, don't show accounts
      if (authState.isLocked || authState.isSetupRequired || authState.masterKey == null) {
        state = const AsyncValue.data([]);
        return;
      }

      state = const AsyncValue.loading();
      final accounts = await _repository.getAccounts(masterKey: authState.masterKey);
      state = AsyncValue.data(accounts);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<bool> addAccount(OtpAccount account) async {
    final authState = _ref.read(authStateProvider);
    final success = await _repository.addAccount(account, masterKey: authState.masterKey);
    if (success) {
      await loadAccounts();
    }
    return success;
  }

  Future<void> deleteAccount(String id) async {
    final authState = _ref.read(authStateProvider);
    final success = await _repository.deleteAccount(id, masterKey: authState.masterKey);
    if (success) {
      await loadAccounts();
    }
  }

  /// Advances an HOTP counter and persists it.
  ///
  /// Counter-based codes do not refresh on a clock; each use consumes one
  /// value, so the stored counter must move forward atomically or the account
  /// desynchronises from the server.
  Future<void> advanceCounter(String id) async {
    final authState = _ref.read(authStateProvider);
    if (authState.masterKey == null) return;

    final accounts = await _repository.getAccounts(masterKey: authState.masterKey);
    final index = accounts.indexWhere((a) => a.id == id);
    if (index == -1) return;

    final updated = accounts[index].copyWith(counter: accounts[index].counter + 1);
    final saved = await _repository.updateAccount(updated, masterKey: authState.masterKey);
    if (saved) await loadAccounts();
  }

  Future<void> clearAllAccounts() async {
    await _repository.clearAll();
    await loadAccounts();
  }
}

final accountListProvider = StateNotifierProvider<AccountListNotifier, AsyncValue<List<OtpAccount>>>((ref) {
  final notifier = AccountListNotifier(ref.read(accountRepositoryProvider), ref);
  
  // Reactively reload whenever the app becomes unlocked with a key available.
  // We listen broadly to cover:
  //  (a) masterKey changing null→key (normal PIN unlock in a single state update)
  //  (b) isLocked changing true→false while masterKey is already set (biometric, future paths)
  ref.listen(authStateProvider, (previous, next) {
    final wasLocked = previous?.isLocked ?? true;
    final isNowUnlocked = !next.isLocked && next.masterKey != null;
    final keyChanged = previous?.masterKey != next.masterKey;
    final justUnlocked = wasLocked && !next.isLocked;

    if (isNowUnlocked && (keyChanged || justUnlocked)) {
      notifier.loadAccounts();
    } else if (next.masterKey == null || next.isLocked) {
      // Clear list on lock or key wipe
      notifier.loadAccounts();
    }
  });

  // Initial load
  notifier.loadAccounts();
  
  return notifier;
});

final currentTimerProvider = StreamProvider.autoDispose<DateTime>((ref) {
  return Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now());
});
