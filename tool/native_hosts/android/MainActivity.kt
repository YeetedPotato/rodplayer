package com.example.rodplayer

import android.content.Context
import android.hardware.display.DisplayManager
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.os.Build
import android.os.Bundle
import android.view.Display
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val methodChannelName = "rodplayer/playback_capabilities"
    private val eventChannelName = "rodplayer/playback_capability_events"
    private var eventSink: EventChannel.EventSink? = null
    private var displayListener: DisplayManager.DisplayListener? = null
    private var audioCallback: AudioDeviceCallback? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "probeCompute" -> result.success(probeCompute())
                    "probeDisplay" -> result.success(probeDisplay())
                    "probeAudio" -> result.success(probeAudio())
                    else -> result.notImplemented()
                }
            } catch (error: Throwable) {
                result.success(null)
            }
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                registerEvents()
            }

            override fun onCancel(arguments: Any?) {
                unregisterEvents()
                eventSink = null
            }
        })
    }

    override fun onResume() {
        super.onResume()
        eventSink?.success("resume")
    }

    private fun probeCompute(): Map<String, Any?> {
        val decoders = mutableListOf<Map<String, Any?>>()
        var hardware = false
        var software = false
        for (codec in MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos) {
            if (codec.isEncoder) continue
            for (type in codec.supportedTypes) {
                val normalized = videoCodec(type) ?: continue
                val caps = runCatching { codec.getCapabilitiesForType(type) }.getOrNull()
                val video = caps?.videoCapabilities
                val isSoftware = Build.VERSION.SDK_INT >= 29 && codec.isSoftwareOnly
                val isHardware = Build.VERSION.SDK_INT >= 29 && codec.isHardwareAccelerated
                hardware = hardware || isHardware
                software = software || isSoftware
                decoders.add(mapOf(
                    "codec" to normalized,
                    "support" to "supported",
                    "hardwareAccelerated" to if (Build.VERSION.SDK_INT >= 29) support(isHardware) else "unknown",
                    "softwareOnly" to if (Build.VERSION.SDK_INT >= 29) support(isSoftware) else "unknown",
                    "vendor" to if (Build.VERSION.SDK_INT >= 29) codec.isVendor else null,
                    "profiles" to (caps?.profileLevels ?: emptyArray()).map { it.profile.toString() },
                    "levels" to (caps?.profileLevels ?: emptyArray()).map { it.level },
                    "maxWidth" to video?.supportedWidths?.upper,
                    "maxHeight" to video?.supportedHeights?.upper,
                    "maxFrameRate" to video?.supportedFrameRates?.upper,
                ))
            }
        }
        return mapOf(
            "hardwareAcceleration" to if (Build.VERSION.SDK_INT >= 29) support(hardware) else "unknown",
            "hardwareVideoDecoding" to if (Build.VERSION.SDK_INT >= 29) support(hardware) else "unknown",
            "softwareVideoDecoding" to if (Build.VERSION.SDK_INT >= 29) support(software) else "unknown",
            "videoDecoders" to decoders,
        )
    }

    private fun probeDisplay(): Map<String, Any?> {
        val display = if (Build.VERSION.SDK_INT >= 30) display else windowManager.defaultDisplay
        val mode = if (Build.VERSION.SDK_INT >= 23) display?.mode else null
        val hdr = if (Build.VERSION.SDK_INT >= 24) display?.hdrCapabilities?.supportedHdrTypes?.toSet() ?: emptySet() else emptySet()
        return mapOf(
            "width" to mode?.physicalWidth,
            "height" to mode?.physicalHeight,
            "refreshRate" to (mode?.refreshRate ?: display?.refreshRate)?.toDouble(),
            "displayId" to display?.displayId?.toString(),
            "hdr10Output" to support(Build.VERSION.SDK_INT >= 24 && hdr.contains(Display.HdrCapabilities.HDR_TYPE_HDR10)),
            "hdr10PlusOutput" to support(Build.VERSION.SDK_INT >= 29 && hdr.contains(Display.HdrCapabilities.HDR_TYPE_HDR10_PLUS)),
            "hlgOutput" to support(Build.VERSION.SDK_INT >= 24 && hdr.contains(Display.HdrCapabilities.HDR_TYPE_HLG)),
            "dolbyVisionOutput" to support(Build.VERSION.SDK_INT >= 24 && hdr.contains(Display.HdrCapabilities.HDR_TYPE_DOLBY_VISION)),
        )
    }

    private fun probeAudio(): Map<String, Any?> {
        val manager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val outputs = if (Build.VERSION.SDK_INT >= 23) manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).toList() else emptyList()
        val device = outputs.firstOrNull { it.isSink }
        val encodings = if (Build.VERSION.SDK_INT >= 23) device?.encodings?.toSet() ?: emptySet() else emptySet()
        return mapOf(
            "routeName" to device?.productName?.toString(),
            "sinkName" to device?.productName?.toString(),
            "pcmOutput" to support(device != null),
            "maxChannels" to if (Build.VERSION.SDK_INT >= 23) device?.channelCounts?.maxOrNull() else null,
            "sampleRates" to if (Build.VERSION.SDK_INT >= 23) device?.sampleRates?.filter { it > 0 } else emptyList<Int>(),
            "passthroughCodecs" to mapOf(
                "ac3" to support(encodings.contains(AudioFormat.ENCODING_AC3)),
                "eac3" to support(encodings.contains(AudioFormat.ENCODING_E_AC3)),
                "truehd" to support(Build.VERSION.SDK_INT >= 23 && encodings.contains(AudioFormat.ENCODING_DOLBY_TRUEHD)),
                "dts" to support(encodings.contains(AudioFormat.ENCODING_DTS) || encodings.contains(AudioFormat.ENCODING_DTS_HD)),
            ),
        )
    }

    private fun registerEvents() {
        unregisterEvents()
        val displayManager = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        displayListener = object : DisplayManager.DisplayListener {
            override fun onDisplayAdded(displayId: Int) = emit("displayChanged")
            override fun onDisplayRemoved(displayId: Int) = emit("displayChanged")
            override fun onDisplayChanged(displayId: Int) = emit("displayChanged")
        }
        displayManager.registerDisplayListener(displayListener, null)
        if (Build.VERSION.SDK_INT >= 23) {
            val manager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audioCallback = object : AudioDeviceCallback() {
                override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) = emit("audioRouteChanged")
                override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) = emit("audioRouteChanged")
            }
            manager.registerAudioDeviceCallback(audioCallback, null)
        }
    }

    private fun unregisterEvents() {
        val displayManager = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        displayListener?.let { displayManager.unregisterDisplayListener(it) }
        displayListener = null
        if (Build.VERSION.SDK_INT >= 23) {
            val manager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audioCallback?.let { manager.unregisterAudioDeviceCallback(it) }
        }
        audioCallback = null
    }

    private fun emit(value: String) {
        eventSink?.success(value)
    }

    private fun support(value: Boolean) = if (value) "supported" else "unsupported"
    private fun videoCodec(mime: String) = when (mime.lowercase()) {
        "video/avc" -> "h264"
        "video/hevc" -> "hevc"
        "video/x-vnd.on2.vp9" -> "vp9"
        "video/av01" -> "av1"
        "video/mpeg2" -> "mpeg2"
        else -> null
    }
}
