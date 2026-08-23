# easy_revenuecat_wrapper_flutter

A simple, flexible Flutter wrapper around [RevenueCat](https://www.revenuecat.com/)
(`purchases_flutter` + `purchases_ui_flutter`) that gets you from zero to a
working paywall and entitlement check with minimal boilerplate.

- One `init()` call at app startup — no manual `CustomerInfo` plumbing.
- `RevenueCatService.instance` is a `ChangeNotifier`: listen to it (or wrap
  widgets in an `AnimatedBuilder`) to react to entitlement changes anywhere
  in your app.
- Handles the edge cases for you: re-syncing when the app resumes from the
  background, and retrying around the entitlement's expiration time so an
  auto-renewal that's still processing doesn't get read as "expired".
- `RevenueCatSubscriptionButton` shows the paywall (or the customer center,
  if already subscribed) and reports the outcome — you supply the styling.

## Installation

```sh
flutter pub add easy_revenuecat_wrapper_flutter
```

This package builds on `purchases_flutter` and `purchases_ui_flutter`, so
also follow RevenueCat's native setup for each platform (Android/iOS
configuration, API keys, products, entitlements, offerings, and paywalls)
in the [RevenueCat docs](https://www.revenuecat.com/docs/getting-started/installation).

## Setup (once, at app startup)

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await RevenueCatService.instance.init(
    apiKey: 'your_api_key',
    entitlementId: 'premium',
  );

  runApp(const MyApp());
}
```

`init` is safe to call more than once — later calls are no-ops.

## Reading status anywhere

```dart
final isSubscribed = RevenueCatService.instance.isSubscribed;

// or listen for changes reactively:
AnimatedBuilder(
  animation: RevenueCatService.instance,
  builder: (context, _) {
    final isSubscribed = RevenueCatService.instance.isSubscribed;
    return isSubscribed ? const SizedBox.shrink() : const BannerAd();
  },
);
```

### Gating ads behind a subscription

A common use case: only show ads to users who aren't subscribed. If you're
using [easy_admob_ads_flutter](https://pub.dev/packages/easy_admob_ads_flutter)
(or any other ads package with a similar `adsEnabled` switch), wire it up
once at startup and keep it in sync as the subscription changes:

```dart
// Enable ads only when the user is NOT subscribed.
EasyAdMobAds.instance.adsEnabled = !RevenueCatService.instance.isSubscribed;
RevenueCatService.instance.addListener(() {
  EasyAdMobAds.instance.adsEnabled = !RevenueCatService.instance.isSubscribed;
});
```

## The subscription button

`offeringId` is the identifier of the RevenueCat **Offering** whose paywall
should be shown — paywalls are designed and attached to an Offering in the
dashboard, so this is how you pick a specific one. If no Offering with that
identifier exists, it falls back to the dashboard's Current offering.

```dart
RevenueCatSubscriptionButton(
  offeringId: 'my_offering',
  builder: (context, isSubscribed) => Image.asset(
    isSubscribed ? 'assets/subscription.png' : 'assets/remove-ads.gif',
    width: 35,
  ),
  onSubscriptionResult: ({required success, required message}) {
    if (success) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  },
)
```

Each app supplies its own icon via `builder` and, optionally, its own copy
via `messageBuilder` — the package doesn't hardcode assets or text. Tapping
is handled entirely by the button, so the widget returned from `builder`
shouldn't have its own `onTap`/`onPressed`.

## Other operations

```dart
// Force a non-cached refresh of the current status.
await RevenueCatService.instance.refresh(forceRefresh: true);

// Restore purchases (e.g. from a "Restore purchases" button).
await RevenueCatService.instance.restorePurchases();

// Associate the RevenueCat user with your own app user id after login.
await RevenueCatService.instance.logIn(appUserId);

// Reset to a new anonymous user after logout.
await RevenueCatService.instance.logOut();
```

## Error handling

Every failable call throws a `RevenueCatWrapperException` (or its subtype
`NotInitializedException`, thrown when a method is called before `init`),
so you can catch one type instead of guessing at what `purchases_flutter`
throws underneath:

```dart
try {
  await RevenueCatService.instance.restorePurchases();
} on RevenueCatWrapperException catch (e) {
  // e.g. show e.message to the user
}
```

## Example

See the [example app](example) for a complete, runnable app that
initializes the service and uses `RevenueCatSubscriptionButton`.
