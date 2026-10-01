import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_config.dart';

/// Overridden in `bootstrap()` and in tests; never read before then.
final appConfigProvider = Provider<AppConfig>(
  (ref) => throw UnimplementedError('appConfigProvider must be overridden'),
);
