package uz.shs.better_player_plus

import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultLoadControl

@UnstableApi
internal class CustomDefaultLoadControl {
    /**
     * The default minimum duration of media that the player will attempt to ensure is buffered
     * at all times, in milliseconds.
     */
    @JvmField
    val minBufferMs: Int

    /**
     * The default maximum duration of media that the player will attempt to buffer, in milliseconds.
     */
    @JvmField
    val maxBufferMs: Int

    /**
     * The default duration of media that must be buffered for playback to start or resume following
     * a user action such as a seek, in milliseconds.
     */
    @JvmField
    val bufferForPlaybackMs: Int

    /**
     * The default duration of media that must be buffered for playback to resume after a rebuffer,
     * in milliseconds.
     */
    @JvmField
    val bufferForPlaybackAfterRebufferMs: Int

    constructor() {
        minBufferMs = 25000
        maxBufferMs = 50000
        bufferForPlaybackMs = 2000
        bufferForPlaybackAfterRebufferMs = 4000
    }

    constructor(
        minBufferMs: Int?,
        maxBufferMs: Int?,
        bufferForPlaybackMs: Int?,
        bufferForPlaybackAfterRebufferMs: Int?
    ) {
        this.minBufferMs = minBufferMs ?: 25000
        this.maxBufferMs = maxBufferMs ?: 50000
        this.bufferForPlaybackMs = bufferForPlaybackMs ?: 2000
        this.bufferForPlaybackAfterRebufferMs = bufferForPlaybackAfterRebufferMs ?: 4000
    }
}
