import 'package:flutter/material.dart';

import 'app/settings_store.dart';
import 'ui/guardian_gate.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await SettingsStore.load();
  runApp(ManmanxiangApp(settings: settings));
}

class ManmanxiangApp extends StatelessWidget {
  const ManmanxiangApp({super.key, required this.settings});

  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '慢慢想',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3F8F6B)),
        useMaterial3: true,
        visualDensity: VisualDensity.comfortable,
      ),
      home: ListenableBuilder(
        listenable: settings,
        builder: (context, _) =>
            settings.guardianConfirmed ? HomePage(settings: settings) : GuardianGate(settings: settings),
      ),
    );
  }
}
