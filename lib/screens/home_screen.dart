// =============================================================
// PROJECT: home_screen.dart
// DEPARTMENT 1 — Home Screen (UID-based)
// =============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart' as intl;
import 'package:rider_sos/models/rider_profile.dart';
import 'package:rider_sos/screens/sos_screen.dart';
import 'package:rider_sos/widgets/rider_drawer.dart';

// =============================================================
// ROOM 0 — Slide-to-confirm slider (למניעת לחיצה בטעות)
// =============================================================

class _SlideToConfirmSlider extends StatefulWidget {
  final String label;
  final Color trackColor;
  final VoidCallback onConfirm;

  const _SlideToConfirmSlider({
    required this.label,
    required this.trackColor,
    required this.onConfirm,
  });

  @override
  State<_SlideToConfirmSlider> createState() => _SlideToConfirmSliderState();
}

class _SlideToConfirmSliderState extends State<_SlideToConfirmSlider> {
  double _dragOffset = 0;
  static const double _confirmThreshold = 0.82;
  static const double _thumbSize = 48.0;
  static const double _trackHeight = 56.0;

  void _onHorizontalDragUpdate(DragUpdateDetails d, double trackWidth) {
    final delta = Directionality.of(context) == TextDirection.rtl ? -d.delta.dx : d.delta.dx;
    setState(() {
      _dragOffset = (_dragOffset + delta / trackWidth).clamp(0.0, 1.0);
      if (_dragOffset >= _confirmThreshold) {
        _dragOffset = 0;
        widget.onConfirm();
      }
    });
  }

  void _onHorizontalDragEnd(DragEndDetails d) {
    setState(() => _dragOffset = 0);
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final thumbPos = (_dragOffset * (w - _thumbSize)).clamp(0.0, w - _thumbSize);
        return Container(
          height: _trackHeight,
          decoration: BoxDecoration(
            color: widget.trackColor,
            borderRadius: BorderRadius.circular(_trackHeight / 2),
          ),
          child: Stack(
            textDirection: isRtl ? TextDirection.ltr : TextDirection.rtl,
            children: [
              Center(
                child: Text(
                  widget.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  textDirection: TextDirection.rtl,
                ),
              ),
              Positioned(
                top: 4,
                bottom: 4,
                left: isRtl ? null : thumbPos,
                right: isRtl ? thumbPos : null,
                child: GestureDetector(
                  onHorizontalDragUpdate: (d) => _onHorizontalDragUpdate(d, w),
                  onHorizontalDragEnd: _onHorizontalDragEnd,
                  child: Container(
                    width: _thumbSize,
                    height: _thumbSize,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.arrow_forward_ios,
                      size: 20,
                      color: widget.trackColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================
// ROOM 1.1 — HomeScreen (Location Gate + Main)
// =============================================================

class HomeScreen extends StatefulWidget {
  final RiderProfile profile;

  const HomeScreen({
    super.key,
    required this.profile,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {

  // ================= LOCATION GATE =================
  bool _checkingLocation = true;
  bool _locationOk = false;
  String? _locationError;
  String _cityText = '...';
  String _addressText = '';
  /// מפתח אזור אחיד (קואורדינטות מעוגלות) — לספירת רוכבים בלי תלות בשפת המכשיר
  String _cityKey = '';

  @override
  void initState() {
    super.initState();
    _checkLocationGate();
  }

  Future<void> _checkLocationGate() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _checkingLocation = false;
          _locationError = 'שירותי מיקום כבויים';
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          _checkingLocation = false;
          _locationError = 'חובה לאשר מיקום';
        });
        return;
      }

      final pos = await Geolocator.getCurrentPosition();
      final placemarks =
          await placemarkFromCoordinates(pos.latitude, pos.longitude);

      final p = placemarks.isNotEmpty ? placemarks.first : null;
      final city = p?.locality ?? p?.subAdministrativeArea;
      final address = _formatAddress(p);
      // מפתח אזור אחיד (2 ספרות אחרי הנקודה ≈ אותו אזור) — מונע 0 בגלל "Petah Tikva" vs "פתח תקווה"
      final lat = (pos.latitude * 100).round() / 100;
      final lng = (pos.longitude * 100).round() / 100;
      final cityKey = '$lat,$lng';

      setState(() {
        _checkingLocation = false;
        _locationOk = true;
        _cityText = city ?? 'לא זוהה';
        _addressText = address;
        _cityKey = cityKey;
      });

    } catch (e) {
      setState(() {
        _checkingLocation = false;
        _locationError = 'שגיאת מיקום: $e';
      });
    }
  }

  static String _formatAddress(Placemark? p) {
    if (p == null) return '';
    final parts = [
      p.thoroughfare,
      p.subThoroughfare,
      if ((p.thoroughfare ?? p.subThoroughfare) == null) p.street,
    ].whereType<String>().where((s) => s.isNotEmpty);
    return parts.join(' ').trim();
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingLocation) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_locationOk) {
      return Scaffold(
        body: Center(child: Text(_locationError ?? 'שגיאת מיקום')),
      );
    }

    return _HomeMainScreen(
      profile: widget.profile,
      cityText: _cityText,
      addressText: _addressText,
      cityKey: _cityKey,
    );
  }
}

// =============================================================
// DEPARTMENT 2 — Main Screen
// =============================================================

class _HomeMainScreen extends StatefulWidget {
  final RiderProfile profile;
  final String cityText;
  final String addressText;
  final String cityKey;

  const _HomeMainScreen({
    required this.profile,
    required this.cityText,
    required this.addressText,
    required this.cityKey,
  });

  @override
  State<_HomeMainScreen> createState() => _HomeMainScreenState();
}

class _HomeMainScreenState extends State<_HomeMainScreen> {

  bool _onDuty = false;
  bool _dutySaving = false;

  bool _sosHolding = false;
  bool _sosTriggered = false;
  Timer? _sosTimer;
  int _holdToken = 0;

  String? _activeEventId;
  String? _activeEventRole;

  late String _cityText;
  late String _addressText;
  late String _cityKey;
  double? _myLat;
  double? _myLng;
  Timer? _locationRefreshTimer;
  /// מתחלף בכל רענון מיקום: true = מציג עיר, false = מציג כתובת
  bool _displayCity = true;

  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  static const double _sheetSizeGreenVisible = 0.46;

  void _adjustSheetToSlider() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_sheetController.isAttached) return;
      _sheetController.jumpTo(_sheetSizeGreenVisible);
    });
  }

  @override
  void initState() {
    super.initState();
    _cityText = widget.cityText;
    _addressText = widget.addressText;
    _cityKey = widget.cityKey;
    _checkForActiveEvent();
    _loadOnDutyState();
    _startLocationRefresh();
    _startActiveEventListener();
  }

  void _startActiveEventListener() {
    FirebaseFirestore.instance
        .collection('riders')
        .doc(widget.profile.uid)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final eventId = snap.data()?['activeEventId'] as String?;
      final role = snap.data()?['activeEventRole'] as String?;
      setState(() {
        _activeEventId = eventId;
        _activeEventRole = role;
      });
    });
  }

  Future<void> _loadOnDutyState() async {
    final doc = await FirebaseFirestore.instance
        .collection('rider_presence')
        .doc(widget.profile.uid)
        .get();
    if (doc.exists && doc.data()?['onDuty'] == true) {
      if (mounted) {
        setState(() => _onDuty = true);
        _adjustSheetToSlider();
      }
    }
  }

  @override
  void dispose() {
    _holdToken++;
    _sosTimer?.cancel();
    _locationRefreshTimer?.cancel();
    _sheetController.dispose();
    super.dispose();
  }

  // =============================================================
  // ROOM 2.1b — Refresh location every 15–20s (display + rider_presence)
  // =============================================================

  static const Duration _locationRefreshInterval = Duration(seconds: 17);

  void _startLocationRefresh() {
    _locationRefreshTimer?.cancel();
    _locationRefreshTimer = Timer.periodic(_locationRefreshInterval, (_) => _refreshLocation());
  }

  Future<void> _refreshLocation() async {
    if (!mounted) return;
    try {
      final pos = await Geolocator.getCurrentPosition();
      final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      final p = placemarks.isNotEmpty ? placemarks.first : null;
      final city = p?.locality ?? p?.subAdministrativeArea;
      final address = _HomeScreenState._formatAddress(p);
      final lat = (pos.latitude * 100).round() / 100;
      final lng = (pos.longitude * 100).round() / 100;
      final cityKey = '$lat,$lng';
      if (!mounted) return;
      setState(() {
        _cityText = city ?? 'לא זוהה';
        _addressText = address;
        _cityKey = cityKey;
        _myLat = pos.latitude;
        _myLng = pos.longitude;
        _displayCity = !_displayCity;
      });
      if (_onDuty) await _writeDuty(true, lat: pos.latitude, lng: pos.longitude);
    } catch (_) {}
  }

  // =============================================================
  // ROOM 2.1 — Resume Active Event
  // =============================================================

  Future<void> _checkForActiveEvent() async {
    final uid = widget.profile.uid;

    final riderDoc = await FirebaseFirestore.instance
        .collection('riders')
        .doc(uid)
        .get();

    if (!riderDoc.exists) return;

    final activeEventId = riderDoc.data()?['activeEventId'];
    final activeEventRole = riderDoc.data()?['activeEventRole'] as String?;
    if (activeEventId == null) {
      setState(() {
        _activeEventId = null;
        _activeEventRole = null;
      });
      return;
    }

    final eventDoc = await FirebaseFirestore.instance
        .collection('sos_events_open')
        .doc(activeEventId)
        .get();

    if (!eventDoc.exists) {
      await FirebaseFirestore.instance
          .collection('riders')
          .doc(uid)
          .update({
        'activeEventId': null,
        'activeEventRole': null,
      });
      if (!mounted) return;
      setState(() {
        _activeEventId = null;
        _activeEventRole = null;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _activeEventId = activeEventId;
      _activeEventRole = activeEventRole;
    });

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SosScreen(
          eventId: activeEventId,
          profile: widget.profile,
        ),
      ),
    );

    if (!mounted) return;
    final updatedRiderDoc = await FirebaseFirestore.instance
        .collection('riders')
        .doc(uid)
        .get();
    final updatedEventId = updatedRiderDoc.data()?['activeEventId'] as String?;
    final updatedRole = updatedRiderDoc.data()?['activeEventRole'] as String?;
    setState(() {
      _sosTriggered = false;
      _sosHolding = false;
      _activeEventId = updatedEventId;
      _activeEventRole = updatedRole;
    });
  }

  // -----------------------------------------------------------
  // ROOM 2.1c — הגיב לאירוע (מהחלונית במסך הבית)
  // -----------------------------------------------------------
  Future<void> _onRespondToEvent(String eventId) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final uid = widget.profile.uid;
    final eventRef =
        FirebaseFirestore.instance.collection('sos_events_open').doc(eventId);
    final respondersRef = eventRef.collection('responders').doc(uid);

    try {
      final responderSnap = await respondersRef.get();
      if (responderSnap.exists) {
        navigator.push(
          MaterialPageRoute(
            builder: (_) => SosScreen(eventId: eventId, profile: widget.profile),
          ),
        );
        if (!mounted) return;
        final updatedRiderDoc = await FirebaseFirestore.instance
            .collection('riders')
            .doc(uid)
            .get();
        final updatedEventId = updatedRiderDoc.data()?['activeEventId'] as String?;
        final updatedRole = updatedRiderDoc.data()?['activeEventRole'] as String?;
        setState(() {
          _activeEventId = updatedEventId;
          _activeEventRole = updatedRole;
        });
        return;
      }

      await respondersRef.set({
        'uid': uid,
        'phone': widget.profile.phone,
        'name': widget.profile.fullName,
        'joinedAt': FieldValue.serverTimestamp(),
      });
      await eventRef.update({
        'responderCount': FieldValue.increment(1),
        'participantIds': FieldValue.arrayUnion([uid]),
      });
      await FirebaseFirestore.instance.collection('riders').doc(uid).update({
        'activeEventId': eventId,
        'activeEventRole': 'responder',
      });

      if (!mounted) return;
      setState(() {
        _activeEventId = eventId;
        _activeEventRole = 'responder';
      });

      navigator.push(
        MaterialPageRoute(
          builder: (_) => SosScreen(eventId: eventId, profile: widget.profile),
        ),
      );
      if (!mounted) return;
      final updatedRiderDoc = await FirebaseFirestore.instance
          .collection('riders')
          .doc(uid)
          .get();
      final updatedEventId = updatedRiderDoc.data()?['activeEventId'] as String?;
      final updatedRole = updatedRiderDoc.data()?['activeEventRole'] as String?;
      setState(() {
        _activeEventId = updatedEventId;
        _activeEventRole = updatedRole;
      });
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('שגיאה: $e', textDirection: TextDirection.rtl),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _onEnterMyEvent(String eventId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SosScreen(
          eventId: eventId,
          profile: widget.profile,
        ),
      ),
    );
    if (!mounted) return;
    final updated = await FirebaseFirestore.instance
        .collection('riders')
        .doc(widget.profile.uid)
        .get();
    final activeId = updated.data()?['activeEventId'] as String?;
    final activeRole = updated.data()?['activeEventRole'] as String?;
    setState(() {
      _activeEventId = activeId;
      _activeEventRole = activeRole;
    });
  }

  // =============================================================
  // ROOM 2.2 — Duty Write
  // =============================================================

  Future<void> _writeDuty(bool onDuty, {double? lat, double? lng}) async {
    final uid = widget.profile.uid;

    final data = <String, dynamic>{
      'onDuty': onDuty,
      'city': _cityText,
      'address': _addressText,
      'cityKey': _cityKey,
      'lastSeenAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (lat != null && lng != null) {
      data['lat'] = lat;
      data['lng'] = lng;
    }
    await FirebaseFirestore.instance
        .collection('rider_presence')
        .doc(uid)
        .set(data, SetOptions(merge: true));
  }

  Future<void> _enterDuty() async {
    if (_dutySaving) return;
    setState(() => _dutySaving = true);
    await _writeDuty(true);
    if (!mounted) return;
    setState(() {
      _onDuty = true;
      _dutySaving = false;
    });
    _adjustSheetToSlider();
  }

  Future<void> _exitDuty() async {
    if (_dutySaving) return;
    setState(() => _dutySaving = true);
    await _writeDuty(false);
    if (!mounted) return;
    setState(() {
      _onDuty = false;
      _dutySaving = false;
    });
    _adjustSheetToSlider();
  }

  // =============================================================
  // ROOM 2.3 — SOS Create / Resume
  // =============================================================

  Future<void> _onSosPressed() async {
    final uid = widget.profile.uid;

    final existing = await FirebaseFirestore.instance
        .collection('sos_events_open')
        .where('initiatorUid', isEqualTo: uid)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      final eventId = existing.docs.first.id;

      await FirebaseFirestore.instance
          .collection('riders')
          .doc(uid)
          .set({
        'activeEventId': eventId,
        'activeEventRole': 'initiator',
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _activeEventId = eventId;
        _activeEventRole = 'initiator';
      });

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SosScreen(
            eventId: eventId,
            profile: widget.profile,
          ),
        ),
      );
      if (!mounted) return;
      final updatedRiderDoc = await FirebaseFirestore.instance
          .collection('riders')
          .doc(uid)
          .get();
      final updatedEventId = updatedRiderDoc.data()?['activeEventId'] as String?;
      final updatedRole = updatedRiderDoc.data()?['activeEventRole'] as String?;
      setState(() {
        _sosTriggered = false;
        _sosHolding = false;
        _activeEventId = updatedEventId;
        _activeEventRole = updatedRole;
      });
      return;
    }

    // אם יש activeEventRole == 'responder', מוסרים אותו מהאירוע הישן
    if (_activeEventRole == 'responder' && _activeEventId != null) {
      try {
        final oldEventRef = FirebaseFirestore.instance
            .collection('sos_events_open')
            .doc(_activeEventId!);
        final oldRespondersRef = oldEventRef.collection('responders').doc(uid);
        final responderSnap = await oldRespondersRef.get();
        if (responderSnap.exists) {
          await oldRespondersRef.delete();
          await oldEventRef.update({
            'responderCount': FieldValue.increment(-1),
            'participantIds': FieldValue.arrayRemove([uid]),
          });
        }
      } catch (e) {
        // אם יש שגיאה בהסרה, ממשיכים לפתוח אירוע חדש
      }
    }

    final eventRef =
        FirebaseFirestore.instance.collection('sos_events_open').doc();

    await eventRef.set({
      'status': 'open',
      'city': _cityText,
      'address': _addressText,
      'cityKey': _cityKey,
      'initiatorUid': uid,
      'initiatorPhone': widget.profile.phone,
      'initiatorName': widget.profile.fullName,
      'initiatorBikePhotoUrls': widget.profile.bikePhotoUrls,
      'participantIds': [uid],
      'managerUid': null,
      'managerType': null,
      'responderCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await FirebaseFirestore.instance
        .collection('riders')
        .doc(uid)
        .set({
      'activeEventId': eventRef.id,
      'activeEventRole': 'initiator',
    }, SetOptions(merge: true));

    if (!mounted) return;
    setState(() {
      _activeEventId = eventRef.id;
      _activeEventRole = 'initiator';
    });

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SosScreen(
          eventId: eventRef.id,
          profile: widget.profile,
        ),
      ),
    );
    if (!mounted) return;
    final updatedRiderDoc = await FirebaseFirestore.instance
        .collection('riders')
        .doc(uid)
        .get();
    final updatedEventId = updatedRiderDoc.data()?['activeEventId'] as String?;
    final updatedRole = updatedRiderDoc.data()?['activeEventRole'] as String?;
    setState(() {
      _sosTriggered = false;
      _sosHolding = false;
      _activeEventId = updatedEventId;
      _activeEventRole = updatedRole;
    });
  }

  // =============================================================
  // ROOM 2.4 — SOS Hold Logic
  // =============================================================

  void _onHoldStart() {
    if (_sosTriggered) return;

    final token = ++_holdToken;

    setState(() => _sosHolding = true);

    _sosTimer?.cancel();
    _sosTimer = Timer(const Duration(seconds: 2), () async {
      if (token != _holdToken) return;

      setState(() {
        _sosHolding = false;
        _sosTriggered = true;
      });

      await _onSosPressed();
    });
  }

  void _onHoldEnd() {
    if (_sosTriggered) return;
    _holdToken++;
    _sosTimer?.cancel();
    setState(() => _sosHolding = false);
  }

  // =============================================================
  // ROOM 2.5 — UI
  // =============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        backgroundColor: Theme.of(context).colorScheme.surface,
        centerTitle: true,
        toolbarHeight: 215,
        leading: Builder(
          builder: (ctx) => Transform.translate(
            offset: const Offset(-15, -62),
            child: Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Icon(Icons.menu, size: 20, color: Colors.black87),
                ),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
                style: IconButton.styleFrom(padding: const EdgeInsets.all(4)),
              ),
            ),
          ),
        ),
        leadingWidth: 56,
        title: Transform.translate(
          offset: const Offset(0, -62),
          child: Image.asset(
            'assets/splash/riderssos.png',
            height: 150,
            fit: BoxFit.contain,
          ),
        ),
      ),
      drawer: RiderDrawer(profile: widget.profile),
      body: Container(
        color: Theme.of(context).colorScheme.surface,
        child: Stack(
        children: [
          Align(
            alignment: const Alignment(0, -0.68),
            child: GestureDetector(
              onLongPressStart: (_) => _onHoldStart(),
              onLongPressEnd: (_) => _onHoldEnd(),
              onLongPressCancel: _onHoldEnd,
              child: AnimatedScale(
                scale: _sosHolding ? 1.08 : 1.0,
                duration: const Duration(milliseconds: 120),
                child: Container(
                  width: 210,
                  height: 210,
                  decoration: BoxDecoration(
                    color: _sosTriggered
                        ? Colors.green
                        : (_sosHolding ? Colors.orange : Colors.red),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text(
                      'מצוקה',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                ),
              ),
            ),
          ),
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: _sheetSizeGreenVisible,
            minChildSize: 0.20,
            maxChildSize: 0.99,
            builder: (context, scrollController) => Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    _displayCity
                        ? _cityText
                        : (_addressText.isEmpty ? _cityText : _addressText),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textDirection: TextDirection.rtl,
                  ),
                  const SizedBox(height: 8),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('rider_presence')
                        .where('onDuty', isEqualTo: true)
                        .snapshots(),
                    builder: (context, snap) {
                      final count = snap.hasData ? snap.data!.docs.length : 0;
                      return Row(
                        children: [
                          Icon(
                            Icons.people_outline,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'רוכבים פעילים בשטח: $count',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 15,
                            ),
                            textDirection: TextDirection.rtl,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Divider(color: Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  if (!_onDuty) ...[
                    IgnorePointer(
                      ignoring: _dutySaving,
                      child: Opacity(
                        opacity: _dutySaving ? 0.6 : 1,
                        child: _SlideToConfirmSlider(
                          label: 'לעבור למצב פעיל',
                          trackColor: Theme.of(context).colorScheme.primary,
                          onConfirm: _enterDuty,
                        ),
                      ),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'מצב פעיל',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                          textDirection: TextDirection.rtl,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'אירועים פתוחים',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('sos_events_open')
                          .orderBy('createdAt', descending: true)
                          .limit(5)
                          .snapshots(),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'שגיאה בטעינה. הרץ במסוף: firebase deploy --only firestore',
                              textDirection: TextDirection.rtl,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          );
                        }
                        if (!snap.hasData || snap.data!.docs.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'אין אירועים פתוחים כרגע',
                              textDirection: TextDirection.rtl,
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          );
                        }
                        final docs = snap.data!.docs;
                        return ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 260),
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const ClampingScrollPhysics(),
                            itemCount: docs.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final doc = docs[index];
                              final data = doc.data();
                              final eventId = doc.id;
                              final classification = data['classification']
                                      as String? ??
                                  'ללא סיווג';
                              final createdAt =
                                  data['createdAt'] as Timestamp?;
                              final initiatorLat =
                                  (data['initiatorLat'] as num?)?.toDouble();
                              final initiatorLng =
                                  (data['initiatorLng'] as num?)?.toDouble();
                              final responderCount =
                                  (data['responderCount'] as int?) ?? 0;

                              final timeStr = createdAt != null
                                  ? intl.DateFormat('HH:mm')
                                      .format(createdAt.toDate())
                                  : '—';
                              int distM = -1;
                              if (_myLat != null &&
                                  _myLng != null &&
                                  initiatorLat != null &&
                                  initiatorLng != null) {
                                distM = Geolocator.distanceBetween(
                                  _myLat!,
                                  _myLng!,
                                  initiatorLat,
                                  initiatorLng,
                                ).round();
                              }
                              final distStr = distM < 0
                                  ? '—'
                                  : distM < 1000
                                      ? '$distM מ\''
                                      : '${(distM / 1000).toStringAsFixed(1)} ק"מ';

                              final responderColor =
                                  responderCount == 0
                                      ? Theme.of(context).colorScheme.error
                                      : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant;

                              final canRespond = _activeEventRole != 'initiator';
                              final isMyEvent = eventId == _activeEventId &&
                                  (_activeEventRole == 'initiator' ||
                                      _activeEventRole == 'responder');
                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: isMyEvent
                                      ? () => _onEnterMyEvent(eventId)
                                      : (canRespond
                                          ? () => _onRespondToEvent(eventId)
                                          : null),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withValues(alpha: 0.6),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outlineVariant
                                            .withValues(alpha: 0.5),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      mainAxisSize: MainAxisSize.min,
                                      textDirection: TextDirection.rtl,
                                      children: [
                                        Text(
                                          classification,
                                          textDirection: TextDirection.rtl,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          textDirection: TextDirection.rtl,
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              textDirection:
                                                  TextDirection.rtl,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  distStr,
                                                  textDirection:
                                                      TextDirection.rtl,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Text(
                                                  'מגיבים: $responderCount',
                                                  textDirection:
                                                      TextDirection.rtl,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: responderColor,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Text(
                                                  timeStr,
                                                  textDirection:
                                                      TextDirection.rtl,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            isMyEvent
                                            ? FilledButton(
                                                onPressed: () =>
                                                    _onEnterMyEvent(eventId),
                                                style: FilledButton.styleFrom(
                                                  backgroundColor: Colors.green,
                                                  foregroundColor: Colors.white,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                          horizontal: 14,
                                                          vertical: 10),
                                                  minimumSize:
                                                      const Size(0, 36),
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .padded,
                                                ),
                                                child: const Text(
                                                  'כניסה לאירוע',
                                                  textDirection:
                                                      TextDirection.rtl,
                                                  style: TextStyle(fontSize: 12),
                                                ),
                                              )
                                            : FilledButton.tonal(
                                                onPressed: canRespond
                                                    ? () => _onRespondToEvent(
                                                        eventId)
                                                    : null,
                                                style: FilledButton.styleFrom(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                          horizontal: 14,
                                                          vertical: 10),
                                                  minimumSize:
                                                      const Size(0, 36),
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .padded,
                                                ),
                                                child: Text(
                                                  canRespond
                                                      ? 'להגיב לאירוע'
                                                      : 'יש לך אירוע פעיל',
                                                  textDirection:
                                                      TextDirection.rtl,
                                                  style: const TextStyle(
                                                      fontSize: 12),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 140),
                    IgnorePointer(
                      ignoring: _dutySaving,
                      child: Opacity(
                        opacity: _dutySaving ? 0.6 : 1,
                        child: _SlideToConfirmSlider(
                          label: 'לעבור למצב לא פעיל',
                          trackColor: Theme.of(context).colorScheme.error,
                          onConfirm: _exitDuty,
                        ),
                      ),
                    ),
                    const SizedBox(height: 100),
                  ],
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
