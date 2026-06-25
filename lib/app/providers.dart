import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_models.dart';
import '../services/app_repository.dart';

final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);
final repositoryProvider = Provider<AppRepository>(
  (ref) => AppRepository(ref.watch(supabaseProvider)),
);
final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseProvider).auth.onAuthStateChange,
);
final pagesProvider = FutureProvider<List<FacebookPage>>(
  (ref) => ref.watch(repositoryProvider).getPages(),
);
final selectedPageProvider = FutureProvider<FacebookPage?>(
  (ref) => ref.watch(repositoryProvider).selectedPage(),
);
final publicationsProvider = FutureProvider<List<AuctionPublication>>(
  (ref) => ref.watch(repositoryProvider).getPublications(),
);
final customersProvider = FutureProvider<List<Customer>>(
  (ref) => ref.watch(repositoryProvider).getCustomers(),
);
final ordersProvider = FutureProvider<List<OrderSummary>>(
  (ref) => ref.watch(repositoryProvider).getOrders(),
);
final alertsProvider = FutureProvider<List<Map<String, dynamic>>>(
  (ref) => ref.watch(repositoryProvider).getAlerts(),
);
