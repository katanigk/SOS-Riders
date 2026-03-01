// =============================================================
// PROJECT: waiting_approval_screen.dart
// מסך ממתין לאישור — רענון אוטומטי כשישתנה הסטטוס
// =============================================================

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'boot_screen.dart';

class WaitingApprovalScreen extends StatelessWidget {
  const WaitingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('שגיאה', textDirection: TextDirection.rtl)),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('riders').doc(uid).snapshots(),
      builder: (context, snap) {
        if (snap.hasData && snap.data!.exists) {
          final status = (snap.data!.data()?['status'] ?? 'pending').toString();
          if (status == 'active') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const BootScreen()),
                (_) => false,
              );
            });
          }
        }

        return Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "ממתין לאישור מנהל",
                  style: TextStyle(fontSize: 18),
                  textDirection: TextDirection.rtl,
                ),
                const SizedBox(height: 16),
                const Text(
                  "האפליקציה תמשיך אוטומטית לאחר האישור.",
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                  textDirection: TextDirection.rtl,
                ),
                const SizedBox(height: 24),
                const CircularProgressIndicator(),
              ],
            ),
          ),
        );
      },
    );
  }
}
