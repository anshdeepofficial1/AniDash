package com.aayush262.dartotsu_extension_bridge.aniyomi

import eu.kanade.tachiyomi.PreferenceScreen
import eu.kanade.tachiyomi.animesource.AnimeCatalogueSource
import eu.kanade.tachiyomi.animesource.ConfigurableAnimeSource
import eu.kanade.tachiyomi.animesource.model.AnimesPage
import eu.kanade.tachiyomi.animesource.model.SAnime
import eu.kanade.tachiyomi.animesource.model.SEpisode
import eu.kanade.tachiyomi.animesource.model.Video
import eu.kanade.tachiyomi.animesource.online.AnimeHttpSource
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.source.model.SChapter
import eu.kanade.tachiyomi.source.model.SManga
import uy.kohesive.injekt.Injekt
import eu.kanade.tachiyomi.animesource.model.AnimeFilterList
import uy.kohesive.injekt.api.get

class AnimeSourceMethods(sourceID: String, langIndex: Int = 0) : AniyomiSourceMethods {

    private val source: AnimeCatalogueSource
    init {
        val manager = Injekt.get<AniyomiExtensionManager>()
        var extension = manager.getOrFetchInstalledAnimeExtensions().find { ext ->
            ext.pkgName == sourceID ||
            ext.pkgName.equals(sourceID, ignoreCase = true) ||
            ext.name.equals(sourceID, ignoreCase = true) ||
            ext.sources.any { s -> s.id.toString() == sourceID || s.name.equals(sourceID, ignoreCase = true) }
        }
        if (extension == null) {
            extension = manager.fetchInstalledAnimeExtensions()?.find { ext ->
                ext.pkgName == sourceID ||
                ext.pkgName.equals(sourceID, ignoreCase = true) ||
                ext.name.equals(sourceID, ignoreCase = true) ||
                ext.sources.any { s -> s.id.toString() == sourceID || s.name.equals(sourceID, ignoreCase = true) }
            }
        }
        val foundExt = extension ?: throw IllegalArgumentException("Anime source with ID '$sourceID' not found.")

        val matchedSource = foundExt.sources.find { it.id.toString() == sourceID || it.name.equals(sourceID, ignoreCase = true) }
        val src = matchedSource ?: foundExt.sources.getOrNull(langIndex) ?: foundExt.sources.firstOrNull()

        source = src as? AnimeHttpSource ?: src as? AnimeCatalogueSource
                ?: throw IllegalArgumentException("Source with ID '$sourceID' is not an AnimeHttpSource or AnimeCatalogueSource")
    }

    override var baseUrl = (source as? AnimeHttpSource)?.baseUrl

    override suspend fun getPopular(page: Int): AnimesPage = source.getPopularAnime(page)

    override suspend fun getLatestUpdates(page: Int): AnimesPage = source.getLatestUpdates(page)


    override suspend fun getSearchResults(query: String, page: Int): AnimesPage =
        source.getSearchAnime(
            page = page,
            query = query,
            filters = try { source.getFilterList() } catch (e: Throwable) { AnimeFilterList() }
        )

    override suspend fun getDetails(media: SAnime): SAnime = source.getAnimeDetails(media)

    override suspend fun getEpisodeList(media: SAnime): List<SEpisode> = source.getEpisodeList(media)

    override suspend fun getVideoList(episode: SEpisode): List<Video> {
        val httpSource = source as? AnimeHttpSource
        if (httpSource != null && httpSource.javaClass.declaredMethods.any { it.name == "getHosterList" }) {
            try {
                val hosters = httpSource.getHosterList(episode)
                if (hosters.isNotEmpty()) {
                    val allVideos = hosters.flatMap { hoster ->
                        val videos = httpSource.getVideoList(hoster)
                        videos.map { it.copy(videoTitle = "${hoster.hosterName} - ${it.videoTitle}") }
                    }
                    if (allVideos.isNotEmpty()) {
                        return allVideos
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        return source.getVideoList(episode)
    }

    override suspend fun getChapterList(media: SAnime): List<SEpisode> =
        throw UnsupportedOperationException("Chapters are not supported in anime sources.")

    override suspend fun getPageList(chapter: SChapter): List<Page> =
        throw UnsupportedOperationException("Pages are not supported in anime sources.")

    override fun setupPreferenceScreen(screen: PreferenceScreen) {
        if (source is ConfigurableAnimeSource) {
            source.setupPreferenceScreen(screen)
        } else {
            throw NoPreferenceScreenException("This source does not support preferences.")
        }
    }
}
class NoPreferenceScreenException(message: String) : Exception(message)

