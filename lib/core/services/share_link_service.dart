import 'package:share_plus/share_plus.dart';

class ShareLinkService {
  const ShareLinkService._();

  static const _base = 'https://anidashweb.vercel.app';

  static Future<void> shareAnime({required String id, required String title}) =>
      SharePlus.instance.share(
        ShareParams(
          text: 'Watch $title on AniDash\n$_base/anime/$id',
          subject: '$title · AniDash',
        ),
      );

  static Future<void> shareEpisode({
    required String animeId,
    required String animeTitle,
    required int episode,
  }) => SharePlus.instance.share(
    ShareParams(
      text:
          'Watch $animeTitle · Episode $episode on AniDash\n$_base/episode/$animeId/$episode',
      subject: '$animeTitle · Episode $episode',
    ),
  );
}
