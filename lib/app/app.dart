import 'package:flutter/material.dart';

import '../screens/auth_gate.dart';
import 'app_state.dart';
import 'app_theme.dart';

class TcgSellerApp extends StatefulWidget {
  const TcgSellerApp({super.key});

  @override
  State<TcgSellerApp> createState() => _TcgSellerAppState();
}

class _TcgSellerAppState extends State<TcgSellerApp> {
  final AppState appState = AppState();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'TCG Seller',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: appState.themeMode,
          home: AuthGate(appState: appState),
        );
      },
    );
  }
}
