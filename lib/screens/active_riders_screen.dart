// =============================================================
// PROJECT: active_riders_screen.dart
// מסך אדמין — ריידרים במצב פעיל (on duty)
// =============================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rider_sos/models/rider_profile.dart';

class ActiveRidersScreen extends StatelessWidget {
  final RiderProfile adminProfile;

  const ActiveRidersScreen({
    super.key,
    required this.adminProfile,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ריידרים במצב פעיל'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('rider_presence')
            .where('onDuty', isEqualTo: true)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text(
                'שגיאה בטעינה: ${snap.error}',
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
                'אין ריידרים במצב פעיל כרגע',
                textDirection: TextDirection.rtl,
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final presenceDoc = docs[index];
              final uid = presenceDoc.id;
              final data = presenceDoc.data();
              final city = (data['city'] ?? '').toString();
              final address = (data['address'] ?? '').toString();
              final displayLocation = address.isNotEmpty ? address : (city.isNotEmpty ? city : '—');

              return _ActiveRiderTile(
                uid: uid,
                location: displayLocation,
              );
            },
          );
        },
      ),
    );
  }
}

class _ActiveRiderTile extends StatelessWidget {
  final String uid;
  final String location;

  const _ActiveRiderTile({
    required this.uid,
    required this.location,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('riders').doc(uid).get(),
      builder: (context, snap) {
        String name = 'ללא שם';
        String phone = '';

        String? avatarUrl;
        if (snap.hasData && snap.data != null && snap.data!.exists) {
          final d = snap.data!.data();
          name = (d?['fullName'] ?? '').toString();
          if (name.isEmpty) name = 'ללא שם';
          phone = (d?['phone'] ?? '').toString();
          final raw = (d?['avatarUrl'] as String?)?.trim();
          avatarUrl = (raw != null && raw.isNotEmpty) ? raw : null;
        }

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.green.shade100,
            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
            child: avatarUrl == null
                ? Icon(Icons.person, color: Colors.green.shade700)
                : null,
          ),
          title: Text(
            name,
            textDirection: TextDirection.rtl,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (phone.isNotEmpty)
                Text(phone, style: const TextStyle(fontSize: 14)),
              Text(
                location,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textDirection: TextDirection.rtl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          trailing: phone.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.phone),
                  onPressed: () async {
                    final uri = Uri(scheme: 'tel', path: phone);
                    try {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    } catch (_) {}
                  },
                  tooltip: 'חייג לריידר',
                )
              : null,
        );
      },
    );
  }
}
