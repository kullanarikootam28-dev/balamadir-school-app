import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:school_management_app/app.dart';
import 'package:school_management_app/config/supabase_config.dart';

Future<void> main() async {
  // ── Ensure Flutter engine is bound before any async work ──────────────────
  WidgetsFlutterBinding.ensureInitialized();

  // ── Phase 1: Supabase Global Initialization ───────────────────────────────
  // Replace the placeholder values below with your live Supabase dashboard
  // keys once you complete Phase 2 key injection.
  await Supabase.initialize(
    url: SupabaseConfig.projectUrl,
    anonKey: SupabaseConfig.anonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
    realtimeClientOptions: const RealtimeClientOptions(
      logLevel: RealtimeLogLevel.info,
    ),
  );

  runApp(
    // ── Riverpod ProviderScope wraps the entire widget tree ──────────────────
    const ProviderScope(
      child: SchoolManagementApp(),
    ),
  );
}

/// Convenience getter — access the Supabase client anywhere in the app.
SupabaseClient get supabase => Supabase.instance.client;
