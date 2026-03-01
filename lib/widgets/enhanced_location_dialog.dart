// =============================================================
// PROJECT: enhanced_location_dialog.dart
// דיאלוג זיהוי מיקום משופר — להנחות את המשתמש להפעיל דיוק מיקום גבוה
// =============================================================

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _keyShown = 'enhanced_location_dialog_shown';

/// מציג את דיאלוג "זיהוי מיקום משופר" פעם אחת.
/// אם המשתמש לוחץ "הפעלה" — פותח את הגדרות המיקום של המערכת.
Future<void> maybeShowEnhancedLocationDialog(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_keyShown) == true) return;
  if (!context.mounted) return;

  final shouldOpenSettings = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const _EnhancedLocationDialog(),
  );

  await prefs.setBool(_keyShown, true);

  if (shouldOpenSettings == true && context.mounted) {
    await Geolocator.openLocationSettings();
  }
}

/// דיאלוג זיהוי מיקום משופר — תואם את דיאלוג Google
class _EnhancedLocationDialog extends StatelessWidget {
  const _EnhancedLocationDialog();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('זיהוי מיקום משופר'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'כדי ליהנות מחוויה יותר טובה, המכשיר צריך להשתמש ב\'זיהוי מיקום משופר\'.',
              ),
              const SizedBox(height: 12),
              const Text(
                'ההגדרה מספקת מיקום מדויק יותר לאפליקציות ולשירותים. '
                'כדי לעשות את זה Google מעבדת מדי פעם נתונים על חיישני מכשיר '
                'ואותות אלחוטיים מהמכשיר שלך כדי לתמוך במיקור המונים של מיקומי אותות אלחוטיים.',
              ),
              const SizedBox(height: 12),
              const Text(
                'השימוש בנתונים האלה נעשה בלי לזהות אותך, כדי לשפר את דיוק המיקום '
                'ולשפר את איכות השירותים מבוססי המיקום.',
              ),
              const SizedBox(height: 12),
              const Text(
                'אפשר לשנות את זה בכל שלב בהגדרות המיקום.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('לא, תודה'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('הפעלה'),
          ),
        ],
      ),
    );
  }
}
