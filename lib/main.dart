import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'timer_screen.dart';

const String _prefActiveKey = 'timer_active';
const String _prefStartIndexKey = 'timer_start_index';
const String _prefStartMsKey = 'timer_start_ms';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  int? initialStartIndex;
  int? initialStartMs;

  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_prefActiveKey) ?? false) {
    final si = prefs.getInt(_prefStartIndexKey);
    final sm = prefs.getInt(_prefStartMsKey);
    if (si != null && sm != null) {
      final elapsed = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(sm));
      final duration = Duration(minutes: si + 1);
      if (elapsed < duration) {
        initialStartIndex = si;
        initialStartMs = sm;
      } else {
        await prefs.remove(_prefActiveKey);
        await prefs.remove(_prefStartIndexKey);
        await prefs.remove(_prefStartMsKey);
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
  runApp(DotMatrixTimerApp(
    initialStartIndex: initialStartIndex,
    initialStartMs: initialStartMs,
  ));
}

class DotMatrixTimerApp extends StatelessWidget {
  const DotMatrixTimerApp({
    super.key,
    this.initialStartIndex,
    this.initialStartMs,
  });

  final int? initialStartIndex;
  final int? initialStartMs;

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
        textTheme: const TextTheme().apply(
          fontFamily: 'monospace',
        ),
      ),
      home: TimerScreen(
        initialStartIndex: initialStartIndex,
        initialStartMs: initialStartMs,
      ),
    );
  }
}
