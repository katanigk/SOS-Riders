const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

admin.initializeApp();

exports.onSosCreated = functions.firestore
  .document("sos_events/{eventId}")
  .onCreate(async (snap, context) => {

    // -------------------------------------------------
    // Room 1.1 — PUSH DISABLED (TEMP)
    // -------------------------------------------------
    console.log(
      "⛔ PUSH DISABLED — event created:",
      context.params.eventId
    );
    return null;

    /*
    // -------------------------------------------------
    // Room 1.2 — PUSH PAYLOAD (INACTIVE)
    // -------------------------------------------------
    const payload = {
      notification: {
        title: "🚨 אירוע מצוקה חדש",
        body: "יש אירוע חריג באזור שלך. כנס לאפליקציה",
      },
      topic: "riders",
    };

    await admin.messaging().send(payload);

    console.log("✅ PUSH SENT for event", context.params.eventId);
    */
  });
