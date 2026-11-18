# Patched copy of workmanager_android 0.10.9

Source: pub.dev `workmanager_android` 0.10.9 (MIT, see `LICENSE`). Used through `dependency_overrides` in the app's `pubspec.yaml`.

The only change is in `android/build.gradle`: the conditional `apply plugin: 'kotlin-android'` and the branches for AGP versions before 9 are removed. FitBuddy builds with AGP 9 and built-in Kotlin (`android.builtInKotlin=true`), where that line never runs. Flutter scans plugin build files for it and warns that future versions will refuse to build. The tests folder was not copied.

Drop this copy and the override when a published version no longer has the line. To check:

```bash
grep -n "kotlin-android" ~/.pub-cache/hosted/pub.dev/workmanager_android-*/android/build.gradle
```
