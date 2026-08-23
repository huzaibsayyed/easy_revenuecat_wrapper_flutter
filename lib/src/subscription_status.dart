import 'package:purchases_flutter/purchases_flutter.dart';

/// Immutable snapshot of a user's entitlement/subscription state.
///
/// Replaces the old inverted "showAds" boolean with something that
/// actually says what it means, plus a bit of extra detail (expiry,
/// renewal, product id) that's usually needed sooner or later anyway.
class SubscriptionStatus {
  final bool isActive;
  final String entitlementId;
  final DateTime? expirationDate;
  final bool willRenew;
  final String? productIdentifier;

  const SubscriptionStatus({required this.isActive, required this.entitlementId, this.expirationDate, this.willRenew = false, this.productIdentifier});

  factory SubscriptionStatus.fromCustomerInfo(CustomerInfo info, String entitlementId) {
    final entitlement = info.entitlements.all[entitlementId];
    return SubscriptionStatus(
      isActive: entitlement?.isActive ?? false,
      entitlementId: entitlementId,
      expirationDate: entitlement?.expirationDate == null ? null : DateTime.tryParse(entitlement!.expirationDate!),
      willRenew: entitlement?.willRenew ?? false,
      productIdentifier: entitlement?.productIdentifier,
    );
  }

  /// Safe placeholder for "we haven't checked yet" — defaults to inactive
  /// so callers never accidentally unlock paid features before a real
  /// fetch has completed.
  factory SubscriptionStatus.unknown(String entitlementId) => SubscriptionStatus(isActive: false, entitlementId: entitlementId);

  @override
  String toString() =>
      'SubscriptionStatus(isActive: $isActive, entitlementId: $entitlementId, '
      'expirationDate: $expirationDate, willRenew: $willRenew, '
      'productIdentifier: $productIdentifier)';
}
