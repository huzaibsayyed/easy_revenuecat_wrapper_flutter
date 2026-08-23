import 'package:easy_revenuecat_wrapper_flutter/easy_revenuecat_wrapper_flutter.dart';
import 'package:flutter/material.dart';

/// Replace these with the values from your RevenueCat dashboard before
/// running this example against a real project.
const _revenueCatApiKey = 'your_revenuecat_api_key';
const _entitlementId = 'premium';
const _offeringId = 'default';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await RevenueCatService.instance.init(apiKey: _revenueCatApiKey, entitlementId: _entitlementId);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'easy_revenuecat_wrapper_flutter example',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RevenueCat wrapper example')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Reactively reflects RevenueCatService.instance, so this
              // rebuilds whenever the entitlement changes.
              AnimatedBuilder(
                animation: RevenueCatService.instance,
                builder: (context, _) {
                  final isSubscribed = RevenueCatService.instance.isSubscribed;
                  return Text(isSubscribed ? 'You are subscribed 🎉' : 'You are not subscribed', style: Theme.of(context).textTheme.titleLarge);
                },
              ),
              const SizedBox(height: 24),
              // The builder only decides how the button looks; tapping is
              // handled by RevenueCatSubscriptionButton itself, so the child
              // here has no onPressed/onTap of its own.
              RevenueCatSubscriptionButton(
                offeringId: _offeringId,
                builder: (context, isSubscribed) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(8)),
                  child: Text(isSubscribed ? 'Manage subscription' : 'Subscribe', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary)),
                ),
                onSubscriptionResult: ({required success, required message}) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
