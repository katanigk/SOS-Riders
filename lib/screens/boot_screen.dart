// =============================================================
// PROJECT: boot_screen.dart
// DEPARTMENT 1 — App Router (Single Entry Point)
// =============================================================

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'login_screen.dart';
import 'registration_screen.dart';
import 'email_verification_screen.dart';
import 'complete_profile_screen.dart';
import 'home_screen.dart';
import 'waiting_approval_screen.dart';
import 'blocked_screen.dart';

import '../models/rider_profile.dart';

// =============================================================
// ROOM 1.1 — BootScreen
// =============================================================

class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> {
  bool _loading = true;
  Widget? _nextScreen;

  @override
  void initState() {
    super.initState();
    _decideRoute();
  }

  // =============================================================
  // ROOM 1.2 — Decision Tree (Original Flow)
  // =============================================================

  Future<void> _decideRoute() async {
    try {
      final auth = FirebaseAuth.instance;
      final user = auth.currentUser;

      // -----------------------------------------------------------
      // CASE 1 — No user → Login
      // -----------------------------------------------------------
      if (user == null) {
        _setNext(const LoginScreen());
        return;
      }

      // Refresh user
      await user.reload();
      final refreshedUser = auth.currentUser;

      if (refreshedUser == null) {
        _setNext(const RegistrationScreen());
        return;
      }

      // -----------------------------------------------------------
      // CASE 2 — Email missing → Registration
      // -----------------------------------------------------------
      if (refreshedUser.email == null) {
        _setNext(const RegistrationScreen());
        return;
      }

      // -----------------------------------------------------------
      // CASE 3 — Email not verified
      // -----------------------------------------------------------
      if (!refreshedUser.emailVerified) {
        _setNext(const EmailVerificationScreen());
        return;
      }

      final uid = refreshedUser.uid;

      // -----------------------------------------------------------
      // CASE 4 — Rider document missing → Complete Profile
      // -----------------------------------------------------------
      final riderDoc = await FirebaseFirestore.instance
          .collection('riders')
          .doc(uid)
          .get();

      if (!riderDoc.exists) {
        _setNext(const CompleteProfileScreen());
        return;
      }

      // -----------------------------------------------------------
      // CASE 5 — Load profile
      // -----------------------------------------------------------
      final profile = await RiderProfile.loadCurrent();

      if (profile == null) {
        _setNext(const CompleteProfileScreen());
        return;
      }

      // -----------------------------------------------------------
      // CASE 6 — Status check
      // -----------------------------------------------------------
      final status = profile.status ?? "pending";

      if (status == "pending") {
        _setNext(const WaitingApprovalScreen());
        return;
      }

      if (status == "blocked") {
        _setNext(const BlockedScreen());
        return;
      }

      // -----------------------------------------------------------
      // CASE 7 — ACTIVE → Home
      // -----------------------------------------------------------
      _setNext(HomeScreen(profile: profile));
    } catch (e) {
      debugPrint("BOOT ERROR: $e");
      _setNext(const RegistrationScreen());
    }
  }

  // =============================================================
  // ROOM 1.3 — Safe Navigation
  // =============================================================

  void _setNext(Widget screen) {
    if (!mounted) return;
    setState(() {
      _nextScreen = screen;
      _loading = false;
    });
  }

  // =============================================================
  // ROOM 1.4 — UI
  // =============================================================

  @override
  Widget build(BuildContext context) {
    if (_loading || _nextScreen == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return _nextScreen!;
  }
}
