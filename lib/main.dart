import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'timer_screen.dart';

const String _prefActiveKey = 'timer_active';
const String _prefEndMsKey = 'timer_end_ms';
const String _prefTotalKey = 'timer_total';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  int? initialEndMs;
  int? initialTotal;

  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_prefActiveKey) ?? false) {
    final em = prefs.getInt(_prefEndMsKey);
    final tt = prefs.getInt(_prefTotalKey);
    if (em != null && tt != null) {
      final e = DateTime.fromMillisecondsSinceEpoch(em);
      if (DateTime.now().isBefore(e)) {
        initialEndMs = em;
        initialTotal = tt;
      } else {
        await prefs.remove(_prefActiveKey);
        await prefs.remove(_prefEndMsKey);
        await prefs.remove(_prefTotalKey);
      }
    }
  }

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      systemNavigationBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(
    DotMatrixTimerApp(initialEndMs: initialEndMs, initialTotal: initialTotal),
  );
}

class DotMatrixTimerApp extends StatelessWidget {
  const DotMatrixTimerApp({super.key, this.initialEndMs, this.initialTotal});

  final int? initialEndMs;
  final int? initialTotal;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dot Matrix Timer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        canvasColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF39FF14),
          secondary: Color(0xFF39FF14),
          surface: Colors.black,
        ),
        textTheme: const TextTheme().apply(fontFamily: 'monospace'),
      ),
      home: TimerScreen(initialEndMs: initialEndMs, initialTotal: initialTotal),
    );
  }
}
