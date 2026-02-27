// =============================================================
// PROJECT: rider_profile_screen.dart
// DEPARTMENT 1 — Rider Profile View (Read-Only)
// =============================================================

import 'package:flutter/material.dart';
import 'package:rider_sos/models/rider_profile.dart';
import 'package:rider_sos/screens/edit_profile_screen.dart';

class RiderProfileScreen extends StatelessWidget {
  final RiderProfile profile;

  const RiderProfileScreen({
    super.key,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('פרופיל ריידר')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: CircleAvatar(
                radius: 48,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
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
                          fontSize: 32,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 20),
            _FieldRow(
              label: 'שם פרטי',
              value: profile.firstName,
              onEdit: () => _navigateToEdit(context),
            ),
            const SizedBox(height: 16),
            _FieldRow(
              label: 'שם משפחה',
              value: profile.lastName,
              onEdit: () => _navigateToEdit(context),
            ),
            const SizedBox(height: 16),
            _FieldRow(
              label: 'מייל',
              value: profile.email,
              onEdit: () => _navigateToEdit(context),
            ),
            const SizedBox(height: 16),
            _FieldRow(
              label: 'טלפון',
              value: profile.phone,
              onEdit: () => _navigateToEdit(context),
            ),
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
                for (int i = 0; i < 3; i++)
                  _BikeImagePreview(
                    url: profile.bikePhotoUrls.length > i
                        ? profile.bikePhotoUrls[i]
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: 48),
            ElevatedButton.icon(
              onPressed: () => _navigateToEdit(context),
              icon: const Icon(Icons.edit),
              label: const Text('ערוך פרטים'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToEdit(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(profile: profile),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onEdit;

  const _FieldRow({
    required this.label,
    required this.value,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
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
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onEdit,
          icon: const Icon(Icons.edit),
        ),
      ],
    );
  }
}

class _BikeImagePreview extends StatelessWidget {
  final String? url;

  const _BikeImagePreview({this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 80,
        height: 80,
        color: Colors.grey.shade200,
        child: url != null
            ? Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
              )
            : const Icon(Icons.image_not_supported),
      ),
    );
  }
}
