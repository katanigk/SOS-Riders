// =============================================================
// PROJECT: rider_profile.dart
// DEPARTMENT 1 — Model (Single Source of Truth)
// =============================================================

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

// =============================================================
// ROOM 1.1 — RiderProfile Model
// =============================================================

class RiderProfile {
  final String uid;
  final String firstName;
  final String lastName;
  final String fullName;
  final String email;
  final String phone;
  final List<String> bikePhotoUrls;
  final String? avatarUrl;
  final String status; // pending / active / blocked
  final String? fcmToken;

  const RiderProfile({
    required this.uid,
    required this.firstName,
    required this.lastName,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.bikePhotoUrls,
    this.avatarUrl,
    required this.status,
    required this.fcmToken,
  });

  // =============================================================
  // ROOM 1.2 — Create Profile
  // =============================================================

  static Future<RiderProfile> create({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required List<File> bikeImages,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception("User not authenticated");
    }

    if (bikeImages.length != 3) {
      throw Exception("Exactly 3 bike images required");
    }

    final uid = user.uid;
    final fullName = "$firstName $lastName";

    // ---------------- STORAGE ----------------
    final storage = FirebaseStorage.instance;
    List<String> urls = [];

    for (int i = 0; i < 3; i++) {
      final ref = storage.ref().child('riders/$uid/bike_$i.jpg');
      await ref.putFile(bikeImages[i]);
      final url = await ref.getDownloadURL();
      urls.add(url);
    }

    // ---------------- FIRESTORE ----------------
    final now = FieldValue.serverTimestamp();

    await FirebaseFirestore.instance
        .collection('riders')
        .doc(uid)
        .set({
      'uid': uid,
      'firstName': firstName,
      'lastName': lastName,
      'fullName': fullName,
      'email': email,
      'phone': phone,
      'bikePhotoUrls': urls,
      'status': 'pending', // 👈 חשוב
      'createdAt': now,
      'updatedAt': now,
      'fcmToken': null,
    });

    return RiderProfile(
      uid: uid,
      firstName: firstName,
      lastName: lastName,
      fullName: fullName,
      email: email,
      phone: phone,
      bikePhotoUrls: urls,
      avatarUrl: null,
      status: 'pending',
      fcmToken: null,
    );
  }

  // =============================================================
  // ROOM 1.3 — Load Current Profile
  // =============================================================

  static Future<RiderProfile?> loadCurrent() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final doc = await FirebaseFirestore.instance
        .collection('riders')
        .doc(user.uid)
        .get();

    if (!doc.exists) return null;

    final data = doc.data()!;

    return RiderProfile(
      uid: data['uid'],
      firstName: data['firstName'],
      lastName: data['lastName'],
      fullName: data['fullName'],
      email: data['email'],
      phone: data['phone'],
      bikePhotoUrls: List<String>.from(data['bikePhotoUrls'] ?? []),
      avatarUrl: data['avatarUrl'] as String?,
      status: data['status'] ?? 'pending',
      fcmToken: data['fcmToken'],
    );
  }

  // =============================================================
  // ROOM 1.4a — Update Avatar
  // =============================================================

  static Future<void> updateAvatar(String url) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('riders').doc(user.uid).update({
      'avatarUrl': url,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // =============================================================
  // ROOM 1.4 — Update FCM Token
  // =============================================================

  static Future<void> updateFcmToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('riders')
        .doc(user.uid)
        .update({
      'fcmToken': token,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
