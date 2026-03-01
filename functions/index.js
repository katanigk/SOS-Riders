const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

admin.initializeApp();

// כשנפתח אירוע מצוקה — שליחת התראה קולית לריידרים במצב פעיל
exports.onSosOpenCreated = functions.firestore
  .document("sos_events_open/{eventId}")
  .onCreate(async (snap, context) => {
    const eventId = context.params.eventId;
    const data = snap.data();
    const initiatorUid = data.initiatorUid || null;

    try {
      // ריידרים במצב פעיל
      const presenceSnap = await admin.firestore()
        .collection("rider_presence")
        .where("onDuty", "==", true)
        .get();

      const uids = [];
      presenceSnap.docs.forEach((doc) => {
        const uid = doc.id;
        if (uid !== initiatorUid) {
          uids.push(uid);
        }
      });

      if (uids.length === 0) {
        console.log("No active riders to notify (excluding initiator)");
        return null;
      }

      const tokenPairs = [];
      for (const uid of uids) {
        const riderDoc = await admin.firestore()
          .collection("riders")
          .doc(uid)
          .get();
        const token = riderDoc.exists ? (riderDoc.data()?.fcmToken || "").trim() : "";
        if (token) tokenPairs.push({ uid, token });
      }

      if (tokenPairs.length === 0) {
        console.log("No FCM tokens found for active riders");
        return null;
      }

      const tokens = tokenPairs.map((p) => p.token);

      const message = {
        notification: {
          title: "🚨 אירוע מצוקה חדש",
          body: "יש אירוע מצוקה באזור. כנס לאפליקציה",
        },
        android: {
          notification: {
            defaultSound: true,
            defaultVibrateTimings: false,
            vibrateTimingsMillis: [0, 800, 400, 800, 400, 800],
            priority: "max",
            channelId: "sos_urgent",
          },
        },
        data: {
          type: "sos_new",
          eventId,
        },
        tokens,
      };

      const response = await admin.messaging().sendEachForMulticast(message);
      console.log(
        "PUSH SENT — event:",
        eventId,
        "success:",
        response.successCount,
        "failure:",
        response.failureCount
      );

      // לוג שגיאות + מחיקת tokens לא תקינים
      if (response.failureCount > 0) {
        for (let i = 0; i < response.responses.length; i++) {
          const r = response.responses[i];
          if (!r.success && r.error) {
            const uid = tokenPairs[i]?.uid || "?";
            console.error(
              "FCM failure for uid:",
              uid,
              "code:",
              r.error.code,
              "message:",
              r.error.message
            );
            if (
              r.error.code === "messaging/invalid-registration-token" ||
              r.error.code === "messaging/registration-token-not-registered" ||
              r.error.code === "messaging/mismatched-credential"
            ) {
              try {
                await admin.firestore().collection("riders").doc(uid).update({
                  fcmToken: admin.firestore.FieldValue.delete(),
                });
                console.log("Removed invalid fcmToken for uid:", uid);
              } catch (e) {
                console.error("Failed to remove invalid token:", e.message);
              }
            }
          }
        }
      }

      return null;
    } catch (err) {
      console.error("❌ PUSH ERROR:", err);
      throw err;
    }
  });
