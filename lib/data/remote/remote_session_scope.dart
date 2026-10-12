import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/di/core_providers.dart';
import '../../app/router/app_router.dart';
import '../../core/persistence/entity_collection.dart' show JsonMap;
import '../../core/result/result.dart';
import '../../design_system/design_system.dart';
import '../../features/alerts/domain/alert.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/domain/auth_session.dart';
import '../../features/settings/domain/app_settings.dart';
import 'remote_providers.dart';
import 'sync_engine.dart';

/// The calculation-relevant preferences the server also uses.
JsonMap serverPreferencesOf(AppSettings s) => {
  'monthStartDay': s.monthStartDay,
  'emiReminderDays': s.emiReminderDays,
  'subscriptionReminderDays': s.subscriptionReminderDays,
  'lowEmergencyCoverageMonths': s.lowEmergencyCoverageMonths,
  'defaultBudgetWarningBps': s.defaultBudgetWarningBps,
  'disabledAlertTypes': (s.disabledAlertTypes.map((t) => t.name).toList()..sort()),
};

/// [s] with the server's preferences applied (unknown fields ignored).
AppSettings withServerPreferences(AppSettings s, JsonMap p) {
  int i(String k, int fallback) => (p[k] as num?)?.toInt() ?? fallback;
  final types = p['disabledAlertTypes'];
  return s.copyWith(
    monthStartDay: i('monthStartDay', s.monthStartDay).clamp(1, 28),
    emiReminderDays: i('emiReminderDays', s.emiReminderDays),
    subscriptionReminderDays: i('subscriptionReminderDays', s.subscriptionReminderDays),
    lowEmergencyCoverageMonths: i('lowEmergencyCoverageMonths', s.lowEmergencyCoverageMonths),
    defaultBudgetWarningBps: i('defaultBudgetWarningBps', s.defaultBudgetWarningBps),
    disabledAlertTypes: types is List
        ? types.map((e) => AlertType.values.where((t) => t.name == e).firstOrNull).whereType<AlertType>().toSet()
        : s.disabledAlertTypes,
  );
}

/// Runs the connected session around the app:
/// * after sign-in: offers a one-time upload of this device's data, then
///   runs the initial sync and decides whether setup (onboarding) is needed;
/// * syncs again whenever the app returns to the foreground;
/// * keeps the calculation preferences in step with `PATCH /preferences`;
/// * clears the signed-in user's cache on sign-out.
class RemoteSessionScope extends ConsumerStatefulWidget {
  const RemoteSessionScope({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<RemoteSessionScope> createState() => _RemoteSessionScopeState();
}

class _RemoteSessionScopeState extends ConsumerState<RemoteSessionScope> with WidgetsBindingObserver {
  late final RemoteBackend _backend = ref.read(remoteBackendProvider)!;
  SyncEngine get _engine => _backend.engine;

  StreamSubscription<Set<String>>? _engineSub;
  Timer? _prefsDebounce;
  JsonMap? _serverPrefs;
  bool _starting = false;

  static String _offeredKey(String userId) => 'finn.remote.importOffered.$userId';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _backend.auth.onExpired = () => ref.read(authControllerProvider.notifier).signOut();
    _serverPrefs = _engine.value(SyncValues.preferences);
    _engineSub = _engine.changes.listen((changed) {
      if (changed.contains(SyncValues.preferences)) _applyServerPreferences();
    });
    ref.listenManual<AuthSession?>(authControllerProvider, (prev, next) {
      if (prev == null && next != null) unawaited(_start());
      if (prev != null && next == null) unawaited(_engine.close(clearPersisted: true));
    });
    ref.listenManual<AppSettings>(settingsProvider, (prev, next) => _onSettingsChanged(next));
    if (ref.read(authControllerProvider) != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_start()));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _engineSub?.cancel();
    _prefsDebounce?.cancel();
    _backend.auth.onExpired = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && ref.read(authControllerProvider) != null && _engine.userId != null) {
      unawaited(_sync());
    }
  }

  Future<void> _sync() async {
    try {
      await _engine.sync();
    } on AppFailure catch (f) {
      debugPrint('Sync failed: ${f.message}');
    } catch (e) {
      debugPrint('Sync failed: $e');
    }
  }

  /// Sign-in (or app start with a session): open the user's cache, offer
  /// the import once, sync, then reconcile onboarding with the server.
  Future<void> _start() async {
    if (_starting) return;
    final userId = _backend.auth.userId;
    if (userId == null) return;
    _starting = true;
    try {
      await _engine.open(userId);
      _serverPrefs = _engine.value(SyncValues.preferences);
      final offered = _backend.prefs.getBool(_offeredKey(userId)) ?? false;
      if (!_engine.hasSynced && !offered && _backend.importer.hasLocalData) {
        await _offerImport(userId);
      }
      await _sync();
      await _reconcileOnboarding();
    } finally {
      _starting = false;
    }
  }

  Future<BuildContext?> _dialogContext() async {
    for (var i = 0; i < 20; i++) {
      await WidgetsBinding.instance.endOfFrame;
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) return ctx;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return null;
  }

  Future<void> _offerImport(String userId) async {
    final ctx = await _dialogContext();
    if (ctx == null || !ctx.mounted) return;
    final upload = await showFinnConfirm(
      ctx,
      title: 'Upload the data on this device?',
      message:
          'This device has records you created before signing in. You can upload them once to your '
          'FiNN account, or start from what is already in your account. Records on this device are not deleted.',
      confirmLabel: 'Upload my data',
      cancelLabel: 'Start from my account',
    );
    await _backend.prefs.setBool(_offeredKey(userId), true);
    if (!upload) return;
    try {
      await _backend.importer.upload(idempotencyKey: 'import_${userId}_${DateTime.now().millisecondsSinceEpoch}');
      _toast((c) => FinnToast.success(c, 'Your data was uploaded'));
    } on AppFailure catch (f) {
      if (f.code == FailureCode.conflict) {
        _toast(
          (c) => FinnToast.info(
            c,
            'Your account already has records',
            subtitle: 'Nothing was uploaded. Your account’s data is shown.',
          ),
        );
      } else {
        // Offer again next time (nothing was written: the import is atomic).
        await _backend.prefs.remove(_offeredKey(userId));
        _toast((c) => FinnToast.error(c, 'Could not upload your data', subtitle: f.message));
      }
    } catch (e) {
      debugPrint('Import failed: $e');
      await _backend.prefs.remove(_offeredKey(userId));
      _toast((c) => FinnToast.error(c, 'Could not upload your data', subtitle: 'Please try again later.'));
    }
  }

  /// Setup is needed exactly when the account has no financial profile yet.
  Future<void> _reconcileOnboarding() async {
    if (!_engine.hasSynced) return;
    final profile = _engine.value(SyncValues.profile);
    if (profile == null) return;
    final exists = profile['exists'] == true;
    if (ref.read(settingsProvider).onboardingComplete != exists) {
      await ref.read(settingsProvider.notifier).update((s) => s.copyWith(onboardingComplete: exists));
    }
  }

  void _applyServerPreferences() {
    final prefs = _engine.value(SyncValues.preferences);
    if (prefs == null) return;
    _serverPrefs = prefs;
    final current = ref.read(settingsProvider);
    final next = withServerPreferences(current, prefs);
    if (next != current) unawaited(ref.read(settingsProvider.notifier).update((_) => next));
  }

  void _onSettingsChanged(AppSettings next) {
    final server = _serverPrefs;
    if (server == null || _engine.userId == null) return;
    final mine = serverPreferencesOf(next);
    final theirs = serverPreferencesOf(withServerPreferences(next, server));
    final patch = <String, Object?>{
      for (final e in mine.entries)
        if (!_same(e.value, theirs[e.key])) e.key: e.value,
    };
    _prefsDebounce?.cancel();
    if (patch.isEmpty) return;
    _prefsDebounce = Timer(const Duration(milliseconds: 600), () => unawaited(_pushPreferences()));
  }

  static bool _same(Object? a, Object? b) => a is List && b is List ? listEquals(a, b) : a == b;

  Future<void> _pushPreferences() async {
    final server = _serverPrefs;
    if (server == null) return;
    final mine = serverPreferencesOf(ref.read(settingsProvider));
    final theirs = serverPreferencesOf(withServerPreferences(ref.read(settingsProvider), server));
    final patch = <String, Object?>{
      for (final e in mine.entries)
        if (!_same(e.value, theirs[e.key])) e.key: e.value,
    };
    if (patch.isEmpty) return;
    try {
      final data = await _backend.api.patch('/preferences', body: patch);
      final body = data is Map && data['preferences'] is Map ? data['preferences'] : data;
      if (body is Map) {
        final updated = Map<String, Object?>.from(body);
        _serverPrefs = updated;
        _engine.setValue(SyncValues.preferences, updated);
      }
    } catch (e) {
      debugPrint('Could not save preferences: $e');
      // Keep the app consistent with the server's calculations.
      _applyServerPreferences();
      _toast(
        (c) => FinnToast.error(
          c,
          'Could not save this setting',
          subtitle: e is AppFailure ? e.message : 'Please try again.',
        ),
      );
    }
  }

  void _toast(void Function(BuildContext context) show) {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted) show(ctx);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
