from pathlib import Path
import shutil
import sys


ROOT = Path(__file__).resolve().parents[1]
HOSTS = ROOT / "tool" / "native_hosts"


def copy(src: str, dst: str) -> None:
    source = HOSTS / src
    target = ROOT / dst
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)


def patch_windows_cmake() -> None:
    path = ROOT / "windows" / "runner" / "CMakeLists.txt"
    if not path.exists():
        return
    text = path.read_text()
    line = "target_link_libraries(${BINARY_NAME} PRIVATE d3d11 dxguid mmdevapi ole32)\n"
    if line not in text:
        text += "\n" + line
        path.write_text(text)


def patch_android_gradle() -> None:
    groovy = ROOT / "android" / "app" / "build.gradle"
    kotlin = ROOT / "android" / "app" / "build.gradle.kts"
    dependencies = [
        'implementation "androidx.media3:media3-exoplayer:1.4.1"',
        'implementation "androidx.media3:media3-ui:1.4.1"',
        'implementation "io.github.thankimanish:mpv-android-lib:0.1.12"',
    ]
    if groovy.exists():
        text = groovy.read_text()
        if "io.github.thankimanish:mpv-android-lib" in text:
            return
        block = "\ndependencies {\n" + "\n".join(f"    {line}" for line in dependencies) + "\n}\n"
        groovy.write_text(text + block)
    elif kotlin.exists():
        text = kotlin.read_text()
        if "io.github.thankimanish:mpv-android-lib" in text:
            return
        block = '\ndependencies {\n    implementation("androidx.media3:media3-exoplayer:1.4.1")\n    implementation("androidx.media3:media3-ui:1.4.1")\n    implementation("io.github.thankimanish:mpv-android-lib:0.1.12")\n}\n'
        kotlin.write_text(text + block)


def patch_podfile(platform: str) -> None:
    path = ROOT / platform / "Podfile"
    if not path.exists():
        return
    text = path.read_text()
    pod = "MobileVLCKit" if platform == "ios" else "VLCKit"
    if pod in text:
        return
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if line.strip().startswith("target "):
            lines.insert(index + 1, f"  pod '{pod}', '~> 3.3.0'")
            path.write_text("\n".join(lines) + "\n")
            return
    path.write_text(text + f"\npod '{pod}', '~> 3.3.0'\n")


def main(platform: str) -> None:
    if platform == "android":
        copy("android/MainActivity.kt", "android/app/src/main/kotlin/com/example/rodplayer/MainActivity.kt")
        patch_android_gradle()
    elif platform == "ios":
        copy("ios/AppDelegate.swift", "ios/Runner/AppDelegate.swift")
        patch_podfile("ios")
    elif platform == "macos":
        copy("macos/MainFlutterWindow.swift", "macos/Runner/MainFlutterWindow.swift")
        patch_podfile("macos")
    elif platform == "windows":
        copy("windows/flutter_window.cpp", "windows/runner/flutter_window.cpp")
        patch_windows_cmake()
    else:
        raise SystemExit(f"unknown platform: {platform}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: apply_native_hosts.py <android|ios|macos|windows>")
    main(sys.argv[1])
