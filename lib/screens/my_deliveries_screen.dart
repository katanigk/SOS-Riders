// =============================================================
// PROJECT: my_deliveries_screen.dart
// "המשלוחים שלי" — ריידרי מועדון רואים את המשלוחים שביצעו
// =============================================================

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:rider_sos/models/rider_profile.dart';

class MyDeliveriesScreen extends StatefulWidget {
  final RiderProfile profile;

  const MyDeliveriesScreen({super.key, required this.profile});

  @override
  State<MyDeliveriesScreen> createState() => _MyDeliveriesScreenState();
}

class _MyDeliveriesScreenState extends State<MyDeliveriesScreen> {
  String _filter = 'today';
  DateTime? _customStart;
  DateTime? _customEnd;

  static const Map<String, String> _filterLabels = {
    'today': 'היום',
    'week': 'השבוע',
    'month': 'החודש',
    'custom': 'התאמה אישית',
  };

  static const int _maxMonthsBack = 12;

  Future<void> _pickCustomDates() async {
    final now = DateTime.now();
    final maxStart = DateTime(now.year, now.month - _maxMonthsBack, 1);
    final range = await showDateRangePicker(
      context: context,
      firstDate: maxStart,
      lastDate: now,
      initialDateRange: _customStart != null && _customEnd != null
          ? DateTimeRange(start: _customStart!, end: _customEnd!)
          : DateTimeRange(
              start: now.subtract(const Duration(days: 30)),
              end: now,
            ),
      locale: const Locale('he'),
    );
    if (range != null && mounted) {
      setState(() {
        _customStart = DateTime(range.start.year, range.start.month, range.start.day);
        _customEnd = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59, 999);
      });
    }
  }

  Query<Map<String, dynamic>> _ordersQuery() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return FirebaseFirestore.instance
          .collection('orders')
          .where('riderUid', isEqualTo: '__none__')
          .orderBy('createdAt', descending: true)
          .limit(1);
    }

    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('orders')
        .where('riderUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true);

    final now = DateTime.now();
    if (_filter == 'today') {
      final start = DateTime(now.year, now.month, now.day);
      q = q.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start));
    } else if (_filter == 'week') {
      final start = now.subtract(const Duration(days: 7));
      q = q.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start));
    } else if (_filter == 'month') {
      final start = DateTime(now.year, now.month, 1);
      q = q.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start));
    } else if (_filter == 'custom' && _customStart != null && _customEnd != null) {
      q = q
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(_customStart!))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(_customEnd!));
    }

    return q;
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'requested':
        return 'ממתין';
      case 'accepted':
        return 'בדרך';
      case 'in_progress':
        return 'בביצוע';
      case 'completed':
        return 'הושלם';
      case 'canceled':
        return 'בוטל';
      default:
        return status;
    }
  }

  Color _statusColor(String status, BuildContext context) {
    switch (status) {
      case 'completed':
        return Theme.of(context).colorScheme.primary;
      case 'in_progress':
      case 'accepted':
        return Colors.orange.shade700;
      case 'canceled':
        return Colors.grey;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('יש להתחבר מחדש')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('המשלוחים שלי', textDirection: ui.TextDirection.rtl),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    textDirection: ui.TextDirection.rtl,
                    children: _filterLabels.entries
                        .map(
                          (e) => Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: FilterChip(
                              label: Text(e.value),
                              selected: _filter == e.key,
                              onSelected: (_) =>
                                  setState(() => _filter = e.key),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                if (_filter == 'custom') ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _pickCustomDates,
                    icon: const Icon(Icons.calendar_month),
                    label: Text(
                      _customStart != null && _customEnd != null
                          ? '${DateFormat('d/M/yyyy').format(_customStart!)} – ${DateFormat('d/M/yyyy').format(_customEnd!)}'
                          : 'בחר טווח (עד $_maxMonthsBack חודשים אחורה)',
                      textDirection: ui.TextDirection.rtl,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _filter == 'custom' && _customStart == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_month, size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 12),
                        Text(
                          'בחר טווח תאריכים',
                          style: TextStyle(color: Colors.grey[600]),
                          textDirection: ui.TextDirection.rtl,
                        ),
                      ],
                    ),
                  )
                : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _ordersQuery().snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'שגיאה: ${snapshot.error}',
                        textDirection: ui.TextDirection.rtl,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.local_shipping_outlined, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'אין משלוחים בתקופה שנבחרה',
                          style: TextStyle(color: Colors.grey[600], fontSize: 16),
                          textDirection: ui.TextDirection.rtl,
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final d = docs[i].data();
                    final createdAt = (d['createdAt'] as Timestamp?)?.toDate();
                    final dateStr = createdAt != null
                        ? DateFormat('d/M/yyyy • HH:mm').format(createdAt)
                        : '—';
                    final status = (d['status'] ?? '').toString();
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        title: Text(
                          d['pickupAddress'] ?? '—',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textDirection: ui.TextDirection.rtl,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '$dateStr • ${((d['totalPrice'] ?? 0) as num).toStringAsFixed(0)} ₪',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 13,
                            ),
                            textDirection: ui.TextDirection.rtl,
                          ),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _statusColor(status, context).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _statusColor(status, context).withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            _statusLabel(status),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _statusColor(status, context),
                            ),
                            textDirection: ui.TextDirection.rtl,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
