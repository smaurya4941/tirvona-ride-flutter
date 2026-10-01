import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notifications/push_notifications.dart';
import '../core/realtime/realtime_providers.dart';
import '../core/theme/app_theme.dart';
import '../features/branding/application/branding_controller.dart';
import '../features/rides/application/driver_duty_binding.dart';
import 'router/app_router.dart';

class TirvonaRideApp extends ConsumerWidget {
  const TirvonaRideApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // App-lifetime services: the realtime connection follows the session,
    // and an approved driver's location follows their duty state; push
    // registration follows the session too; branding syncs once per launch.
    ref
      ..watch(brandingSyncProvider)
      ..watch(realtimeClientProvider)
      ..watch(driverDutyBindingProvider)
      ..watch(pushNotificationsProvider);
    return MaterialApp.router(
      scaffoldMessengerKey: ref.watch(rootMessengerKeyProvider),
      title: 'Tirvona Rides',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
