// =============================================================
// PROJECT: edit_profile_screen.dart
// DEPARTMENT 1 — Edit Profile (Field-by-Field Editing)
// =============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:rider_sos/models/rider_profile.dart';
import 'package:rider_sos/screens/email_verification_screen.dart';

class EditProfileScreen extends StatefulWidget {
  final RiderProfile profile;

  const EditProfileScreen({
    super.key,
    required this.profile,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _firstNameCtrl;
  late TextEditingController _lastNameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl;

  String? _editingField;
  bool _saving = false;

  List<String> _bikePhotoUrls = [];
  List<File?> _bikeReplacements = [null, null, null];
  int? _editingBikeIndex;

  String? _avatarUrl;
  File? _avatarReplacement;
  bool _avatarSaving = false;

  final ImagePicker _picker = ImagePicker();
  String? _phoneVerificationId;
  bool _phoneSmsSent = false;
  final TextEditingController _phoneCodeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _firstNameCtrl = TextEditingController(text: widget.profile.firstName);
    _lastNameCtrl = TextEditingController(text: widget.profile.lastName);
    _emailCtrl = TextEditingController(text: widget.profile.email);
    _phoneCtrl = TextEditingController(text: widget.profile.phone);
    _bikePhotoUrls = List.from(widget.profile.bikePhotoUrls);
    _avatarUrl = widget.profile.avatarUrl;
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _phoneCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveFirstName() async {
    final v = _firstNameCtrl.text.trim();
    if (v.isEmpty || v == widget.profile.firstName) {
      setState(() => _editingField = null);
      return;
    }
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('riders')
          .doc(widget.profile.uid)
          .update({
        'firstName': v,
        'fullName': '$v ${_lastNameCtrl.text.trim()}',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        setState(() {
          _editingField = null;
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('נשמר בהצלחה')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e')),
        );
      }
    }
  }

  Future<void> _saveLastName() async {
    final v = _lastNameCtrl.text.trim();
    if (v.isEmpty || v == widget.profile.lastName) {
      setState(() => _editingField = null);
      return;
    }
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('riders')
          .doc(widget.profile.uid)
          .update({
        'lastName': v,
        'fullName': '${_firstNameCtrl.text.trim()} $v',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        setState(() {
          _editingField = null;
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('נשמר בהצלחה')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e')),
        );
      }
    }
  }

  Future<void> _saveEmail() async {
    final newEmail = _emailCtrl.text.trim();
    if (newEmail.isEmpty || !newEmail.contains('@') || newEmail == widget.profile.email) {
      setState(() => _editingField = null);
      return;
    }
    setState(() => _saving = true);
    try {
      await FirebaseAuth.instance.currentUser!.verifyBeforeUpdateEmail(newEmail);
      if (mounted) {
        setState(() {
          _editingField = null;
          _saving = false;
        });
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const EmailVerificationScreen(),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: ${e.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e')),
        );
      }
    }
  }

  String _formatPhone(String raw) {
    final p = raw.replaceAll(RegExp(r'[^\d+]'), '');
    if (p.startsWith('+972')) return p;
    if (p.startsWith('972')) return '+$p';
    if (p.startsWith('0')) return '+972${p.substring(1)}';
    return '+972$p';
  }

  Future<void> _sendPhoneSms() async {
    final raw = _phoneCtrl.text.trim();
    if (raw.length < 9) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('מספר טלפון לא תקין')),
      );
      return;
    }
    setState(() => _saving = true);
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: _formatPhone(raw),
      verificationCompleted: (credential) async {
        await _applyPhoneCredential(credential);
      },
      verificationFailed: (e) {
        if (mounted) {
          setState(() => _saving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('שגיאה: ${e.message}')),
          );
        }
      },
      codeSent: (id, _) {
        if (mounted) {
          setState(() {
            _phoneVerificationId = id;
            _phoneSmsSent = true;
            _saving = false;
          });
        }
      },
      codeAutoRetrievalTimeout: (id) {
        _phoneVerificationId = id;
      },
    );
  }

  Future<void> _verifyPhoneCode() async {
    if (_phoneVerificationId == null) return;
    setState(() => _saving = true);
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _phoneVerificationId!,
        smsCode: _phoneCodeCtrl.text.trim(),
      );
      await _applyPhoneCredential(credential);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('קוד שגוי')),
        );
      }
    }
  }

  Future<void> _applyPhoneCredential(PhoneAuthCredential credential) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    try {
      await user.updatePhoneNumber(credential);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('לא ניתן לעדכן טלפון')),
        );
      }
      return;
    }
    final phone = _formatPhone(_phoneCtrl.text.trim());
    await FirebaseFirestore.instance
        .collection('riders')
        .doc(widget.profile.uid)
        .update({
      'phone': phone,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (mounted) {
      setState(() {
        _editingField = null;
        _phoneSmsSent = false;
        _phoneVerificationId = null;
        _phoneCodeCtrl.clear();
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('טלפון עודכן בהצלחה')),
      );
    }
  }

  Future<void> _replaceAvatar() async {
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
      imageQuality: 85,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (img == null) return;

    setState(() {
      _avatarReplacement = File(img.path);
      _avatarSaving = true;
    });
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('riders/${widget.profile.uid}/avatar.jpg');
      await ref.putFile(File(img.path));
      final url = await ref.getDownloadURL();
      await RiderProfile.updateAvatar(url);
      if (mounted) {
        setState(() {
          _avatarUrl = url;
          _avatarReplacement = null;
          _avatarSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('תמונת פרופיל עודכנה בהצלחה')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _avatarSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e')),
        );
      }
    }
  }

  Future<void> _replaceBikePhoto(int index) async {
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
      _bikeReplacements[index] = File(img.path);
      _editingBikeIndex = null;
    });
    _saving = true;
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('riders/${widget.profile.uid}/bike_$index.jpg');
      await ref.putFile(File(img.path));
      final url = await ref.getDownloadURL();
      final urls = List<String>.from(_bikePhotoUrls);
      while (urls.length <= index) {
        urls.add('');
      }
      urls[index] = url;
      await FirebaseFirestore.instance
          .collection('riders')
          .doc(widget.profile.uid)
          .update({
        'bikePhotoUrls': urls,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        setState(() {
          _bikePhotoUrls = urls;
          _bikeReplacements[index] = null;
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('תמונה עודכנה בהצלחה')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('עריכת פרופיל ריידר')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: GestureDetector(
                onTap: _avatarSaving ? null : _replaceAvatar,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircleAvatar(
                      radius: 52,
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      backgroundImage: _avatarReplacement != null
                          ? FileImage(_avatarReplacement!)
                          : _avatarUrl != null && _avatarUrl!.isNotEmpty
                              ? NetworkImage(_avatarUrl!)
                              : null,
                      child: _avatarReplacement == null &&
                              (_avatarUrl == null || _avatarUrl!.isEmpty)
                          ? Text(
                              widget.profile.fullName.isNotEmpty
                                  ? widget.profile.fullName[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                fontSize: 36,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            )
                          : null,
                    ),
                    if (_avatarSaving)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black38,
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          child: Icon(
                            Icons.camera_alt,
                            size: 20,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildEditableField(
              label: 'שם פרטי',
              controller: _firstNameCtrl,
              fieldKey: 'firstName',
              onSave: _saveFirstName,
            ),
            const SizedBox(height: 16),
            _buildEditableField(
              label: 'שם משפחה',
              controller: _lastNameCtrl,
              fieldKey: 'lastName',
              onSave: _saveLastName,
            ),
            const SizedBox(height: 16),
            _buildEditableField(
              label: 'מייל',
              controller: _emailCtrl,
              fieldKey: 'email',
              onSave: _saveEmail,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            _buildPhoneField(),
            const SizedBox(height: 24),
            const Align(
              alignment: Alignment.centerRight,
              child: Text(
                'תמונות הכלי',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (int i = 0; i < 3; i++) _buildBikePhotoEdit(i),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditableField({
    required String label,
    required TextEditingController controller,
    required String fieldKey,
    required VoidCallback onSave,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final isEditing = _editingField == fieldKey;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: isEditing
                  ? TextField(
                      controller: controller,
                      enabled: !_saving,
                      keyboardType: keyboardType,
                      textAlign: TextAlign.right,
                      textDirection: TextDirection.rtl,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    )
                  : Text(
                      controller.text,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
            IconButton(
              onPressed: _saving
                  ? null
                  : () {
                      if (isEditing) {
                        onSave();
                      } else {
                        setState(() => _editingField = fieldKey);
                      }
                    },
              icon: Icon(isEditing ? Icons.check : Icons.edit),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPhoneField() {
    final isEditing = _editingField == 'phone';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'טלפון',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        if (!isEditing)
          Row(
            children: [
              Expanded(
                child: Text(
                  _phoneCtrl.text,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              IconButton(
                onPressed: _saving ? null : () => setState(() => _editingField = 'phone'),
                icon: const Icon(Icons.edit),
              ),
            ],
          )
        else ...[
          TextField(
            controller: _phoneCtrl,
            enabled: !_phoneSmsSent && !_saving,
            keyboardType: TextInputType.phone,
            textAlign: TextAlign.right,
            textDirection: TextDirection.rtl,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          if (!_phoneSmsSent)
            ElevatedButton(
              onPressed: _saving ? null : _sendPhoneSms,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('שלח קוד אימות'),
            )
          else ...[
            TextField(
              controller: _phoneCodeCtrl,
              enabled: !_saving,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(
                labelText: 'קוד אימות',
                isDense: true,
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _saving ? null : _verifyPhoneCode,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('אמת קוד'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _saving
                      ? null
                      : () {
                          setState(() {
                            _editingField = null;
                            _phoneSmsSent = false;
                            _phoneVerificationId = null;
                            _phoneCodeCtrl.clear();
                          });
                        },
                  child: const Text('ביטול'),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildBikePhotoEdit(int index) {
    final url = _bikePhotoUrls.length > index ? _bikePhotoUrls[index] : null;
    final replacement = _bikeReplacements[index];
    final isEditing = _editingBikeIndex == index;
    return Column(
      children: [
        GestureDetector(
          onTap: () {
            if (isEditing) {
              _replaceBikePhoto(index);
            } else {
              setState(() => _editingBikeIndex = index);
            }
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 80,
              height: 80,
              color: Colors.grey.shade200,
              child: replacement != null
                  ? Image.file(replacement, fit: BoxFit.cover)
                  : url != null
                      ? Image.network(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.broken_image),
                        )
                      : const Icon(Icons.add_photo_alternate),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'תמונה ${index + 1}',
          style: const TextStyle(fontSize: 12),
        ),
        if (isEditing)
          TextButton(
            onPressed: _saving ? null : () => _replaceBikePhoto(index),
            child: const Text('החלף'),
          ),
      ],
    );
  }
}
