import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zc_bangumi/pages/subject_tag_page.dart';
import 'package:zc_bangumi/providers/app_state_provider.dart';
import 'package:zc_bangumi/providers/auth_provider.dart';
import 'package:zc_bangumi/providers/connectivity_provider.dart';
import 'package:zc_bangumi/providers/mikan_provider.dart';
import 'package:zc_bangumi/services/api_client.dart';
import 'package:zc_bangumi/services/mikan_service.dart';
import 'package:zc_bangumi/services/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setPrefix('tag_smoke.');
  final storage = StorageService();
  await storage.init();
  await storage.setMikanEnabled(false);
  final api = ApiClient();

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        Provider<StorageService>.value(value: storage),
        ChangeNotifierProvider(
          create: (_) => AppStateProvider(storage: storage),
        ),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(api: api, storage: storage),
        ),
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
        ChangeNotifierProvider(
          create: (_) =>
              MikanProvider(service: MikanService(), storage: storage),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFF09199)),
          useMaterial3: true,
        ),
        home: const SubjectTagPage(),
      ),
    ),
  );
}
