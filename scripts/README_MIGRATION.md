# מיגרציית אירועי SOS

## הרצת המיגרציה (מעבר מ-sos_events ל-sos_events_open / sos_events_closed)

1. הורד Service Account Key מ-Firebase Console → Project Settings → Service accounts → Generate new private key

2. הגדר את המשתנה:
   ```bash
   set GOOGLE_APPLICATION_CREDENTIALS=path\to\serviceAccountKey.json
   ```

3. הרץ את הסקריפט מתוך תיקיית functions (כדי שיימצא firebase-admin):
   ```bash
   cd functions
   node ..\scripts\migrate_sos_events.js
   ```

4. פרסם את כללי Firestore:
   ```bash
   firebase deploy --only firestore
   ```

5. (אופציונלי) מחק את הקולקשן sos_events הישן מהקונסול לאחר וידוא שהכל עובד.
