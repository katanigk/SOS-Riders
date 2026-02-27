// =============================================================
// PROJECT: rider_drawer.dart
// DEPARTMENT 1 — Rider Drawer
// =============================================================

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rider_sos/models/rider_profile.dart';
import 'package:rider_sos/screens/boot_screen.dart';
import 'package:rider_sos/screens/open_events_screen.dart';
import 'package:rider_sos/screens/rider_profile_screen.dart';

class RiderDrawer extends StatelessWidget {
  final RiderProfile profile;

  const RiderDrawer({
    super.key,
    required this.profile,
  });

  static const String _appVersion = '0.1.0';

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    backgroundImage: profile.avatarUrl != null &&
                            profile.avatarUrl!.isNotEmpty
                        ? NetworkImage(profile.avatarUrl!)
                        : null,
                    child: profile.avatarUrl == null ||
                            profile.avatarUrl!.isEmpty
                        ? Text(
                            profile.fullName.isNotEmpty
                                ? profile.fullName[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimary,
                              fontSize: 24,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    profile.fullName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _statusLabel(profile.status),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.event_note),
              title: const Text('אירועים'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OpenEventsScreen(profile: profile),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('פרופיל ריידר'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RiderProfileScreen(profile: profile),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('יציאה'),
              onTap: () async {
                Navigator.pop(context);
                await FirebaseAuth.instance.signOut();
                if (!context.mounted) return;
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const BootScreen()),
                  (_) => false,
                );
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_forever,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'מחיקת פרופיל ריידר',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => _showDeleteProfileDialog(context),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'גרסה $_appVersion',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteProfileDialog(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          size: 48,
          color: Theme.of(context).colorScheme.error,
        ),
        title: const Text('מחיקת פרופיל ריידר'),
        content: const Text(
          'האם אתה בטוח שברצונך למחוק את פרופיל הריידר שלך?\n\n'
          'פעולה זו תמחק את כל הנתונים שלך לצמיתות ולא ניתן יהיה לשחזר אותם. '
          'תצטרך להירשם מחדש אם תרצה להשתמש באפליקציה שוב.',
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.right,
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('מחק פרופיל ריידר'),
          ),
        ],
      ),
    ).then((confirmed) async {
      if (confirmed != true || !context.mounted) return;
      Navigator.pop(context);
      try {
        await FirebaseFirestore.instance
            .collection('riders')
            .doc(profile.uid)
            .delete();
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          try {
            await user.delete();
          } catch (_) {
            await FirebaseAuth.instance.signOut();
          }
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('שגיאה במחיקה: $e')),
          );
          return;
        }
      }
      if (!context.mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const BootScreen()),
        (_) => false,
      );
    });
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return 'פעיל';
      case 'pending':
        return 'ממתין לאישור';
      case 'blocked':
        return 'חסום';
      default:
        return status;
    }
  }
}
