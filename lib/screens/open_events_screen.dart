// =============================================================
// PROJECT: open_events_screen.dart
// אירועי מצוקה — פתוחים (עם "אני בדרך") + סגורים (היסטוריה)
// =============================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rider_sos/models/rider_profile.dart';
import 'package:rider_sos/screens/sos_screen.dart';

// =============================================================
// OpenEventsScreen — טאבים: אירועים פתוחים | אירועים סגורים
// =============================================================

class OpenEventsScreen extends StatefulWidget {
  final RiderProfile profile;

  const OpenEventsScreen({
    super.key,
    required this.profile,
  });

  @override
  State<OpenEventsScreen> createState() => _OpenEventsScreenState();
}

class _OpenEventsScreenState extends State<OpenEventsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Position? _myPosition;
  String? _locationError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadMyPosition();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadMyPosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() => _locationError = 'מיקום כבוי');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() => _locationError = 'אין הרשאת מיקום');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted) return;
      setState(() {
        _myPosition = pos;
        _locationError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _locationError = 'שגיאת מיקום');
    }
  }

  int _distanceMeters(double? lat, double? lng) {
    if (_myPosition == null || lat == null || lng == null) return -1;
    return Geolocator.distanceBetween(
      _myPosition!.latitude,
      _myPosition!.longitude,
      lat,
      lng,
    ).round();
  }

  String _formatDistance(int meters) {
    if (meters < 0) return '—';
    if (meters < 1000) return '$meters מ\'';
    final km = (meters / 1000).toStringAsFixed(1);
    return '$km ק"מ';
  }

  Future<void> _onImOnMyWay(String eventId) async {
    final uid = widget.profile.uid;
    final eventRef =
        FirebaseFirestore.instance.collection('sos_events_open').doc(eventId);
    final respondersRef = eventRef.collection('responders').doc(uid);

    final responderSnap = await respondersRef.get();
    if (responderSnap.exists) {
      await _navigateToEvent(eventId, false);
      return;
    }

    try {
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
      await _navigateToEvent(eventId, false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('שגיאה: $e', textDirection: TextDirection.rtl),
        ),
      );
    }
  }

  Future<void> _navigateToEvent(String eventId, bool isClosed) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SosScreen(
          eventId: eventId,
          profile: widget.profile,
          isClosed: isClosed,
        ),
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('אירועים שלי', textDirection: TextDirection.rtl),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'פתוחים'),
            Tab(text: 'סגורים'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _EventsList(
            profile: widget.profile,
            status: 'open',
            myPosition: _myPosition,
            locationError: _locationError,
            showRespondButton: true,
            distanceMeters: _distanceMeters,
            formatDistance: _formatDistance,
            onImOnMyWay: _onImOnMyWay,
            onTap: (id, closed) => _navigateToEvent(id, closed),
          ),
          _EventsList(
            profile: widget.profile,
            status: 'closed',
            myPosition: _myPosition,
            locationError: _locationError,
            showRespondButton: false,
            distanceMeters: _distanceMeters,
            formatDistance: _formatDistance,
            onImOnMyWay: (_) async {},
            onTap: (id, closed) => _navigateToEvent(id, closed),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// _EventsList — רשימת אירועים (פתוחים או סגורים)
// =============================================================

class _EventsList extends StatelessWidget {
  final RiderProfile profile;
  final String status;
  final Position? myPosition;
  final String? locationError;
  final bool showRespondButton;
  final int Function(double?, double?) distanceMeters;
  final String Function(int) formatDistance;
  final Future<void> Function(String) onImOnMyWay;
  final Future<void> Function(String eventId, bool isClosed) onTap;

  const _EventsList({
    required this.profile,
    required this.status,
    required this.myPosition,
    required this.locationError,
    required this.showRespondButton,
    required this.distanceMeters,
    required this.formatDistance,
    required this.onImOnMyWay,
    required this.onTap,
  });

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream() {
    final coll =
        status == 'open' ? 'sos_events_open' : 'sos_events_closed';
    return FirebaseFirestore.instance
        .collection(coll)
        .where('participantIds', arrayContains: profile.uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _stream(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'שגיאה בטעינת אירועים',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snap.error}',
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  status == 'open'
                      ? 'אין אירועים פתוחים כרגע'
                      : 'אין אירועים סגורים',
                  textDirection: TextDirection.rtl,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (locationError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    locationError!,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final data = doc.data();
                        final eventId = doc.id;
                        final classification =
                            data['classification'] as String? ?? 'ללא סיווג';
                        final initiatorName =
                            data['initiatorName'] as String? ?? data['initiatorPhone'] as String? ?? '—';
                        final initiatorLat =
                            (data['initiatorLat'] as num?)?.toDouble();
                        final initiatorLng =
                            (data['initiatorLng'] as num?)?.toDouble();
                        final responderCount =
                            (data['responderCount'] as int?) ?? 0;
                        final managerUid = data['managerUid'] as String?;
                        final managerPhone = data['managerPhone'] as String?;
                        final initiatorUid = data['initiatorUid'] as String?;
                        final createdAt = data['createdAt'] as dynamic;
                        final closedAt = data['closedAt'] as dynamic;
                        final emergencyCalls = data['emergencyCalls'] as List<dynamic>? ?? [];
                        final city = data['city'] as String? ?? '';
                        final address =
                            data['initiatorAddress'] as String? ?? data['address'] as String? ?? '';

                        final dist = distanceMeters(initiatorLat, initiatorLng);
                        final distText = formatDistance(dist);

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: InkWell(
                            onTap: () => onTap(eventId, status == 'closed'),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: status == 'closed'
                                ? _ClosedEventCardContent(
                                    classification: classification,
                                    managerUid: managerUid,
                                    managerPhone: managerPhone,
                                    initiatorUid: initiatorUid,
                                    initiatorName: initiatorName,
                                    responderCount: responderCount,
                                    createdAt: createdAt,
                                    closedAt: closedAt,
                                    emergencyCalls: emergencyCalls,
                                    onTap: () => onTap(eventId, true),
                                  )
                                : _OpenEventCardContent(
                                    classification: classification,
                                    initiatorName: initiatorName,
                                    responderCount: responderCount,
                                    address: address,
                                    city: city,
                                    distText: distText,
                                    showRespondButton: showRespondButton,
                                    onImOnMyWay: () => onImOnMyWay(eventId),
                                    onTap: () => onTap(eventId, false),
                                  ),
                          ),
                        ),
                        );
                      },
                ),
              ),
            ],
          );
        },
    );
  }
}

// כרטיס אירוע סגור — סיווג, מי ניהל, מתי נפתח/נסגר, משך, משתתפים, כוחות שהוזמנו
class _ClosedEventCardContent extends StatelessWidget {
  final String classification;
  final String? managerUid;
  final String? managerPhone;
  final String? initiatorUid;
  final String initiatorName;
  final int responderCount;
  final dynamic createdAt;
  final dynamic closedAt;
  final List<dynamic> emergencyCalls;
  final VoidCallback onTap;

  const _ClosedEventCardContent({
    required this.classification,
    required this.managerUid,
    required this.managerPhone,
    required this.initiatorUid,
    required this.initiatorName,
    required this.responderCount,
    required this.createdAt,
    required this.closedAt,
    this.emergencyCalls = const [],
    required this.onTap,
  });

  String _managerLabel() {
    if (managerUid == null && managerPhone == null) return '—';
    if (managerUid == initiatorUid) return 'יוזם';
    return managerPhone ?? '—';
  }

  String _formatTime(dynamic t) {
    if (t == null) return '—';
    if (t is DateTime) return intl.DateFormat('dd/MM HH:mm').format(t);
    if (t is Timestamp) return intl.DateFormat('dd/MM HH:mm').format(t.toDate());
    return '—';
  }

  String _formatDuration() {
    DateTime? created;
    DateTime? closed;
    if (createdAt is Timestamp) created = (createdAt as Timestamp).toDate();
    if (closedAt is Timestamp) closed = (closedAt as Timestamp).toDate();
    if (created == null || closed == null) return '—';
    final d = closed.difference(created);
    if (d.inMinutes < 60) return '${d.inMinutes} דקות';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (m == 0) return '$h שעות';
    return '$h שעות ו־$m דקות';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              classification,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              textDirection: TextDirection.rtl,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _row('מי ניהל', _managerLabel()),
        _row('מתי נפתח', _formatTime(createdAt)),
        _row('מתי נסגר', _formatTime(closedAt)),
        _row('משך', _formatDuration()),
        _row('משתתפים', 'יוזם: $initiatorName • מגיבים: $responderCount'),
        if (emergencyCalls.isNotEmpty)
          _row(
            'כוחות שהוזמנו',
            emergencyCalls
                .map((c) => c is Map ? (c['service'] ?? '').toString() : '')
                .where((s) => s.isNotEmpty)
                .toSet()
                .join(', '),
          ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.visibility, size: 18),
            label: const Text('צפה באירוע', textDirection: TextDirection.rtl),
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        textDirection: TextDirection.rtl,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              textDirection: TextDirection.rtl,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
              textDirection: TextDirection.rtl,
            ),
          ),
        ],
      ),
    );
  }
}

// כרטיס אירוע פתוח — פריסה קיימת
class _OpenEventCardContent extends StatelessWidget {
  final String classification;
  final String initiatorName;
  final int responderCount;
  final String address;
  final String city;
  final String distText;
  final bool showRespondButton;
  final VoidCallback onImOnMyWay;
  final VoidCallback onTap;

  const _OpenEventCardContent({
    required this.classification,
    required this.initiatorName,
    required this.responderCount,
    required this.address,
    required this.city,
    required this.distText,
    required this.showRespondButton,
    required this.onImOnMyWay,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              classification,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              textDirection: TextDirection.rtl,
            ),
            Text(
              'מגיבים: $responderCount',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
              textDirection: TextDirection.rtl,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'יוזם: $initiatorName',
          style: const TextStyle(fontSize: 14),
          textDirection: TextDirection.rtl,
        ),
        if (address.isNotEmpty || city.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            address.isNotEmpty ? address : city,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textDirection: TextDirection.rtl,
          ),
        ],
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'מרחק: $distText',
              style: const TextStyle(fontSize: 14),
              textDirection: TextDirection.rtl,
            ),
            if (showRespondButton)
              FilledButton.icon(
                onPressed: onImOnMyWay,
                icon: const Icon(Icons.directions_bike),
                label: const Text('אני בדרך', textDirection: TextDirection.rtl),
              )
            else
              TextButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.visibility, size: 18),
                label: const Text('צפה באירוע', textDirection: TextDirection.rtl),
              ),
          ],
        ),
      ],
    );
  }
}
