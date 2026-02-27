// =============================================================
// PROJECT: pending_riders_screen.dart
// מסך אדמין — אישור רוכבים חדשים
// =============================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:rider_sos/models/rider_profile.dart';

class PendingRidersScreen extends StatelessWidget {
  final RiderProfile adminProfile;

  const PendingRidersScreen({
    super.key,
    required this.adminProfile,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('אישור רוכבים'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('riders')
            .where('status', isEqualTo: 'pending')
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(
              child: Text(
                'שגיאה בטעינת רשימת הרוכבים',
                textDirection: TextDirection.rtl,
              ),
            );
          }

          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'אין רוכבים ממתינים כרגע',
                textDirection: TextDirection.rtl,
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemBuilder: (context, index) {
              final d = docs[index].data();
              final uid = d['uid'] as String? ?? docs[index].id;
              final name = (d['fullName'] ?? '').toString();
              final phone = (d['phone'] ?? '').toString();
              final createdAt = d['createdAt'] as dynamic;
              String createdText = '';
              if (createdAt is Timestamp) {
                final dt = createdAt.toDate();
                createdText =
                    '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
              }

              return ListTile(
                leading: CircleAvatar(
                  child: Text(
                    name.isNotEmpty ? name[0] : '?',
                  ),
                ),
                title: Text(
                  name.isNotEmpty ? name : 'ללא שם',
                  textDirection: TextDirection.rtl,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (phone.isNotEmpty) Text(phone),
                    if (createdText.isNotEmpty)
                      Text(
                        'נרשם: $createdText',
                        style: const TextStyle(fontSize: 12),
                      ),
                  ],
                ),
                trailing: ElevatedButton(
                  onPressed: () => _approveRider(context, uid),
                  child: const Text('אשר'),
                ),
              );
            },
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemCount: docs.length,
          );
        },
      ),
    );
  }

  Future<void> _approveRider(BuildContext context, String uid) async {
    try {
      await FirebaseFirestore.instance.collection('riders').doc(uid).update({
        'status': 'active',
        'approvedAt': FieldValue.serverTimestamp(),
        'approvedBy': adminProfile.uid,
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('הרוכב אושר בהצלחה')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה באישור רוכב: $e')),
        );
      }
    }
  }
}

