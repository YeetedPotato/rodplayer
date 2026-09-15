package com.example.rodplayer

import android.content.Context
import android.hardware.display.DisplayManager
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Display
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import dev.jdtech.mpv.MPVLib
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val methodChannelName = "rodplayer/playback_capabilities"
    private val eventChannelName = "rodplayer/playback_capability_events"
    private val playbackMethodChannelName = "rodplayer/android_playback"
    private val playbackEventChannelName = "rodplayer/android_playback_events"
    private val playbackViewType = "rodplayer/android_playback_view"
    private val compatibilityMethodChannelName = "rodplayer/android_compatibility_playback"
    private val compatibilityEventChannelName = "rodplayer/android_compatibility_playback_events"
    private val compatibilityViewType = "rodplayer/android_compatibility_playback_view"
    private var eventSink: EventChannel.EventSink? = null
    private var displayListener: DisplayManager.DisplayListener? = null
    private var audioCallback: AudioDeviceCallback? = null
    private lateinit var playbackManager: AndroidPlaybackManager
    private lateinit var compatibilityManager: AndroidCompatibilityPlaybackManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        playbackManager = AndroidPlaybackManager(this)
        compatibilityManager = AndroidCompatibilityPlaybackManager(this)
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, playbackMethodChannelName).setMethodCallHandler(playbackManager::handle)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, playbackEventChannelName).setStreamHandler(playbackManager)
        flutterEngine.platformViewsController.registry.registerViewFactory(playbackViewType, AndroidPlaybackViewFactory(playbackManager))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, compatibilityMethodChannelName).setMethodCallHandler(compatibilityManager::handle)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, compatibilityEventChannelName).setStreamHandler(compatibilityManager)
        flutterEngine.platformViewsController.registry.registerViewFactory(compatibilityViewType, AndroidCompatibilityPlaybackViewFactory(compatibilityManager))
    }

    override fun onResume() {
        super.onResume()
        eventSink?.success("resume")
    }

    override fun onDestroy() {
        if (::playbackManager.isInitialized) playbackManager.disposeAll()
        if (::compatibilityManager.isInitialized) compatibilityManager.disposeAll()
        super.onDestroy()
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

private class AndroidCompatibilityPlaybackManager(private val context: Context) : EventChannel.StreamHandler {
    private val sessions = mutableMapOf<String, AndroidCompatibilityPlaybackSession>()
    private var eventSink: EventChannel.EventSink? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ping" -> result.success(runCatching { Class.forName("dev.jdtech.mpv.MPVLib"); true }.getOrElse { false })
            "create" -> {
                val url = call.argument<String>("url")
                if (url.isNullOrBlank()) {
                    result.error("bad_url", "Missing playback URL", null)
                    return
                }
                val handle = UUID.randomUUID().toString()
                sessions[handle] = AndroidCompatibilityPlaybackSession(context, handle, url) { eventSink?.success(it) }
                result.success(handle)
            }
            "play" -> command(call, result) { it.play() }
            "pause" -> command(call, result) { it.pause() }
            "seek" -> command(call, result) { it.seek(call.argument<Number>("positionMillis")?.toLong() ?: 0L) }
            "stop" -> command(call, result) { it.stop() }
            "volume" -> command(call, result) { it.setVolume((call.argument<Number>("volume")?.toFloat() ?: 100f) / 100f) }
            "mute" -> command(call, result) { it.setMuted(call.argument<Boolean>("muted") ?: false) }
            "dispose" -> {
                val handle = call.argument<String>("handle")
                if (handle == null) {
                    result.error("bad_handle", "Missing player handle", null)
                    return
                }
                sessions.remove(handle)?.dispose()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun attachSurface(handle: String?, holder: SurfaceHolder?) {
        handle?.let { sessions[it]?.attachSurface(holder) }
    }

    fun disposeAll() {
        val handles = sessions.keys.toList()
        for (handle in handles) sessions.remove(handle)?.dispose()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun command(call: MethodCall, result: MethodChannel.Result, action: (AndroidCompatibilityPlaybackSession) -> Unit) {
        val handle = call.argument<String>("handle")
        val session = handle?.let { sessions[it] }
        if (session == null) {
            result.error("bad_handle", "Unknown player handle", null)
            return
        }
        action(session)
        result.success(null)
    }
}

private class AndroidCompatibilityPlaybackSession(
    context: Context,
    private val handle: String,
    private val url: String,
    private val emit: (Map<String, Any?>) -> Unit,
) : MPVLib.EventObserver, MPVLib.LogObserver {
    private val handler = Handler(Looper.getMainLooper())
    private val mpv: MPVLib = MPVLib.create(context) ?: throw IllegalStateException("Unable to create mpv playback context")
    private var disposed = false
    private var muted = false
    private var desiredVolume = 1f
    private val positionTick = object : Runnable {
        override fun run() {
            sendState()
            if (!disposed) handler.postDelayed(this, 1000)
        }
    }

    init {
        mpv.addObserver(this)
        mpv.addLogObserver(this)
        mpv.init()
        mpv.command(arrayOf("loadfile", url))
        handler.post(positionTick)
        sendState()
    }

    fun attachSurface(holder: SurfaceHolder?) {
        if (disposed) return
        if (holder == null) mpv.detachSurface() else mpv.attachSurface(holder.surface)
    }

    fun play() {
        mpv.setPropertyBoolean("pause", false)
        sendState()
    }

    fun pause() {
        mpv.setPropertyBoolean("pause", true)
        sendState()
    }

    fun seek(positionMillis: Long) {
        mpv.command(arrayOf("seek", (positionMillis / 1000.0).toString(), "absolute"))
        sendState()
    }

    fun stop() {
        mpv.command(arrayOf("stop"))
        sendState()
    }

    fun setVolume(value: Float) {
        desiredVolume = value.coerceIn(0f, 1f)
        if (!muted) mpv.setPropertyDouble("volume", desiredVolume * 100.0)
        sendState()
    }

    fun setMuted(value: Boolean) {
        muted = value
        mpv.setPropertyBoolean("mute", muted)
        if (!muted) mpv.setPropertyDouble("volume", desiredVolume * 100.0)
        sendState()
    }

    override fun event(eventId: Int) {
        if (eventId == MPVLib.MpvEvent.MPV_EVENT_END_FILE) sendState(ended = true)
    }

    override fun eventProperty(property: String) = sendState()
    override fun eventProperty(property: String, value: Long) = sendState()
    override fun eventProperty(property: String, value: Boolean) = sendState()
    override fun eventProperty(property: String, value: String) = sendState()
    override fun eventProperty(property: String, value: Double) = sendState()

    override fun logMessage(prefix: String, level: Int, text: String) {
        if (level <= MPVLib.MpvLogLevel.MPV_LOG_LEVEL_ERROR) sendState(error = "$prefix: $text")
    }

    private fun sendState(error: String? = null, ended: Boolean = false) {
        if (disposed) return
        emit(mapOf(
            "handle" to handle,
            "playing" to !(mpv.getPropertyBoolean("pause") ?: false),
            "buffering" to false,
            "positionMillis" to (((mpv.getPropertyDouble("time-pos") ?: 0.0) * 1000).toLong()),
            "durationMillis" to (((mpv.getPropertyDouble("duration") ?: 0.0) * 1000).toLong()),
            "volume" to (desiredVolume * 100.0),
            "muted" to muted,
            "error" to error,
            "ended" to ended,
        ))
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        handler.removeCallbacks(positionTick)
        runCatching { mpv.detachSurface() }
        runCatching { mpv.command(arrayOf("stop")) }
        mpv.removeObserver(this)
        mpv.removeLogObserver(this)
        mpv.destroy()
    }
}

private class AndroidCompatibilityPlaybackPlatformView(
    context: Context,
    handle: String?,
    private val manager: AndroidCompatibilityPlaybackManager,
) : PlatformView, SurfaceHolder.Callback {
    private val view = SurfaceView(context)
    private val playerHandle = handle

    init {
        view.holder.addCallback(this)
    }

    override fun getView(): View = view
    override fun surfaceCreated(holder: SurfaceHolder) = manager.attachSurface(playerHandle, holder)
    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) = manager.attachSurface(playerHandle, holder)
    override fun surfaceDestroyed(holder: SurfaceHolder) = manager.attachSurface(playerHandle, null)

    override fun dispose() {
        view.holder.removeCallback(this)
        manager.attachSurface(playerHandle, null)
    }
}

private class AndroidCompatibilityPlaybackViewFactory(private val manager: AndroidCompatibilityPlaybackManager) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val handle = (args as? Map<*, *>)?.get("handle") as? String
        return AndroidCompatibilityPlaybackPlatformView(context, handle, manager)
    }
}

private class AndroidPlaybackManager(private val context: Context) : EventChannel.StreamHandler {
    private val sessions = mutableMapOf<String, AndroidPlaybackSession>()
    private var eventSink: EventChannel.EventSink? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ping" -> result.success(true)
            "create" -> {
                val url = call.argument<String>("url")
                if (url.isNullOrBlank()) {
                    result.error("bad_url", "Missing playback URL", null)
                    return
                }
                val handle = UUID.randomUUID().toString()
                sessions[handle] = AndroidPlaybackSession(context, handle, Uri.parse(url)) { eventSink?.success(it) }
                result.success(handle)
            }
            "play" -> command(call, result) { it.play() }
            "pause" -> command(call, result) { it.pause() }
            "seek" -> command(call, result) { it.seek(call.argument<Number>("positionMillis")?.toLong() ?: 0L) }
            "stop" -> command(call, result) { it.stop() }
            "volume" -> command(call, result) { it.setVolume((call.argument<Number>("volume")?.toFloat() ?: 100f) / 100f) }
            "mute" -> command(call, result) { it.setMuted(call.argument<Boolean>("muted") ?: false) }
            "dispose" -> {
                val handle = call.argument<String>("handle")
                if (handle == null) {
                    result.error("bad_handle", "Missing player handle", null)
                    return
                }
                sessions.remove(handle)?.dispose()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun player(handle: String?): ExoPlayer? = handle?.let { sessions[it]?.player }

    fun disposeAll() {
        val handles = sessions.keys.toList()
        for (handle in handles) {
            sessions.remove(handle)?.dispose()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun command(call: MethodCall, result: MethodChannel.Result, action: (AndroidPlaybackSession) -> Unit) {
        val handle = call.argument<String>("handle")
        val session = handle?.let { sessions[it] }
        if (session == null) {
            result.error("bad_handle", "Unknown player handle", null)
            return
        }
        action(session)
        result.success(null)
    }
}

private class AndroidPlaybackSession(
    context: Context,
    private val handle: String,
    uri: Uri,
    private val emit: (Map<String, Any?>) -> Unit,
) : Player.Listener {
    val player: ExoPlayer = ExoPlayer.Builder(context).build()
    private val handler = Handler(Looper.getMainLooper())
    private var disposed = false
    private var muted = false
    private var desiredVolume = 1f
    private val positionTick = object : Runnable {
        override fun run() {
            sendState()
            if (!disposed) handler.postDelayed(this, 1000)
        }
    }

    init {
        player.addListener(this)
        player.setMediaItem(MediaItem.fromUri(uri))
        player.prepare()
        player.playWhenReady = true
        handler.post(positionTick)
        sendState()
    }

    fun play() {
        player.play()
        sendState()
    }

    fun pause() {
        player.pause()
        sendState()
    }

    fun seek(positionMillis: Long) {
        player.seekTo(positionMillis.coerceAtLeast(0))
        sendState()
    }

    fun stop() {
        player.pause()
        player.seekTo(0)
        sendState()
    }

    fun setVolume(value: Float) {
        desiredVolume = value.coerceIn(0f, 1f)
        if (!muted) player.volume = desiredVolume
        sendState()
    }

    fun setMuted(value: Boolean) {
        if (muted == value) {
            sendState()
            return
        }
        muted = value
        player.volume = if (muted) 0f else desiredVolume
        sendState()
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        sendState()
    }

    override fun onPlaybackStateChanged(playbackState: Int) {
        sendState(ended = playbackState == Player.STATE_ENDED)
    }

    override fun onPlayerError(error: PlaybackException) {
        sendState(error = "${error.errorCodeName}: ${error.message ?: "Playback failed"}")
    }

    private fun sendState(error: String? = null, ended: Boolean = false) {
        if (disposed) return
        val duration = if (player.duration == C.TIME_UNSET) 0L else player.duration.coerceAtLeast(0)
        emit(mapOf(
            "handle" to handle,
            "playing" to player.isPlaying,
            "buffering" to (player.playbackState == Player.STATE_BUFFERING),
            "positionMillis" to player.currentPosition.coerceAtLeast(0),
            "durationMillis" to duration,
            "volume" to (desiredVolume * 100.0),
            "muted" to muted,
            "error" to error,
            "ended" to ended,
        ))
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        handler.removeCallbacks(positionTick)
        player.removeListener(this)
        player.release()
    }
}

private class AndroidPlaybackPlatformView(
    context: Context,
    handle: String?,
    manager: AndroidPlaybackManager,
) : PlatformView {
    private val view = PlayerView(context)

    init {
        view.useController = false
        view.resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
        view.player = manager.player(handle)
    }

    override fun getView(): View = view

    override fun dispose() {
        view.player = null
    }
}

private class AndroidPlaybackViewFactory(private val manager: AndroidPlaybackManager) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val handle = (args as? Map<*, *>)?.get("handle") as? String
        return AndroidPlaybackPlatformView(context, handle, manager)
    }
}
