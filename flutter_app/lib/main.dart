import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const TarneebOnlineApp());
}

class TarneebOnlineApp extends StatelessWidget {
  const TarneebOnlineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tarneeb Online',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}
