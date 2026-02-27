// =============================================================
// PROJECT: auth_service.dart
// DEPARTMENT 1 — Centralized Authentication Logic
// =============================================================

import 'package:firebase_auth/firebase_auth.dart';

class AuthService {

  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // =============================================================
  // ROOM 1.1 — Register with Email
  // =============================================================

  static Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
  }) async {

    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    await credential.user!.sendEmailVerification();

    return credential;
  }

  // =============================================================
  // ROOM 1.2 — Reload User
  // =============================================================

  static Future<void> reloadUser() async {
    await _auth.currentUser?.reload();
  }

  // =============================================================
  // ROOM 1.3 — Logout
  // =============================================================

  static Future<void> logout() async {
    await _auth.signOut();
  }
}
