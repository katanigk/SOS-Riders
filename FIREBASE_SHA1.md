# הוספת SHA-1 ל-Firebase (להתראות FCM)

אם ההתראות נכשלות (`success: 0 failure: 1`), ייתכן שחסר SHA-1 ב-Firebase.

## שלב 1: קבלת SHA-1

הרץ את הסקריפט:
```
scripts\get-sha1.bat
```

או ידנית:
```cmd
keytool -list -v -keystore %USERPROFILE%\.android\debug.keystore -alias androiddebugkey -storepass android
```

חפש את השורה: `SHA1: XX:XX:XX:...` והעתק את הערך.

## שלב 2: הוספה ל-Firebase

1. https://console.firebase.google.com
2. בחר פרויקט: **rider-sos-igor**
3. Project Settings (אייקון גלגל שיניים)
4. Your apps → בחר את האפליקציה **Android**
5. הוסף fingerprint → **Add fingerprint**
6. הדבק את ה-SHA-1 ולחץ Save

## שלב 3: הורדת google-services.json מחדש (אם שינויים)

אם הוספת SHA-1 חדש — Firebase עשוי לייצר `google-services.json` מעודכן.
הורד אותו והחלף ב-`android/app/google-services.json`.

## שלב 4: פריסת Cloud Function המעודכנת

```cmd
cd functions
npm install
firebase deploy --only functions
```
