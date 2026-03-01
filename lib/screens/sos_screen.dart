// =============================================================
// PROJECT: sos_screen.dart
// =============================================================

// =============================================================
// DEPARTMENT 8 — SOS Active Event (Screen)
// =============================================================

// -------------------------------------------------------------
// Room 8.1 — Imports
// -------------------------------------------------------------
import 'dart:io';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:rider_sos/models/rider_profile.dart';

// =============================================================
// DEPARTMENT 9 — SOS Active Event Widget
// =============================================================

// -------------------------------------------------------------
// Room 9.1 — Widget
// -------------------------------------------------------------
class SosScreen extends StatefulWidget {
  final String eventId;
  final RiderProfile profile;
  /// true = אירוע סגור (צפייה בלבד), false = אירוע פתוח (פעיל)
  final bool isClosed;

  const SosScreen({
    super.key,
    required this.eventId,
    required this.profile,
    this.isClosed = false,
  });

  @override
  State<SosScreen> createState() => _SosScreenState();
}

// =============================================================
// DEPARTMENT 10 — State & Core Logic
// =============================================================
class _SosScreenState extends State<SosScreen> {
  // -----------------------------------------------------------
  // Room 10.1 — Local flags
  // -----------------------------------------------------------
  bool _didPop = false;

  // classification
  bool _classificationLocked = false;
  Timer? _classificationTimer;

  // close button
  bool _closingHolding = false;
  bool _closingTriggered = false;
  Timer? _closeTimer;
  int _holdToken = 0;

  // live location (רק יוזם מעדכן מיקום באירוע)
  Timer? _locationTimer;
  bool _liveLocationStarted = false;

  // chat
  final TextEditingController _chatCtrl = TextEditingController();
  bool _sendingMsg = false;
  final ImagePicker _imagePicker = ImagePicker();

  // -----------------------------------------------------------
  // Room 10.2 — Safe pop
  // -----------------------------------------------------------
  void _safePopTrue() {
    if (!mounted || _didPop) return;
    _didPop = true;
    Navigator.of(context).pop(true);
  }

  String get _eventsCollection =>
      widget.isClosed ? 'sos_events_closed' : 'sos_events_open';

  Stream<DocumentSnapshot<Map<String, dynamic>>> _eventStream() {
    return FirebaseFirestore.instance
        .collection(_eventsCollection)
        .doc(widget.eventId)
        .snapshots();
  }

  // -----------------------------------------------------------
  // Room 10.4 — Auto-exit if closed (מנקים activeEventId אצל הרוכב)
  // -----------------------------------------------------------
  void _handleAutoExit(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (widget.isClosed) return;
    final data = snap.data();
    if (data == null) return;
    if (data['status'] != 'closed') return;

    final uid = widget.profile.uid;
    FirebaseFirestore.instance.collection('riders').doc(uid).update({
      'activeEventId': FieldValue.delete(),
      'activeEventRole': FieldValue.delete(),
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _safePopTrue();
    });
  }

  // ===========================================================
  // === CRITICAL START — CLASSIFICATION LOGIC ==================
  // ===========================================================

  // -----------------------------------------------------------
  // Room 10.5 — Start classification timer (40s)
  // RULE:
  //  - רק היוזם מפעיל את ה-timeout; מגיב שנכנס לחדר לא ידרוס סיווג קיים
  //  - אם היוזם לא סיווג תוך 40 שניות → "ללא_סיווג"
  // -----------------------------------------------------------
  void _startClassificationTimer() {
    _classificationTimer?.cancel();

    _classificationTimer = Timer(const Duration(seconds: 40), () async {
      if (!mounted || _classificationLocked) return;

      final eventRef = FirebaseFirestore.instance
          .collection(_eventsCollection)
          .doc(widget.eventId);
      final snap = await eventRef.get();
      if (!mounted) return;
      final d = snap.data();
      if (d == null) return;
      if (d['classification'] != null) return;
      if (d['initiatorUid'] != widget.profile.uid) return;

      final initiatorLat = (d['initiatorLat'] as num?)?.toDouble();
      final initiatorLng = (d['initiatorLng'] as num?)?.toDouble();

      String? nearestResponderUid;
      String? nearestResponderPhone;
      double nearestDist = double.infinity;

      if (initiatorLat != null && initiatorLng != null) {
        final respondersSnap = await eventRef.collection('responders').get();
        int nearestJoinedAt = 0;
        for (final r in respondersSnap.docs) {
          final ruid = r.data()['uid'] as String?;
          if (ruid == null) continue;
          final pre = await FirebaseFirestore.instance
              .collection('rider_presence')
              .doc(ruid)
              .get();
          final pdata = pre.data();
          final rlat = (pdata?['lat'] as num?)?.toDouble();
          final rlng = (pdata?['lng'] as num?)?.toDouble();
          if (rlat == null || rlng == null) continue;
          final dist = Geolocator.distanceBetween(
            initiatorLat, initiatorLng, rlat, rlng,
          );
          final joinedAt = (r.data()['joinedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          final isCloser = dist < nearestDist;
          final isTie = (dist - nearestDist).abs() < 1;
          final isFirstResponder = isTie && joinedAt < nearestJoinedAt;
          if (isCloser || isFirstResponder) {
            nearestDist = dist;
            nearestJoinedAt = joinedAt;
            nearestResponderUid = ruid;
            nearestResponderPhone = r.data()['phone'] as String?;
          }
        }
      }

      await eventRef.update({
        'classification': 'מצוקה רציני משולב',
        'classificationAt': FieldValue.serverTimestamp(),
        'managerUid': nearestResponderUid,
        'managerPhone': nearestResponderPhone,
        'managerType': nearestResponderUid != null ? 'auto_nearest_responder' : 'auto_unclassified',
        'managerAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // -----------------------------------------------------------
  // Room 10.6 — Set classification (initiator only)
  // -----------------------------------------------------------
  Future<void> _setClassification(String value) async {
    if (_classificationLocked) return;

    _classificationLocked = true;
    _classificationTimer?.cancel();

    await FirebaseFirestore.instance
        .collection(_eventsCollection)
        .doc(widget.eventId)
        .update({
      'classification': value,
      'classificationAt': FieldValue.serverTimestamp(),
      'managerUid': widget.profile.uid,
      'managerPhone': widget.profile.phone,
      'managerType': 'initiator_classified',
    });
  }

  // ===========================================================
  // === CRITICAL END — CLASSIFICATION LOGIC ====================
  // ===========================================================

  // ===========================================================
  // === CRITICAL START — MANAGER CLAIM (Responder First) =======
  // ===========================================================
  // -----------------------------------------------------------
  // Room 10.6.1 — Attempt claim manager if event is unclassified
  // RULE:
  //  - רק מי שלחץ "אני בדרך" (כלומר יש responders/{phone}) יכול לתבוע
  //  - תביעה מתבצעת רק אם managerPhone עדיין null && managerType=auto_unclassified
  // -----------------------------------------------------------
  Future<void> _tryClaimManagerIfNeeded({
    required String? managerPhone,
    required String? managerType,
  }) async {
    if (managerPhone != null) return;
    if (managerType != 'auto_unclassified') return;

    final uid = widget.profile.uid;
    final mePhone = widget.profile.phone;

    final responderDoc = await FirebaseFirestore.instance
        .collection(_eventsCollection)
        .doc(widget.eventId)
        .collection('responders')
        .doc(uid)
        .get();

    if (!responderDoc.exists) return;

    final eventRef =
        FirebaseFirestore.instance.collection(_eventsCollection).doc(widget.eventId);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(eventRef);
      final d = snap.data();
      if (d == null) return;

      final curManager = d['managerPhone'];
      final curType = d['managerType'];

      if (curManager != null) return;
      if (curType != 'auto_unclassified') return;

      tx.update(eventRef, {
        'managerUid': uid,
        'managerPhone': mePhone,
        'managerType': 'responder_first',
        'managerAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // ===========================================================
  // === CRITICAL END — MANAGER CLAIM (Responder First) =========
  // ===========================================================

  // ===========================================================
  // === CRITICAL START — LIVE LOCATION =========================
  // ===========================================================

  // -----------------------------------------------------------
  // Room 10.7 — Start live location updates (יוזם בלבד, כל 17 שניות)
  // -----------------------------------------------------------
  void _startLiveLocationIfInitiator(bool isInitiator, String? status) {
    if (_liveLocationStarted || !isInitiator || status != 'open') return;
    _liveLocationStarted = true;

    _locationTimer?.cancel();
    const interval = Duration(seconds: 10);
    _locationTimer = Timer.periodic(interval, (_) => _refreshEventLocation());
    // עדכון ראשון מיד
    _refreshEventLocation();
  }

  static String _formatAddress(Placemark? p, double? lat, double? lng) {
    if (p != null) {
      final parts = [
        p.street,
        p.thoroughfare,
        p.subThoroughfare,
        p.subLocality,
        p.locality,
      ].whereType<String>().where((s) => s.trim().isNotEmpty);
      final addr = parts.join(', ').trim();
      if (addr.isNotEmpty) return addr;
    }
    if (lat != null && lng != null) {
      return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
    }
    return '';
  }

  Future<void> _refreshEventLocation() async {
    if (!mounted) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
      );
      final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      final p = placemarks.isNotEmpty ? placemarks.first : null;
      final address = _formatAddress(p, pos.latitude, pos.longitude);
      if (!mounted) return;
      await FirebaseFirestore.instance
          .collection(_eventsCollection)
          .doc(widget.eventId)
          .update({
        'initiatorAddress': address.isEmpty ? null : address,
        'initiatorLat': pos.latitude,
        'initiatorLng': pos.longitude,
        'locationUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  // ===========================================================
  // === CRITICAL END — LIVE LOCATION ===========================
  // ===========================================================

  // ===========================================================
  // === CRITICAL START — CLOSE EVENT ===========================
  // ===========================================================

  // -----------------------------------------------------------
  // Room 10.8 — Close event
  // -----------------------------------------------------------
  Future<void> _closeEvent() async {
    final eventId = widget.eventId;
    final openRef = FirebaseFirestore.instance.collection('sos_events_open').doc(eventId);
    final closedRef = FirebaseFirestore.instance.collection('sos_events_closed').doc(eventId);

    final eventSnap = await openRef.get();
    if (!eventSnap.exists) {
      _safePopTrue();
      return;
    }
    final eventData = Map<String, dynamic>.from(eventSnap.data()!);
    eventData['status'] = 'closed';
    eventData['closedAt'] = FieldValue.serverTimestamp();
    eventData['closedBy'] = widget.profile.phone;

    final respondersSnap = await openRef.collection('responders').get();
    final initiatorUid = eventData['initiatorUid'] as String?;
    List<String> pids = List<String>.from(
        eventData['participantIds'] as List<dynamic>? ?? []);
    if (pids.isEmpty && initiatorUid != null) {
      pids = [initiatorUid];
      for (final doc in respondersSnap.docs) {
        final u = doc.data()['uid'] as String?;
        if (u != null && !pids.contains(u)) pids.add(u);
      }
      eventData['participantIds'] = pids;
    }

    final batch = FirebaseFirestore.instance.batch();

    batch.set(closedRef, eventData);

    for (final doc in respondersSnap.docs) {
      batch.set(closedRef.collection('responders').doc(doc.id), doc.data());
    }
    final messagesSnap = await openRef.collection('messages').get();
    for (final doc in messagesSnap.docs) {
      batch.set(closedRef.collection('messages').doc(doc.id), doc.data());
    }

    // מוחק רק את מסמך האירוע — ה-responders ו-messages יישארו יתומים (ה-rules לא מאפשרים מחיקתם)
    batch.delete(openRef);

    await batch.commit();

    // מנקה activeEventId של הסוגר (ה-rules מאפשרים עדכון רק לעצמך)
    final myUid = widget.profile.uid;
    await FirebaseFirestore.instance.collection('riders').doc(myUid).update({
      'activeEventId': FieldValue.delete(),
      'activeEventRole': FieldValue.delete(),
    });

    _safePopTrue();
  }

  // -----------------------------------------------------------
  // Room 10.9 — Hold start
  // -----------------------------------------------------------
  void _onHoldStart() {
    if (_closingTriggered) return;

    HapticFeedback.lightImpact();
    final token = ++_holdToken;

    setState(() => _closingHolding = true);

    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(seconds: 2), () async {
      if (!mounted || token != _holdToken) return;

      HapticFeedback.heavyImpact();
      setState(() {
        _closingTriggered = true;
        _closingHolding = false;
      });

      await _closeEvent();
    });
  }

  // -----------------------------------------------------------
  // Room 10.10 — Hold cancel
  // -----------------------------------------------------------
  void _onHoldEnd() {
    _holdToken++;
    _closeTimer?.cancel();
    if (!mounted) return;
    setState(() => _closingHolding = false);
  }

  // ===========================================================
  // === CRITICAL END — CLOSE EVENT =============================
  // ===========================================================

  // ===========================================================
  // === CRITICAL START — CHAT ================================
  // ===========================================================

  // -----------------------------------------------------------
  // Room 10.12 — Chat messages stream
  // PATH:
  //  sos_events/{eventId}/messages/{messageId}
  // -----------------------------------------------------------
  Stream<QuerySnapshot<Map<String, dynamic>>> _chatStream() {
    return FirebaseFirestore.instance
        .collection(_eventsCollection)
        .doc(widget.eventId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(80)
        .snapshots();
  }

  // -----------------------------------------------------------
  // Room 10.13 — Can write chat
  // RULE:
  //  - רק מי שלחץ "אני בדרך" יכול לכתוב תמיד
  //  - היוזם חסום אם לא סיווג (classification == null)
  //  - אם היוזם סיווג (ואז הוא גם manager) → מותר
  // -----------------------------------------------------------
  Future<bool> _isResponder() async {
    final uid = widget.profile.uid;
    final d = await FirebaseFirestore.instance
        .collection(_eventsCollection)
        .doc(widget.eventId)
        .collection('responders')
        .doc(uid)
        .get();
    return d.exists;
  }

  static List<String> _parseBikePhotoUrls(dynamic raw) {
    if (raw is List) {
      return raw
          .map((e) => e.toString())
          .where((u) => u.isNotEmpty)
          .toList();
    }
    return [];
  }

  Future<bool> _canWriteChat({
    required bool isInitiator,
    required String? classification,
    required bool isManager,
  }) async {
    if (widget.isClosed) return false;
    if (isManager) return true;
    if (isInitiator && classification != null) return true;

    // מגיבים — צריך לבדוק במסד
    if (await _isResponder()) return true;

    return false;
  }

  // -----------------------------------------------------------
  // Room 10.14 — Send message
  // -----------------------------------------------------------
  Future<void> _sendChatMessage({
    required bool isInitiator,
    required String? classification,
    required bool isManager,
  }) async {
    if (_sendingMsg) return;

    final raw = _chatCtrl.text.trim();
    if (raw.isEmpty) return;

    final ok = await _canWriteChat(
      isInitiator: isInitiator,
      classification: classification,
      isManager: isManager,
    );
    if (!ok) return;

    setState(() => _sendingMsg = true);

    try {
      final mePhone = widget.profile.phone;
      await FirebaseFirestore.instance
          .collection(_eventsCollection)
          .doc(widget.eventId)
          .collection('messages')
          .add({
        'text': raw,
        'senderUid': widget.profile.uid,
        'senderPhone': mePhone,
        'senderName': widget.profile.fullName,
        'createdAt': Timestamp.now(),
      });

      _chatCtrl.clear();
    } finally {
      if (!mounted) return;
      setState(() => _sendingMsg = false);
    }
  }

  Future<void> _sendChatImage({
    required bool isInitiator,
    required String? classification,
    required bool isManager,
  }) async {
    if (_sendingMsg) return;

    final ok = await _canWriteChat(
      isInitiator: isInitiator,
      classification: classification,
      isManager: isManager,
    );
    if (!ok) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('צלם תמונה'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('בחר מהגלריה'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final img = await _imagePicker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1200,
    );
    if (img == null || !mounted) return;

    setState(() => _sendingMsg = true);
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('sos_chat/${widget.eventId}/${DateTime.now().millisecondsSinceEpoch}_${widget.profile.uid}.jpg');
      await ref.putFile(File(img.path));
      final url = await ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection(_eventsCollection)
          .doc(widget.eventId)
          .collection('messages')
          .add({
        'text': '',
        'imageUrl': url,
        'senderUid': widget.profile.uid,
        'senderPhone': widget.profile.phone,
        'senderName': widget.profile.fullName,
        'createdAt': Timestamp.now(),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בשליחת תמונה: $e')),
        );
      }
    } finally {
      if (!mounted) return;
      setState(() => _sendingMsg = false);
    }
  }

  // ===========================================================
  // === CRITICAL END — CHAT =================================
  // ===========================================================

  // ===========================================================
  // === REINFORCEMENT (תגבורת) =================================
  // ===========================================================
  static const List<({String service, String phone, IconData icon, String? displayPhone})> _reinforcementServices = [
    (service: 'משטרה', phone: '100', icon: Icons.local_police, displayPhone: null),
    (service: 'מדא', phone: '101', icon: Icons.local_hospital, displayPhone: null),
    (service: 'מכבי אש', phone: '102', icon: Icons.local_fire_department, displayPhone: null),
    (service: 'מוקד עירוני', phone: '106', icon: Icons.phone, displayPhone: null),
    (service: 'פיילוט', phone: '0524719366', icon: Icons.security, displayPhone: '911'),
  ];

  void _showReinforcementSheet(BuildContext sheetContext) {
    showModalBottomSheet(
      context: sheetContext,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'תגבורת',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
                textDirection: TextDirection.rtl,
              ),
              const SizedBox(height: 16),
              ..._reinforcementServices.map((s) => ListTile(
                leading: Icon(s.icon, color: Colors.red.shade700),
                title: Text(s.service, textDirection: TextDirection.rtl),
                trailing: Text(s.displayPhone ?? s.phone, style: const TextStyle(fontWeight: FontWeight.w700)),
                onTap: () {
                  Navigator.pop(ctx);
                  _callAndRecordReinforcement(sheetContext, s.service, s.phone);
                },
              )),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _callAndRecordReinforcement(BuildContext context, String service, String phone) async {
    // עדכון Firestore קודם — כדי שהממשק יתעדכן מיד (לפני פתיחת אפליקציית החיוג)
    try {
      await FirebaseFirestore.instance
          .collection(_eventsCollection)
          .doc(widget.eventId)
          .update({
        'emergencyCalls': FieldValue.arrayUnion([
          {
            'service': service,
            'phone': phone,
            'calledBy': widget.profile.uid,
            'calledByPhone': widget.profile.phone,
            'calledAt': Timestamp.now(),
          },
        ]),
      });
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה ברישום התגבורת: $e')),
        );
      }
      return;
    }
    try {
      final uri = Uri(scheme: 'tel', path: phone);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  // -----------------------------------------------------------
  // Room 10.15 — Lifecycle
  // -----------------------------------------------------------
  @override
  void initState() {
    super.initState();
    if (!widget.isClosed) {
      _startClassificationTimer();
      WakelockPlus.enable();
    }
  }

  @override
  void dispose() {
    if (!widget.isClosed) WakelockPlus.disable();
    _classificationTimer?.cancel();
    _locationTimer?.cancel();
    _closeTimer?.cancel();
    _chatCtrl.dispose();
    super.dispose();
  }

  // ===========================================================
  // DEPARTMENT 11 — UI
  // ===========================================================
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _eventStream(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snap.data!.exists) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('האירוע לא קיים'),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () async {
                      if (!widget.isClosed) {
                        await FirebaseFirestore.instance
                            .collection('riders')
                            .doc(widget.profile.uid)
                            .update({
                          'activeEventId': FieldValue.delete(),
                          'activeEventRole': FieldValue.delete(),
                        });
                      }
                      _safePopTrue();
                    },
                    child: const Text('חזור'),
                  ),
                ],
              ),
            ),
          );
        }

        _handleAutoExit(snap.data!);

        final data = snap.data!.data()!;
        final status = data['status'] as String?;
        final classification = data['classification'] as String?;
        final managerUid = data['managerUid'] as String?;
        final managerPhone = data['managerPhone'] as String?;
        final managerType = data['managerType'] as String?;
        final initiatorUid = data['initiatorUid'] as String?;
        final initiatorPhone = data['initiatorPhone'] as String?;

        final isManager = managerUid == widget.profile.uid ||
            (managerPhone == widget.profile.phone && managerUid == null);
        final isInitiator = initiatorUid == widget.profile.uid ||
            (initiatorPhone == widget.profile.phone && initiatorUid == null);

        // ניסיון תביעה למנהל במקרה חריג (רק responders)
        // (רץ פעם-פעמיים עד שיתפס — לא קריטי אם ייקרא שוב)
        _tryClaimManagerIfNeeded(
          managerPhone: managerPhone,
          managerType: managerType,
        );

        // עדכון מיקום חי באירוע — רק יוזם, כל 17 שניות
        _startLiveLocationIfInitiator(isInitiator, status);

        final initiatorCanSeeContent = isInitiator && classification != null;
        final showFullContent = !isInitiator || initiatorCanSeeContent;
        final initiatorAddress = data['initiatorAddress'] as String? ?? '';
        final bikeUrls = _parseBikePhotoUrls(data['initiatorBikePhotoUrls']);
        final showBikePhotos = bikeUrls.isNotEmpty && (
          !isInitiator ||
          (isInitiator && classification != null)
        );

        return Scaffold(
          backgroundColor: Colors.red.shade800,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: Colors.red.shade900,
            title: const Text('חדר מצוקה'),
            centerTitle: true,
            actions: [
              if (showFullContent && status == 'open' && !widget.isClosed)
                IconButton(
                  icon: const Icon(Icons.emergency),
                  tooltip: 'תגבורת',
                  onPressed: () => _showReinforcementSheet(context),
                ),
            ],
          ),
          body: SafeArea(
            child: initiatorCanSeeContent == false && isInitiator
                ? _InitiatorBlindContent(
                    onClassify: _setClassification,
                    classification: classification,
                  )
                : Stack(
              children: [
                Column(
              children: [
                const SizedBox(height: 12),
                const Icon(Icons.warning, size: 64, color: Colors.white),
                const SizedBox(height: 8),
                Text(
                  classification != null
                      ? 'אירוע $classification פעיל'
                      : 'אירוע מצוקה פעיל',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                  textDirection: TextDirection.rtl,
                ),
                if (initiatorAddress.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      initiatorAddress,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                if (showBikePhotos) ...[
                  const SizedBox(height: 12),
                  _TheftBikePhotosPanel(
                    bikePhotoUrls: bikeUrls,
                    classification: classification,
                  ),
                ],
                const SizedBox(height: 8),

                // -------------------------------------------------
                // Room 11.4 — Chat panel
                // -------------------------------------------------
                Expanded(
                  child: Container(
                    width: double.infinity,
                    margin: EdgeInsets.fromLTRB(
                        12, 6, 12, MediaQuery.of(context).viewInsets.bottom > 0 ? 4 : 12),
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        const Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'צ׳אט תיאום',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: _chatStream(),
                            builder: (context, s) {
                              if (!s.hasData) {
                                return const Center(
                                    child: CircularProgressIndicator());
                              }

                              final docs = s.data!.docs;
                              if (docs.isEmpty) {
                                return const Center(
                                  child: Text('אין הודעות עדיין'),
                                );
                              }

                              return ListView.builder(
                                reverse: true,
                                itemCount: docs.length,
                                itemBuilder: (_, i) {
                                  final m = docs[i].data();
                                  final txt = (m['text'] ?? '').toString();
                                  final imageUrl = (m['imageUrl'] ?? '').toString();
                                  final sender =
                                      (m['senderName'] ?? '').toString();
                                  final senderPhone =
                                      (m['senderPhone'] ?? '').toString();
                                  final mine =
                                      senderPhone == widget.profile.phone;

                                  return Align(
                                    alignment: mine
                                        ? Alignment.centerLeft
                                        : Alignment.centerRight,
                                    child: Container(
                                      margin:
                                          const EdgeInsets.symmetric(vertical: 4),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: mine
                                            ? Colors.green.shade50
                                            : Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            sender,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          if (imageUrl.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            GestureDetector(
                                              onTap: () => Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => _ZoomableImageView(url: imageUrl),
                                                ),
                                              ),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(8),
                                                child: Image.network(
                                                  imageUrl,
                                                  width: 200,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) =>
                                                      const Icon(Icons.broken_image),
                                                ),
                                              ),
                                            ),
                                          ],
                                          if (txt.isNotEmpty) ...[
                                            if (imageUrl.isNotEmpty) const SizedBox(height: 4),
                                            Text(
                                              txt,
                                              style: const TextStyle(fontSize: 13),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        FutureBuilder<bool>(
                          future: _canWriteChat(
                            isInitiator: isInitiator,
                            classification: classification,
                            isManager: isManager,
                          ),
                          builder: (context, can) {
                            final canWrite = can.data ?? false;
                            final hintText = canWrite
                                ? 'כתוב הודעה...'
                                : (isInitiator && classification == null)
                                    ? 'סווג את האירוע למעלה כדי לכתוב בצ׳אט'
                                    : 'צ׳אט חסום עבורך';

                            return Row(
                              children: [
                                IconButton(
                                  onPressed: (!canWrite || _sendingMsg)
                                      ? null
                                      : () => _sendChatImage(
                                            isInitiator: isInitiator,
                                            classification: classification,
                                            isManager: isManager,
                                          ),
                                  icon: const Icon(Icons.camera_alt),
                                  tooltip: 'צלם או בחר תמונה',
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: _chatCtrl,
                                    enabled: canWrite && !_sendingMsg,
                                    decoration: InputDecoration(
                                      hintText: hintText,
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    textInputAction: TextInputAction.send,
                                    onSubmitted: (_) => _sendChatMessage(
                                      isInitiator: isInitiator,
                                      classification: classification,
                                      isManager: isManager,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: (!canWrite || _sendingMsg)
                                      ? null
                                      : () => _sendChatMessage(
                                            isInitiator: isInitiator,
                                            classification: classification,
                                            isManager: isManager,
                                          ),
                                  child: _sendingMsg
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('שלח'),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                // space for sheet peek (מתבטל כשהמקלדת פתוחה כדי למנוע overflow)
                if (showFullContent && status == 'open')
                  SizedBox(
                      height: MediaQuery.of(context).viewInsets.bottom > 0
                          ? 0
                          : 55),
              ],
            ),
                if (showFullContent && status == 'open')
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: _SosInfoSheet(
                      eventId: widget.eventId,
                      isManager: isManager,
                      closingHolding: _closingHolding,
                      onHoldStart: _onHoldStart,
                      onHoldEnd: _onHoldEnd,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  }

// =============================================================
// DEPARTMENT 11.6 — Initiator Blind Content (לא סווג)
// -------------------------------------------------------------
class _InitiatorBlindContent extends StatelessWidget {
  final void Function(String) onClassify;
  final String? classification;

  const _InitiatorBlindContent({
    required this.onClassify,
    this.classification,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.warning, size: 64, color: Colors.white),
            const SizedBox(height: 16),
            const Text(
              'נא לסווג את האירוע',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () => onClassify('תאונה'),
                  child: const Text('תאונה'),
                ),
                ElevatedButton(
                  onPressed: () => onClassify('תקיפה'),
                  child: const Text('תקיפה'),
                ),
                ElevatedButton(
                  onPressed: () => onClassify('גניבה'),
                  child: const Text('גניבה'),
                ),
                ElevatedButton(
                  onPressed: () => onClassify('חילוץ לוגיסטי'),
                  child: const Text('חילוץ לוגיסטי'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// DEPARTMENT 11.7 — Draggable Info Sheet (מגיבים + סגירה)
// -------------------------------------------------------------
class _SosInfoSheet extends StatefulWidget {
  final String eventId;
  final bool isManager;
  final bool closingHolding;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  const _SosInfoSheet({
    required this.eventId,
    required this.isManager,
    required this.closingHolding,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  @override
  State<_SosInfoSheet> createState() => _SosInfoSheetState();
}

class _SosInfoSheetState extends State<_SosInfoSheet> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eventsCol = 'sos_events_open';
    return DraggableScrollableSheet(
      initialChildSize: 0.08,
      minChildSize: 0.06,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return _SheetBody(
          eventId: widget.eventId,
          eventsCol: eventsCol,
          scrollController: scrollController,
          isManager: widget.isManager,
          closingHolding: widget.closingHolding,
          onHoldStart: widget.onHoldStart,
          onHoldEnd: widget.onHoldEnd,
          loadResponderDistances: _loadResponderDistances,
        );
      },
    );
  }

  Future<Map<String, double>> _loadResponderDistances(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> responders,
    double? initLat,
    double? initLng,
  ) async {
    final map = <String, double>{};
    if (initLat == null || initLng == null) return map;
    for (final r in responders) {
      final uid = (r.data()['uid'] ?? '').toString();
      if (uid.isEmpty) continue;
      final pre = await FirebaseFirestore.instance
          .collection('rider_presence')
          .doc(uid)
          .get();
      final pdata = pre.data();
      final rlat = (pdata?['lat'] as num?)?.toDouble();
      final rlng = (pdata?['lng'] as num?)?.toDouble();
      if (rlat != null && rlng != null) {
        map[uid] = Geolocator.distanceBetween(
          initLat, initLng, rlat, rlng,
        );
      }
    }
    return map;
  }
}

// -------------------------------------------------------------
// Room 11.7.1 — Sheet Body (extracted for clarity)
// -------------------------------------------------------------
// מיפוי שם כוח -> אייקון (לצג "כוחות שהוקפצו")
const Map<String, IconData> _serviceIcons = {
  'משטרה': Icons.local_police,
  'מדא': Icons.local_hospital,
  'מכבי אש': Icons.local_fire_department,
  'מוקד עירוני': Icons.phone,
  'פיילוט': Icons.security,
};

class _SheetBody extends StatelessWidget {
  final String eventId;
  final String eventsCol;
  final ScrollController scrollController;
  final bool isManager;
  final bool closingHolding;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final Future<Map<String, double>> Function(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> responders,
    double? initLat,
    double? initLng,
  ) loadResponderDistances;

  const _SheetBody({
    required this.eventId,
    required this.eventsCol,
    required this.scrollController,
    required this.isManager,
    required this.closingHolding,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.loadResponderDistances,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 16,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection(eventsCol)
              .doc(eventId)
              .snapshots(),
          builder: (context, eventSnap) {
            if (!eventSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final eventData = eventSnap.data!.data();
            final initiatorLat =
                (eventData?['initiatorLat'] as num?)?.toDouble();
            final initiatorLng =
                (eventData?['initiatorLng'] as num?)?.toDouble();
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection(eventsCol)
                  .doc(eventId)
                  .collection('responders')
                  .snapshots(),
              builder: (context, respSnap) {
                if (!respSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final responders = respSnap.data!.docs;
                return FutureBuilder<Map<String, double>>(
                  future: loadResponderDistances(
                    responders,
                    initiatorLat,
                    initiatorLng,
                  ),
                  builder: (context, distSnap) {
                    final distMap = distSnap.data ?? <String, double>{};
                    return CustomScrollView(
                      controller: scrollController,
                      slivers: [
                        SliverToBoxAdapter(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 8),
                              Center(
                                child: Container(
                                  width: 40,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade400,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    'פרטי האירוע',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18,
                                    ),
                                    textDirection: TextDirection.rtl,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    'ריידרים בדרך',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                      color: Colors.black54,
                                    ),
                                    textDirection: TextDirection.rtl,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                            ],
                          ),
                        ),
                        if (responders.isEmpty)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                  child: Text('אין מגיבים עדיין')),
                            ),
                          )
                        else
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (_, i) {
                                final r = responders[i].data();
                                final name = (r['name'] ?? '').toString();
                                final uid = (r['uid'] ?? '').toString();
                                final dist = distMap[uid];
                                final distStr = dist != null
                                    ? '${(dist / 1000).toStringAsFixed(1)} ק״מ'
                                    : '—';
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.red.shade200,
                                    child: Text(
                                      name.isNotEmpty
                                          ? name.substring(0, 1)
                                          : '?',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    name.isNotEmpty ? name : 'ללא שם',
                                    textDirection: TextDirection.rtl,
                                  ),
                                  trailing: Text(
                                    distStr,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                );
                              },
                              childCount: responders.length,
                            ),
                          ),
                        SliverToBoxAdapter(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 12),
                              Divider(height: 1, thickness: 1, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    'כוחות שהוקפצו',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                      color: Colors.black54,
                                    ),
                                    textDirection: TextDirection.rtl,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Builder(
                                  builder: (_) {
                                    final calls = eventData?['emergencyCalls'] as List<dynamic>? ?? [];
                                    final services = calls
                                        .map((c) => c is Map ? (c['service'] ?? '').toString() : '')
                                        .where((s) => s.isNotEmpty)
                                        .toSet()
                                        .toList();
                                    if (services.isEmpty) {
                                      return const Text(
                                        '—',
                                        style: TextStyle(fontSize: 14),
                                        textDirection: TextDirection.rtl,
                                      );
                                    }
                                    return Wrap(
                                      spacing: 12,
                                      runSpacing: 8,
                                      textDirection: TextDirection.rtl,
                                      children: services.map((name) {
                                        final icon = _serviceIcons[name] ?? Icons.phone;
                                        return Padding(
                                          padding: const EdgeInsets.only(left: 4),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            children: [
                                              Icon(icon, size: 22, color: Colors.red.shade700),
                                              const SizedBox(width: 6),
                                              Text(name, style: const TextStyle(fontSize: 14), textDirection: TextDirection.rtl),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isManager)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(
                                  left: 16, right: 16, bottom: 24, top: 8),
                              child: GestureDetector(
                                onLongPressStart: (_) => onHoldStart(),
                                onLongPressEnd: (_) => onHoldEnd(),
                                onLongPressCancel: onHoldEnd,
                                child: AnimatedScale(
                                  scale: closingHolding ? 1.06 : 1.0,
                                  duration: const Duration(milliseconds: 120),
                                  child: Container(
                                    width: 140,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Center(
                                      child: Text(
                                        'סגור אירוע',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// =============================================================
// DEPARTMENT 12 — Theft Bike Photos Panel (Zoomable)
// =============================================================

// -------------------------------------------------------------
// Room 12.1 — Panel Widget
// -------------------------------------------------------------
class _TheftBikePhotosPanel extends StatelessWidget {
  final List<String> bikePhotoUrls;
  final String? classification;

  const _TheftBikePhotosPanel({
    required this.bikePhotoUrls,
    this.classification,
  });

  String get _title {
    if (classification == 'גניבה') return 'גניבה — תמונות הכלי (לחץ להגדלה)';
    if (classification == 'מצוקה רציני משולב') return 'מצוקה משולבת — תמונות הכלי (לחץ להגדלה)';
    return 'תמונות הכלי (לחץ להגדלה)';
  }

  @override
  Widget build(BuildContext context) {
    if (bikePhotoUrls.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          'תמונות הכלי: לא נמצאו',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              _title,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: bikePhotoUrls.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final url = bikePhotoUrls[i];
                return GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _ZoomableImageView(url: url),
                      ),
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 84,
                      height: 84,
                      color: Colors.black12,
                      child: Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(Icons.broken_image,
                              color: Colors.white70),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// Room 12.2 — Fullscreen + Zoom
// -------------------------------------------------------------
class _ZoomableImageView extends StatelessWidget {
  final String url;

  const _ZoomableImageView({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('תמונה'),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1.0,
          maxScale: 5.0,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.broken_image, color: Colors.white70, size: 64),
            ),
          ),
        ),
      ),
    );
  }
}
