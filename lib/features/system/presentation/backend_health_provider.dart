import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/system_repository.dart';
import '../domain/backend_health.dart';

final backendHealthProvider = FutureProvider.autoDispose<BackendHealth>(
  (ref) => ref.watch(systemRepositoryProvider).checkHealth(),
);
