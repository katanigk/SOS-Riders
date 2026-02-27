// =============================================================
// PROJECT: email_verification_screen.dart
// DEPARTMENT 1 — Email Verification
// =============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'boot_screen.dart';

// =============================================================
// ROOM 1.1 — EmailVerificationScreen
// =============================================================

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState
    extends State<EmailVerificationScreen> {

  Timer? _timer;

  // =============================================================
  // ROOM 1.2 — Start Polling
  // =============================================================

  @override
  void initState() {
    super.initState();
    _startChecking();
  }

  void _startChecking() {
    _timer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final user = FirebaseAuth.instance.currentUser;
      await user?.reload();

      final refreshedUser = FirebaseAuth.instance.currentUser;

      if (refreshedUser != null && refreshedUser.emailVerified) {
        _timer?.cancel();

        if (!mounted) return;

        final email = refreshedUser.email;
        if (email != null) {
          try {
            await FirebaseFirestore.instance
                .collection('riders')
                .doc(refreshedUser.uid)
                .update({
              'email': email,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          } catch (_) {}
        }

        if (!mounted) return;

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const BootScreen()),
          (_) => false,
        );
      }
    });
  }

  // =============================================================
  // ROOM 1.3 — Dispose
  // =============================================================

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // =============================================================
  // ROOM 1.4 — UI
  // =============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("אימות מייל")),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            textDirection: TextDirection.rtl,
            children: [
              Text(
                "נשלח מייל אימות.\nיש לפתוח את המייל ולאשר.\n\nהאפליקציה תמשיך אוטומטית לאחר האישור.",
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: TextStyle(fontSize: 18),
              ),
              SizedBox(height: 24),
              CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
