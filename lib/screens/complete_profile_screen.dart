// =============================================================
// PROJECT: complete_profile_screen.dart
// DEPARTMENT 1 — Complete Profile (Step 2)
// =============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/rider_profile.dart';
import 'boot_screen.dart';

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() =>
      _CompleteProfileScreenState();
}

class _CompleteProfileScreenState
    extends State<CompleteProfileScreen> {

  final ImagePicker _picker = ImagePicker();

  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  List<File?> _images = [null, null, null];

  String? _verificationId;
  bool _smsSent = false;
  bool _loading = false;

  String get _displayName {
    return FirebaseAuth.instance.currentUser?.displayName ?? "";
  }

  bool get _imagesReady =>
      _images.where((e) => e != null).length == 3;

  bool get _canSendSms =>
      _phoneCtrl.text.length >= 9;

  // =============================================================
  // ROOM 1.1 — Pick Image (Camera or Gallery)
  // =============================================================

  Future<void> _pickImage(int index) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('צלם תמונה'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('בחר מהגלריה'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final img = await _picker.pickImage(
      source: source,
      imageQuality: 75,
    );

    if (img == null) return;

    setState(() {
      _images[index] = File(img.path);
    });
  }

  // =============================================================
  // ROOM 1.2 — Send SMS
  // =============================================================

  Future<void> _sendSms() async {

    setState(() => _loading = true);

    final raw = _phoneCtrl.text.trim();

    String formatted;

    if (raw.startsWith('+972')) {
      formatted = raw;
    } else if (raw.startsWith('0')) {
      formatted = '+972${raw.substring(1)}';
    } else {
      formatted = '+972$raw';
    }

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: formatted,
      verificationCompleted: (credential) async {
        await FirebaseAuth.instance.currentUser!
            .linkWithCredential(credential);
        await _finishRegistration();
      },
      verificationFailed: (e) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("שגיאה: ${e.message}")),
        );
      },
      codeSent: (id, _) {
        _verificationId = id;
        setState(() {
          _smsSent = true;
          _loading = false;
        });
      },
      codeAutoRetrievalTimeout: (id) {
        _verificationId = id;
      },
    );
  }

  // =============================================================
  // ROOM 1.3 — Verify Code
  // =============================================================

  Future<void> _verifyCode() async {

    if (_verificationId == null) return;

    setState(() => _loading = true);

    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId!,
      smsCode: _codeCtrl.text.trim(),
    );

    await FirebaseAuth.instance.currentUser!
        .linkWithCredential(credential);

    await _finishRegistration();
  }

  // =============================================================
  // ROOM 1.4 — Create Rider Officially
  // =============================================================

  Future<void> _finishRegistration() async {

    final user = FirebaseAuth.instance.currentUser!;
    final nameParts = _displayName.trim().split(RegExp(r'\s+'));
    final firstName = nameParts.isNotEmpty ? nameParts.first : '';
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
    final raw = _phoneCtrl.text.trim();
    String phone;
    if (raw.startsWith('+972')) {
      phone = raw;
    } else if (raw.startsWith('0')) {
      phone = '+972${raw.substring(1)}';
    } else {
      phone = '+972$raw';
    }
    final images = _images.whereType<File>().toList();

    await RiderProfile.create(
      firstName: firstName,
      lastName: lastName,
      email: user.email!,
      phone: phone,
      bikeImages: images,
    );


    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const BootScreen()),
      (_) => false,
    );
  }

  // =============================================================
  // ROOM 1.5 — UI
  // =============================================================

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(title: const Text("השלמת פרופיל ריידר")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            textDirection: TextDirection.rtl,
            children: [
              Text(
                "שלום $_displayName 👋",
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 24),

              const Text("העלה 3 תמונות של הכלי שלך"),

              const SizedBox(height: 12),

              for (int i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ElevatedButton.icon(
                    icon: Icon(
                      _images[i] != null
                          ? Icons.check_circle
                          : Icons.upload,
                    ),
                    label: Text(
                      _images[i] != null
                          ? "תמונה ${i + 1} הועלתה ✔"
                          : "העלה תמונה ${i + 1}",
                    ),
                    onPressed: () => _pickImage(i),
                  ),
                ),

              const SizedBox(height: 20),

              TextField(
                controller: _phoneCtrl,
                textAlign: TextAlign.right,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  labelText: "מספר טלפון לאימות",
                  alignLabelWithHint: true,
                ),
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: 12),

              if (!_smsSent)
                ElevatedButton(
                  onPressed:
                      (_imagesReady && _canSendSms && !_loading)
                          ? _sendSms
                          : null,
                  child: _loading
                      ? const CircularProgressIndicator()
                      : const Text("שלח קוד אימות"),
                ),

              if (_smsSent) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _codeCtrl,
                  textAlign: TextAlign.right,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(
                    labelText: "הכנס קוד אימות",
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _loading ? null : _verifyCode,
                  child: _loading
                      ? const CircularProgressIndicator()
                      : const Text("אמת וסיים הרשמה"),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
