/**
 * מיגרציה: מעביר אירועים מ-sos_events ל-sos_events_open / sos_events_closed
 *
 * הרצה:
 *   1. הגדר GOOGLE_APPLICATION_CREDENTIALS (קובץ service account JSON)
 *   2. מהשורש: node scripts/migrate_sos_events.js
 *
 * או: cd functions && node ../scripts/migrate_sos_events.js
 * (צריך firebase-admin: npm install firebase-admin או להריץ מתוך functions)
 */

const admin = require('firebase-admin');

// אתחול - משתמש ב-default credentials (GOOGLE_APPLICATION_CREDENTIALS)
try {
  admin.initializeApp();
} catch (e) {
  console.error('שגיאה באתחול Firebase. וודא ש-GOOGLE_APPLICATION_CREDENTIALS מוגדר.');
  process.exit(1);
}

const db = admin.firestore();

async function migrate() {
  const sosRef = db.collection('sos_events');
  const openRef = db.collection('sos_events_open');
  const closedRef = db.collection('sos_events_closed');

  const snapshot = await sosRef.get();
  if (snapshot.empty) {
    console.log('אין מסמכים ב-sos_events.');
    return;
  }

  console.log(`נמצאו ${snapshot.size} אירועים למיגרציה.`);

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const status = data.status || 'open';
    const targetColl = status === 'closed' ? closedRef : openRef;
    const eventId = doc.id;

    console.log(`  מעביר ${eventId} (${status})...`);

    const batch = db.batch();

    batch.set(targetColl.doc(eventId), data);

    const responders = await sosRef.doc(eventId).collection('responders').get();
    for (const r of responders.docs) {
      batch.set(targetColl.doc(eventId).collection('responders').doc(r.id), r.data());
    }
    const messages = await sosRef.doc(eventId).collection('messages').get();
    for (const m of messages.docs) {
      batch.set(targetColl.doc(eventId).collection('messages').doc(m.id), m.data());
    }

    await batch.commit();
  }

  console.log('מיגרציה הושלמה בהצלחה.');
  console.log('אפשר כעת למחוק את הקולקשן sos_events ידנית מהקונסול (או להשאיר לגיבוי).');
}

migrate().catch((e) => {
  console.error('שגיאה:', e);
  process.exit(1);
});
