import 'package:flutter/material.dart';

class BlockedScreen extends StatelessWidget {
  const BlockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          "החשבון נחסם. צור קשר עם מנהל.",
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
