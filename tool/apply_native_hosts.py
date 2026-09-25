from pathlib import Path
import plistlib
import re
import shutil
import sys


ROOT = Path(__file__).resolve().parents[1]
HOSTS = ROOT / "tool" / "native_hosts"
VLCKIT_COREGRAPHICS_HELPER = """\
def rodplayer_patch_vlckit_coregraphics(installer)
  header = File.join(installer.sandbox.root, 'VLCKit', 'VLCKit.framework', 'Headers', 'VLCMediaThumbnailer.h')
  original = "#if TARGET_OS_IPHONE\\n# import <CoreGraphics/CoreGraphics.h>\\n#endif"
  replacement = '#import <CoreGraphics/CoreGraphics.h>'
  raise 'RodPlayer expected VLCKit header was not installed' unless File.file?(header)

  contents = File.read(header)
  return if contents.include?(replacement)
  raise 'RodPlayer cannot safely patch VLCKit header' unless contents.scan(original).length == 1
  File.write(header, contents.sub(original, replacement))
end
"""
VLCKIT_POST_INSTALL_HOOK = "  rodplayer_patch_vlckit_coregraphics(installer)\n"


def copy(src: str, dst: str) -> None:
    source = HOSTS / src
    target = ROOT / dst
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)


def append_apple_gateway(dst: str) -> None:
    target = ROOT / dst
    ownership = (HOSTS / "apple" / "ApplePrivateNetworkBootstrapOwnership.swift").read_text()
    gateway = (HOSTS / "apple" / "AppleLoopbackGateway.swift").read_text()
    target.write_text(target.read_text().rstrip() + "\n\n" + ownership + "\n\n" + gateway)


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
        'implementation "dev.jdtech.mpv:libmpv:1.0.0"',
    ]
    if groovy.exists():
        text = groovy.read_text()
        text = text.replace(
            "minSdkVersion flutter.minSdkVersion",
            "minSdkVersion 26",
        )
        if "io.github.thankimanish:mpv-android-lib" in text:
            groovy.write_text(text.replace("io.github.thankimanish:mpv-android-lib:0.1.12", "dev.jdtech.mpv:libmpv:1.0.0"))
            return
        if "dev.jdtech.mpv:libmpv" in text:
            groovy.write_text(text)
            return
        block = "\ndependencies {\n" + "\n".join(f"    {line}" for line in dependencies) + "\n}\n"
        groovy.write_text(text + block)
    elif kotlin.exists():
        text = kotlin.read_text()
        text = text.replace(
            "minSdk = flutter.minSdkVersion",
            "minSdk = 26",
        )
        if "io.github.thankimanish:mpv-android-lib" in text:
            kotlin.write_text(text.replace("io.github.thankimanish:mpv-android-lib:0.1.12", "dev.jdtech.mpv:libmpv:1.0.0"))
            return
        if "dev.jdtech.mpv:libmpv" in text:
            kotlin.write_text(text)
            return
        block = '\ndependencies {\n    implementation("androidx.media3:media3-exoplayer:1.4.1")\n    implementation("androidx.media3:media3-ui:1.4.1")\n    implementation("dev.jdtech.mpv:libmpv:1.0.0")\n}\n'
        kotlin.write_text(text + block)


def patch_podfile(platform: str) -> None:
    path = ROOT / platform / "Podfile"
    if not path.exists():
        return
    text = path.read_text()
    pod = "MobileVLCKit" if platform == "ios" else "VLCKit"
    mesh_pod_path = "../build/apple_mesh/ios" if platform == "ios" else "../build/apple_mesh/macos"
    target_platform = "ios" if platform == "ios" else "osx"
    target_version = "18.1" if platform == "ios" else "15.0"
    deployment_comment = "# Deployment target is the oldest supported OS; Xcode selects the newest SDK."
    pods = [
        f"  pod '{pod}', '~> 3.3.0'",
        f"  pod 'RodPlayerTailscaleKit', :path => '{mesh_pod_path}'",
    ]
    target_pattern = re.compile(r"^\s*#?\s*platform\s+:(?:ios|osx),\s*'[^']+'\s*$")
    lines = [line for line in text.splitlines() if not target_pattern.match(line) and line != deployment_comment]
    lines[0:0] = [deployment_comment, f"platform :{target_platform}, '{target_version}'"]
    for index, line in enumerate(lines):
        if line.strip().startswith("target "):
            for pod_line in reversed(pods):
                if pod_line not in lines:
                    lines.insert(index + 1, pod_line)
            patched = "\n".join(lines) + "\n"
            if platform == "macos":
                patched = patch_macos_vlckit_podfile(patched)
            path.write_text(patched)
            return
    for pod_line in pods:
        if pod_line not in lines:
            lines.append(pod_line)
    patched = "\n".join(lines) + "\n"
    if platform == "macos":
        patched = patch_macos_vlckit_podfile(patched)
    path.write_text(patched)


def patch_macos_vlckit_podfile(text: str) -> str:
    if VLCKIT_COREGRAPHICS_HELPER not in text:
        post_install = "post_install do |installer|\n"
        if text.count(post_install) != 1:
            raise RuntimeError("expected one generated macOS Podfile post_install block")
        text = text.replace(post_install, f"{VLCKIT_COREGRAPHICS_HELPER}\n{post_install}")
    post_install = "post_install do |installer|\n"
    if text.count(post_install) != 1:
        raise RuntimeError("expected one generated macOS Podfile post_install block")
    if VLCKIT_POST_INSTALL_HOOK not in text:
        text = text.replace(post_install, f"{post_install}{VLCKIT_POST_INSTALL_HOOK}")
    return text


def patch_macos_deployment_target() -> None:
    path = ROOT / "macos" / "Runner.xcodeproj" / "project.pbxproj"
    if not path.exists():
        return
    text = path.read_text()
    # Deployment targets express the oldest supported OS; Xcode selects the SDK.
    updated = re.sub(
        r"MACOSX_DEPLOYMENT_TARGET = [^;]+;",
        "MACOSX_DEPLOYMENT_TARGET = 15.0;",
        text,
    )
    if updated != text:
        path.write_text(updated)


def patch_macos_entitlements(root: Path = ROOT) -> None:
    for name in ("DebugProfile.entitlements", "Release.entitlements"):
        path = root / "macos" / "Runner" / name
        if not path.exists():
            raise FileNotFoundError(f"missing generated macOS entitlement file: {path}")
        with path.open("rb") as handle:
            entitlements = plistlib.load(handle)
        entitlements["com.apple.security.network.client"] = True
        entitlements["com.apple.security.network.server"] = True
        with path.open("wb") as handle:
            plistlib.dump(entitlements, handle)


def patch_ios_deployment_target() -> None:
    path = ROOT / "ios" / "Runner.xcodeproj" / "project.pbxproj"
    if not path.exists():
        return
    text = path.read_text()
    # Deployment targets express the oldest supported OS; Xcode selects the SDK.
    updated = re.sub(
        r"IPHONEOS_DEPLOYMENT_TARGET = [^;]+;",
        "IPHONEOS_DEPLOYMENT_TARGET = 18.1;",
        text,
    )
    if updated != text:
        path.write_text(updated)


def main(platform: str) -> None:
    if platform == "android":
        copy("android/MainActivity.kt", "android/app/src/main/kotlin/com/example/rodplayer/MainActivity.kt")
        patch_android_gradle()
    elif platform == "ios":
        copy("ios/AppDelegate.swift", "ios/Runner/AppDelegate.swift")
        append_apple_gateway("ios/Runner/AppDelegate.swift")
        patch_podfile("ios")
        patch_ios_deployment_target()
    elif platform == "macos":
        copy("macos/MainFlutterWindow.swift", "macos/Runner/MainFlutterWindow.swift")
        append_apple_gateway("macos/Runner/MainFlutterWindow.swift")
        patch_podfile("macos")
        patch_macos_deployment_target()
        patch_macos_entitlements()
    elif platform == "windows":
        copy("windows/flutter_window.cpp", "windows/runner/flutter_window.cpp")
        patch_windows_cmake()
    else:
        raise SystemExit(f"unknown platform: {platform}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: apply_native_hosts.py <android|ios|macos|windows>")
    main(sys.argv[1])
