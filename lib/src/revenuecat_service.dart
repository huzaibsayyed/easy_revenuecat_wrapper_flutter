import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:logging/logging.dart';

import 'revenuecat_exception.dart';
import 'subscription_status.dart';

/// Thin, app-agnostic wrapper around the RevenueCat SDK.
///
/// Call [RevenueCatService.init] once at app startup. From then on,
/// [RevenueCatService.instance] is a [ChangeNotifier] — listen to it (or
/// wrap widgets in an `AnimatedBuilder`) to react to entitlement changes
/// anywhere in the app, instead of re-fetching status by hand.
class RevenueCatService extends ChangeNotifier with WidgetsBindingObserver {
  RevenueCatService._();

  static final RevenueCatService instance = RevenueCatService._();
  static final Logger _log = Logger('RevenueCatService');

  late String _entitlementId;
  bool _initialized = false;
  SubscriptionStatus? _status;
  Timer? _expirationTimer;
  int _expirationRetryCount = 0;

  late int _maxExpirationRetries;
  late Duration _expirationRetryDelay;
  late Duration _expirationBuffer;

  bool get isInitialized => _initialized;

  /// The entitlement identifier passed to [init]. Needed by callers (e.g.
  /// [RevenueCatSubscriptionButton]) that must supply it to RevenueCat SDK
  /// calls like `presentPaywallIfNeeded`.
  String get entitlementId {
    _ensureInitialized();
    return _entitlementId;
  }

  /// Latest known status. Null until the first fetch completes after [init].
  SubscriptionStatus? get status => _status;

  /// True only if the cached entitlement is active AND, when it has an
  /// expiration date, the device clock hasn't passed it yet.
  ///
  /// RevenueCat computes `entitlement.isActive` at the moment the
  /// `CustomerInfo` was fetched — it does not update itself just because
  /// time passes while the app stays open. Checking [SubscriptionStatus.expirationDate]
  /// here means a stale cache can't report an already-expired subscription
  /// as active, even before the next [refresh] happens.
  bool get isSubscribed {
    final s = _status;
    if (s == null || !s.isActive) return false;
    final expiration = s.expirationDate;
    if (expiration != null && !expiration.isAfter(DateTime.now())) return false;
    return true;
  }

  /// Configures the RevenueCat SDK and starts listening for entitlement
  /// changes. Safe to call more than once — later calls are no-ops.
  ///
  /// [logLevel] defaults to [LogLevel.warn] rather than `debug`, since this
  /// gets reused across apps and debug logging shouldn't ship by default.
  Future<void> init({
    required String apiKey,
    required String entitlementId,
    LogLevel logLevel = LogLevel.warn,
    String? appUserId,
    int maxExpirationRetries = 4,
    Duration expirationRetryDelay = const Duration(minutes: 5),
    Duration expirationBuffer = const Duration(minutes: 5),
  }) async {
    if (_initialized) return;

    _entitlementId = entitlementId;
    _maxExpirationRetries = maxExpirationRetries;
    _expirationRetryDelay = expirationRetryDelay;
    _expirationBuffer = expirationBuffer;

    await Purchases.setLogLevel(logLevel);
    final configuration = PurchasesConfiguration(apiKey);
    if (appUserId != null) {
      configuration.appUserID = appUserId;
    }
    await Purchases.configure(configuration);

    Purchases.addCustomerInfoUpdateListener(_onCustomerInfoUpdate);
    WidgetsBinding.instance.addObserver(this);
    _initialized = true;

    _log.info('RevenueCat initialized successfully.');

    await refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Catches the common real-world case: the subscription lapsed while the
    // app was backgrounded (or closed), so no CustomerInfo update ever fired
    // for it. Re-sync as soon as the user comes back.
    if (state == AppLifecycleState.resumed && _initialized) {
      refresh();
    }
  }

  void _onCustomerInfoUpdate(CustomerInfo info) => _applyCustomerInfo(info);

  void _applyCustomerInfo(CustomerInfo info) {
    _status = SubscriptionStatus.fromCustomerInfo(info, _entitlementId);
    _scheduleExpirationCheck();
    notifyListeners();
  }

  /// Fetches [status] from RevenueCat and updates it.
  ///
  /// RevenueCat's own SDK caches `CustomerInfo` (`cachedOrFetched` by
  /// default) and only treats that cache as stale after ~5 minutes in the
  /// foreground. So a plain [refresh] shortly after a renewal can still
  /// hand back the pre-renewal snapshot. Pass [forceRefresh] to invalidate
  /// that cache first — used by [_checkAfterExpiration], where reading
  /// stale data would incorrectly flip [isSubscribed] to false.
  Future<SubscriptionStatus> refresh({bool forceRefresh = false}) async {
    _ensureInitialized();
    try {
      if (forceRefresh) {
        _log.fine('Invalidating RevenueCat customer info cache.');
        await Purchases.invalidateCustomerInfoCache();
      }
      final info = await Purchases.getCustomerInfo();
      _applyCustomerInfo(info);
      _log.fine('Customer info refreshed successfully.');
      return _status!;
    } catch (e) {
      _log.fine('Failed to refresh customer info: $e');
      throw RevenueCatWrapperException('Failed to fetch customer info', e);
    }
  }

  /// Schedules a check right around when the current entitlement is due to
  /// expire, so listeners (ad-gating, the subscription button, etc.) get
  /// notified even if the app never backgrounds/foregrounds in between.
  void _scheduleExpirationCheck() {
    _expirationTimer?.cancel();
    final expiration = _status?.expirationDate;
    if (expiration == null) return;

    final delay = expiration.difference(DateTime.now()) + _expirationBuffer;
    if (delay.isNegative) {
      // Already past expiration per this status. `_applyCustomerInfo` (our
      // only caller) has already notified listeners with it — nothing more
      // to schedule here. If this reading needs a retry because the
      // subscription was auto-renewing, that's driven by
      // [_checkAfterExpiration] itself, not from here, so we don't stomp on
      // its retry timer or its counter.
      return;
    }
    _expirationRetryCount = 0;
    _expirationTimer = Timer(delay, _checkAfterExpiration);
  }

  /// Runs once we're past the cached expiration date.
  ///
  /// For an auto-renewing subscription this moment is a race, not a clean
  /// cutover: the store can take a little while to process the renewal and
  /// for RevenueCat's backend to reflect it, so a naive check right here can
  /// read the entitlement as expired even though it renewed correctly. Two
  /// things guard against that turning into a permanent false "not
  /// subscribed" state (which is what showed ads even on a valid sub):
  /// forcing a non-cached fetch, and — if the entitlement was set to
  /// auto-renew — retrying a few times with a short backoff instead of
  /// giving up (and going silent) after a single stale read.
  Future<void> _checkAfterExpiration() async {
    final wasAutoRenewing = _status?.willRenew ?? false;

    try {
      await refresh(forceRefresh: true);
    } catch (e, stackTrace) {
      _log.warning('Expiration refresh failed.', e, stackTrace);
      // Network hiccup or similar — fall through to the retry/give-up logic
      // below using whatever `_status` already holds.
    }

    if (isSubscribed) {
      _log.info(
        'Subscription is still active after expiration check. '
        'Renewal confirmed.',
      );
      _expirationRetryCount = 0;
      return; // refresh() already renotified and rescheduled against the new expirationDate
    }

    if (wasAutoRenewing && _expirationRetryCount < _maxExpirationRetries) {
      _expirationRetryCount++;
      _log.warning(
        'Subscription is not active yet after expected renewal. '
        'Retrying in $_expirationRetryDelay '
        '($_expirationRetryCount/$_maxExpirationRetries).',
      );
      _expirationTimer = Timer(_expirationRetryDelay, _checkAfterExpiration);
    } else {
      _log.info(
        'Subscription considered expired. '
        'Auto-renew=$wasAutoRenewing, '
        'retries=$_expirationRetryCount.',
      );
      _expirationRetryCount = 0;
      notifyListeners(); // genuinely expired (or never auto-renewing) — tell listeners now
    }
  }

  Future<Offerings> getOfferings() async {
    _ensureInitialized();
    try {
      return await Purchases.getOfferings();
    } catch (e) {
      throw RevenueCatWrapperException('Failed to fetch offerings', e);
    }
  }

  Future<SubscriptionStatus> restorePurchases() async {
    _ensureInitialized();
    try {
      final info = await Purchases.restorePurchases();
      _applyCustomerInfo(info);
      return _status!;
    } catch (e) {
      throw RevenueCatWrapperException('Failed to restore purchases', e);
    }
  }

  /// Associates the RevenueCat anonymous user with your own [appUserId]
  /// (e.g. after login).
  Future<void> logIn(String appUserId) async {
    _ensureInitialized();
    try {
      final result = await Purchases.logIn(appUserId);
      _applyCustomerInfo(result.customerInfo);
    } catch (e) {
      throw RevenueCatWrapperException('Failed to log in', e);
    }
  }

  /// Resets to a new anonymous user (e.g. after logout).
  Future<void> logOut() async {
    _ensureInitialized();
    try {
      final info = await Purchases.logOut();
      _applyCustomerInfo(info);
    } catch (e) {
      throw RevenueCatWrapperException('Failed to log out', e);
    }
  }

  void _ensureInitialized() {
    if (!_initialized) throw const NotInitializedException();
  }

  @override
  void dispose() {
    _expirationTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    Purchases.removeCustomerInfoUpdateListener(_onCustomerInfoUpdate);
    super.dispose();
  }
}
