// =============================================================
// PROJECT: registration_screen.dart
// DEPARTMENT 1 — Email Registration (Step 1 Only)
// =============================================================

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'email_verification_screen.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {

  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _acceptedPrivacy = false;
  bool _loading = false;

  bool get _isValid {
    return _firstNameCtrl.text.isNotEmpty &&
        _lastNameCtrl.text.isNotEmpty &&
        _emailCtrl.text.contains('@') &&
        _passwordCtrl.text.length >= 6 &&
        _acceptedPrivacy;
  }

  // =============================================================
  // ROOM 1.1 — Register User + Save DisplayName
  // =============================================================

  Future<void> _register() async {
    setState(() => _loading = true);

    try {

      // 1️⃣ Create Auth User
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text.trim(),
      );

      final user = credential.user;

      // 2️⃣ Save Full Name inside FirebaseAuth
      final fullName =
          "${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}";

      await user?.updateDisplayName(fullName);

      // 3️⃣ Send Email Verification
      await user?.sendEmailVerification();

      if (!mounted) return;

      // 4️⃣ Go To Email Verification Screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const EmailVerificationScreen(),
        ),
      );

    } on FirebaseAuthException catch (e) {

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("שגיאה: ${e.message}")),
      );

    } catch (e) {

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("שגיאה כללית: $e")),
      );

    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // =============================================================
  // ROOM 1.2 — UI
  // =============================================================

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(title: const Text("הרשמה כריידר")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [

            TextField(
              controller: _firstNameCtrl,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(
                labelText: "שם פרטי",
                alignLabelWithHint: true,
              ),
              onChanged: (_) => setState(() {}),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: _lastNameCtrl,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(
                labelText: "שם משפחה",
                alignLabelWithHint: true,
              ),
              onChanged: (_) => setState(() {}),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: _emailCtrl,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(
                labelText: "מייל",
                alignLabelWithHint: true,
              ),
              onChanged: (_) => setState(() {}),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(
                labelText: "סיסמה",
                alignLabelWithHint: true,
              ),
              onChanged: (_) => setState(() {}),
            ),

            const SizedBox(height: 16),

            CheckboxListTile(
              value: _acceptedPrivacy,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (val) {
                setState(() => _acceptedPrivacy = val ?? false);
              },
              title: const Text("קראתי והבנתי את מדיניות הפרטיות"),
            ),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: (_isValid && !_loading) ? _register : null,
              child: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text("הירשם"),
            ),
          ],
        ),
      ),
    );
  }
}
