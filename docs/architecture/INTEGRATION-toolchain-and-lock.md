# Candidate Integration Toolchain

Reproduction SDK: Flutter **3.47.5 stable**, revision
`6a19cca56475dbfba1478ee68d7bd0c2ef891da1`, Dart **3.13.4**.
Use that SDK for controlled integration; floating `stable` alone is not a
reproducible validation toolchain. A future SDK update requires lock validation.

The current resolved graph requires Dart >=3.13 and Flutter >=3.44.
Local package metadata proves `xml 7.1.0` / `petitparser 7.1.0` require Dart
^3.13.0; `shared_preferences_android 2.4.28`, `volume_controller 3.7.1`, and
`wakelock_plus_platform_interface 1.7.0` require Flutter >=3.44.0.
pubspec declares those truthful integration floors; no dependency was downgraded.
The exact lockfile, not the range alone, defines this candidate's resolved graph.

## Fresh Windows Reproduction

In a disposable checkout at the reviewed baseline, using the SDK above:

1. `flutter create --platforms=windows --no-pub .` if scaffolding is missing.
2. `python tool/apply_native_hosts.py windows` applies authoritative host code.
3. Apply the corrected binary product patch, including pubspec and pubspec.lock.
   At this baseline `.gitignore` and `pubspec.lock` are added by the product
   patch: remove only the scaffold-generated copies before applying that patch.
   This instruction is for a fresh disposable checkout, never user-owned files.
   If validating an already patched checkout, preserve and restore the exact
   product lock after `flutter create`; this SDK regenerates it even with no-pub.
4. `flutter pub get --offline --enforce-lockfile` with populated matching cache.
   On a clean online CI cache use `flutter pub get --enforce-lockfile` instead;
   resolution must fail rather than silently upgrade the reviewed graph.
5. `flutter test --no-pub`, `flutter analyze --no-pub --no-fatal-infos`, applicable
   Python policies, `git diff --check`, `flutter build windows --debug --no-pub`.

Do not include generated windows/, .metadata, logs or build artifacts in the
product patch. Native host source/generation tooling stays authoritative.
The separate Windows symlink-fixture helper is not a product dependency and
must remain an isolated policy-test overlay if Windows needs it. Never claim
Apple compile or native seek proof from Windows tests.
