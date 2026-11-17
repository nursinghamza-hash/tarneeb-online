import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TarneebOnlineApp());
}

class TarneebOnlineApp extends StatelessWidget {
  const TarneebOnlineApp({super.key});

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFE2BD68);
    return MaterialApp(
      title: 'تحدي الطرنيب',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF071A18),
        colorScheme: ColorScheme.fromSeed(
          seedColor: gold,
          brightness: Brightness.dark,
          primary: gold,
          secondary: const Color(0xFF146047),
          surface: const Color(0xFF12372F),
        ),
        fontFamily: 'Roboto',
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF12372F),
          contentTextStyle: TextStyle(color: Colors.white),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
