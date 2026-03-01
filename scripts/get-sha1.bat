@echo off
echo Getting SHA-1 from debug keystore...
echo.
keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android 2>nul | findstr "SHA1:"
echo.
echo Copy the SHA1 value above and add it in Firebase Console:
echo 1. Firebase Console -^> Project Settings -^> Your apps -^> Android app
echo 2. Add fingerprint -^> Paste SHA-1
echo.
pause
