import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/app_state.dart';
import '../app/providers.dart';
import '../navigation/main_navigation.dart';
import 'login_screen.dart';
import 'page_selection_screen.dart';

class AuthGate extends ConsumerWidget {
  final AppState appState;
  const AuthGate({super.key, required this.appState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authStateProvider);
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return const LoginScreen();
    return ref
        .watch(selectedPageProvider)
        .when(
          data: (page) => page == null
              ? PageSelectionScreen(appState: appState)
              : MainNavigation(appState: appState),
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (error, _) => PageSelectionScreen(
            appState: appState,
            initialError: error.toString(),
          ),
        );
  }
}
