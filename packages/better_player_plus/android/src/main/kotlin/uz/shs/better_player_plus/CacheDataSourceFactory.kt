package uz.shs.better_player_plus

import android.content.Context
import android.net.Uri
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.FileDataSource
import androidx.media3.datasource.TransferListener
import androidx.media3.datasource.cache.CacheDataSink
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.exoplayer.upstream.DefaultBandwidthMeter

@UnstableApi
internal class CacheDataSourceFactory(
    private val context: Context,
    private val maxCacheSize: Long,
    private val maxFileSize: Long,
    upstreamDataSource: DataSource.Factory?
) : DataSource.Factory {
    private var defaultDatasourceFactory: DefaultDataSource.Factory? = null

    init {
        val bandwidthMeter = DefaultBandwidthMeter.Builder(context).build()
        upstreamDataSource?.let {
            defaultDatasourceFactory = DefaultDataSource.Factory(context, upstreamDataSource)
            defaultDatasourceFactory?.setTransferListener(bandwidthMeter)
        }
    }

    internal fun createCacheDataSource(): CacheDataSource {
        val betterPlayerCache = BetterPlayerCache.createCache(context, maxCacheSize)
            ?: throw IllegalStateException("Cache can't be null.")

        val upstreamForCache = defaultDatasourceFactory?.createDataSource()
            ?: FileDataSource()

        return CacheDataSource(
            betterPlayerCache,
            upstreamForCache,
            FileDataSource(),
            CacheDataSink(betterPlayerCache, maxFileSize),
            CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR,
            null
        )
    }

    override fun createDataSource(): DataSource {
        // Distinct upstream instances avoid concurrent socket corruption while
        // manifests and keys bypass the media cache.
        val cacheDataSource = createCacheDataSource()
        val upstreamForDirect = defaultDatasourceFactory?.createDataSource()
            ?: FileDataSource()

        return FilterPlaylistCacheDataSource(cacheDataSource, upstreamForDirect)
    }
}

@UnstableApi
internal class FilterPlaylistCacheDataSource(
    private val cacheDataSource: DataSource,
    private val upstreamDataSource: DataSource
) : DataSource {
    private var activeSource: DataSource? = null

    override fun addTransferListener(transferListener: TransferListener) {
        cacheDataSource.addTransferListener(transferListener)
        upstreamDataSource.addTransferListener(transferListener)
    }

    override fun open(dataSpec: DataSpec): Long {
        val uriStr = dataSpec.uri.toString().lowercase()
        // Never cache manifests (.m3u8, .mpd) or decryption keys (.key) in SimpleCache.
        val isManifestOrKey = uriStr.contains(".m3u8") ||
                              uriStr.contains(".mpd") ||
                              uriStr.endsWith(".key") ||
                              uriStr.contains("/key/") ||
                              uriStr.contains("key.php")
        activeSource = if (isManifestOrKey) {
            upstreamDataSource
        } else {
            cacheDataSource
        }
        return activeSource!!.open(dataSpec)
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        return activeSource?.read(buffer, offset, length) ?: -1
    }

    override fun getUri(): Uri? {
        return activeSource?.uri
    }

    override fun getResponseHeaders(): Map<String, List<String>> {
        return activeSource?.responseHeaders ?: emptyMap()
    }

    override fun close() {
        try {
            activeSource?.close()
        } finally {
            activeSource = null
        }
    }
}
