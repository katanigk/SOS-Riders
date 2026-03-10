// =============================================================
// PROJECT: rider_drawer.dart
// DEPARTMENT 1 — Rider Drawer
// =============================================================

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rider_sos/models/rider_profile.dart';
import 'package:rider_sos/screens/boot_screen.dart';
import 'package:rider_sos/screens/open_events_screen.dart';
import 'package:rider_sos/screens/rider_profile_screen.dart';
import 'package:rider_sos/screens/pending_riders_screen.dart';
import 'package:rider_sos/screens/active_riders_screen.dart';
import 'package:rider_sos/screens/my_deliveries_screen.dart';

class RiderDrawer extends StatelessWidget {
  final RiderProfile profile;
  /// האם הריידר במצב פעיל (להצגת האזהרה למועדון)
  final bool? onDuty;

  const RiderDrawer({
    super.key,
    required this.profile,
    this.onDuty,
  });

  @override
  Widget build(BuildContext context) {
    final isClub = _isClub(profile);
    final duty = onDuty ?? false;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StandardHeader(profile: profile),
            if (isClub && !duty)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.error.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    Icon(Icons.info_outline, size: 20, color: Theme.of(context).colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'כדי לקבל הזמנות מלקוחות ולראות אירועים בגזרה — עבור למצב פעיל',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                        textDirection: TextDirection.rtl,
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
            if (_isClub(profile)) ...[
              ListTile(
                leading: const Icon(Icons.local_shipping),
                title: const Text('המשלוחים שלי'),
                subtitle: const Text('משלוחים שביצעתי לפי תקופה'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MyDeliveriesScreen(profile: profile),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.workspace_premium),
                title: const Text('אזור המועדון'),
                subtitle: const Text('פיצ׳רים מיוחדים לריידרי המועדון'),
                onTap: () {
                  Navigator.pop(context);
                  showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('אזור המועדון'),
                      content: const Text(
                        'כאן נוסיף בהמשך כלים ופיצ׳רים מיוחדים לריידרים במועדון (Club Rider).',
                        textDirection: TextDirection.rtl,
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('סגור'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
            if (_isAdmin(profile)) ...[
              ListTile(
                leading: const Icon(Icons.verified),
                title: const Text('אישור רוכבים'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PendingRidersScreen(adminProfile: profile),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.people),
                title: const Text('ריידרים במצב פעיל'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ActiveRidersScreen(adminProfile: profile),
                    ),
                  );
                },
              ),
            ],
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
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snap) {
                final v = snap.data?.version ?? '?';
                final b = snap.data?.buildNumber ?? '';
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'גרסה $v${b.isNotEmpty ? ' ($b)' : ''}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                );
              },
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

  bool _isAdmin(RiderProfile profile) {
    return profile.role == 'admin';
  }

  bool _isClub(RiderProfile profile) {
    return profile.role == 'club' || profile.role == 'admin';
  }

  static String _roleLabel(RiderProfile profile) {
    switch (profile.role) {
      case 'admin':
        return 'אדמין · ריידר מועדון';
      case 'club':
        return 'ריידר מועדון';
      case 'community':
      default:
        return 'ריידר קהילה';
    }
  }
}

// =============================================================
// Header סטנדרטי
// =============================================================

class _StandardHeader extends StatelessWidget {
  final RiderProfile profile;

  const _StandardHeader({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
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
            child: profile.avatarUrl == null || profile.avatarUrl!.isEmpty
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
            RiderDrawer._roleLabel(profile),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
