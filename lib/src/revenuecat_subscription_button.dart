import 'package:flutter/material.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

import './revenuecat_service.dart';

typedef SubscriptionResultCallback = void Function({required bool success, required String message});

/// A tappable widget that shows a paywall (or the customer center, if the
/// user is already subscribed) and reports the outcome.
///
/// Unlike the original, this doesn't hardcode an asset path or copy — you
/// supply [builder] for the tappable child, so every app that reuses this
/// package can use its own icon and styling. It also reactively reflects
/// [RevenueCatService.instance], so you don't need to pass a `showAds`
/// flag down from a parent and keep it in sync by hand.
class RevenueCatSubscriptionButton extends StatefulWidget {
  /// Identifier of the RevenueCat Offering whose paywall should be shown.
  /// A paywall is designed and attached to an Offering in the RevenueCat
  /// dashboard, so selecting a specific paywall means selecting the
  /// Offering it's attached to — there's no way to address a paywall
  /// directly by its own id.
  final String offeringId;

  /// Builds the tappable child for the current subscription state.
  final Widget Function(BuildContext context, bool isSubscribed) builder;

  final SubscriptionResultCallback? onSubscriptionResult;

  /// Optional override for the outcome copy. Defaults to plain English.
  final String Function(PaywallResult result)? messageBuilder;

  const RevenueCatSubscriptionButton({super.key, required this.offeringId, required this.builder, this.onSubscriptionResult, this.messageBuilder});

  @override
  State<RevenueCatSubscriptionButton> createState() => _RevenueCatSubscriptionButtonState();
}

class _RevenueCatSubscriptionButtonState extends State<RevenueCatSubscriptionButton> {
  bool _busy = false;

  String _defaultMessage(PaywallResult result) => switch (result) {
    PaywallResult.purchased => 'Subscription activated successfully.',
    PaywallResult.restored => 'Your subscription has been restored.',
    PaywallResult.cancelled => 'Subscription purchase cancelled.',
    PaywallResult.error => 'Unable to complete the subscription. Please try again.',
    PaywallResult.notPresented => 'The subscription offer could not be displayed.',
  };

  Future<void> _handleTap() async {
    if (_busy) return;
    setState(() => _busy = true);

    final service = RevenueCatService.instance;

    try {
      if (service.isSubscribed) {
        await RevenueCatUI.presentCustomerCenter();
        widget.onSubscriptionResult?.call(success: true, message: 'Your subscription is active.');
        return;
      }

      final offerings = await service.getOfferings();
      final offering = offerings.getOffering(widget.offeringId);
      final result = await RevenueCatUI.presentPaywallIfNeeded(service.entitlementId, offering: offering);
      final success = result == PaywallResult.purchased || result == PaywallResult.restored;
      final message = (widget.messageBuilder ?? _defaultMessage)(result);
      widget.onSubscriptionResult?.call(success: success, message: message);
    } catch (e) {
      widget.onSubscriptionResult?.call(success: false, message: 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!RevenueCatService.instance.isInitialized) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: RevenueCatService.instance,
      builder: (context, _) {
        final isSubscribed = RevenueCatService.instance.isSubscribed;
        return Opacity(
          opacity: _busy ? 0.5 : 1.0,
          child: InkWell(onTap: _busy ? null : _handleTap, child: widget.builder(context, isSubscribed)),
        );
      },
    );
  }
}
