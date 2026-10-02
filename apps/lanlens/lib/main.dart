import 'package:flutter/material.dart';

import 'app/home_screen.dart';
import 'ui/theme.dart';

void main() => runApp(const LanLensApp());

class LanLensApp extends StatelessWidget {
  const LanLensApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'LanLens',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: const HomeScreen(),
      );
}
