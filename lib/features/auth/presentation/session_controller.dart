import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/storage/secure_storage.dart';
import '../data/auth_repository.dart';
import '../domain/app_user.dart';
import '../domain/auth_session.dart';

enum SessionStatus {
  /// Bootstrap hasn't resolved yet — the splash screen stays up.
  unknown,
  unauthenticated,
  authenticated,
}

class SessionState {
  const SessionState({required this.status, this.user});

  const SessionState.unknown() : this(status: SessionStatus.unknown);
  const SessionState.unauthenticated()
    : this(status: SessionStatus.unauthenticated);
  const SessionState.authenticated(AppUser user)
    : this(status: SessionStatus.authenticated, user: user);

  final SessionStatus status;
  final AppUser? user;

  bool get isAuthenticated => status == SessionStatus.authenticated;
}

/// Single source of truth for "who is logged in, as what role, with what
/// driver-approval status". The router (see app_router.dart) watches this to
/// decide which shell to show; screens call its methods to mutate it.
class SessionController extends Notifier<SessionState> {
  /// Work that must run while the user is still signed in (e.g. stopping
  /// push to this phone). Registered by those services, so the session
  /// never depends on them — they depend on the session.
  final List<Future<void> Function()> _beforeLogout = [];

  void addBeforeLogoutHook(Future<void> Function() hook) {
    if (!_beforeLogout.contains(hook)) _beforeLogout.add(hook);
  }

  void removeBeforeLogoutHook(Future<void> Function() hook) =>
      _beforeLogout.remove(hook);

  @override
  SessionState build() {
    unawaited(_bootstrap());
    return const SessionState.unknown();
  }

  Future<void> _bootstrap() async {
    final storage = ref.read(secureStorageProvider);
    final hasTokens =
        await storage.readAccessToken() != null &&
        await storage.readRefreshToken() != null;
    if (!hasTokens) {
      state = const SessionState.unauthenticated();
      return;
    }
    try {
      final user = await ref.read(authRepositoryProvider).me();
      state = SessionState.authenticated(user);
    } on ApiException {
      // AuthInterceptor already tried a silent refresh internally; a
      // failure here means the session is genuinely gone.
      await storage.clearTokens();
      state = const SessionState.unauthenticated();
    }
  }

  /// Persists a session obtained outside [login] — a verified signup
  /// (see [SignupFlow]) — without announcing it yet. Tokens are stored at
  /// once, so a restart in between still resumes signed in.
  Future<void> storeSession(AuthSession session) => ref
      .read(secureStorageProvider)
      .saveTokens(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
      );

  /// Signs in with a stored session; the router then routes by role
  /// (driver → KYC onboarding, customer → home).
  Future<void> activate(AuthSession session) async {
    await storeSession(session);
    state = SessionState.authenticated(session.user);
  }

  /// The signed-in user's phone was just verified (legacy accounts).
  void updateUser(AppUser user) {
    if (!state.isAuthenticated) return;
    state = SessionState.authenticated(user);
  }

  Future<void> login({required String phone, required String password}) async {
    final storage = ref.read(secureStorageProvider);
    final deviceId = await storage.readOrCreateDeviceId();
    final session = await ref
        .read(authRepositoryProvider)
        .login(phone: phone, password: password, deviceId: deviceId);
    await storage.saveTokens(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );
    state = SessionState.authenticated(session.user);
  }

  /// Signs out on every device. The server call must succeed first (it is
  /// the point of the action); then this device signs out like [logout].
  Future<void> logoutEverywhere() async {
    await ref.read(authRepositoryProvider).logoutEverywhere();
    await _signOutLocally(revokeRefreshToken: false);
  }

  Future<void> logout() => _signOutLocally(revokeRefreshToken: true);

  Future<void> _signOutLocally({required bool revokeRefreshToken}) async {
    // While still signed in (e.g. stop pushes to this phone). A failing
    // hook must never keep the user signed in.
    for (final hook in List.of(_beforeLogout)) {
      try {
        await hook().timeout(const Duration(seconds: 6));
      } catch (_) {}
    }
    final storage = ref.read(secureStorageProvider);
    final refreshToken = await storage.readRefreshToken();
    await storage.clearTokens();
    state = const SessionState.unauthenticated();
    if (revokeRefreshToken && refreshToken != null) {
      // Best-effort — logout is idempotent server-side, so a network
      // failure here shouldn't block signing out locally.
      unawaited(
        ref
            .read(authRepositoryProvider)
            .logout(refreshToken)
            .catchError((_) {}),
      );
    }
  }

  /// Called by [AuthInterceptor] when a silent token refresh fails.
  Future<void> handleSessionExpired() async {
    if (!state.isAuthenticated) return;
    await ref.read(secureStorageProvider).clearTokens();
    state = const SessionState.unauthenticated();
  }

  /// Re-fetches the current user — call after actions that change
  /// `driverStatus` (submitting KYC) so the shell picks the right screen.
  Future<void> refreshUser() async {
    if (!state.isAuthenticated) return;
    try {
      final user = await ref.read(authRepositoryProvider).me();
      state = SessionState.authenticated(user);
    } on ApiException {
      // Keep showing the last known-good user on a transient failure.
    }
  }
}

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);
