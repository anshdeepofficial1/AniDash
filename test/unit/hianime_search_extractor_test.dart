import 'package:ani_dash/core/registery/sources/anime/aniwatch/extractors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

void main() {
  test('HiAnime search parser supports the current hk-tile layout', () {
    final document = html.parse('''
      <div class="hk-grid hk-results">
        <article class="hk-tile">
          <div class="hk-tile__art">
            <img src="https://hianime.ms/images/poster/one-piece.webp">
            <a class="hk-tile__link"
               href="https://hianime.ms/details/one-piece-1a877"></a>
          </div>
          <h3 class="hk-tile__name">
            <a href="https://hianime.ms/details/one-piece-1a877">
              <span class="hk-dual" data-en="ONE PIECE" data-jp="One Piece">
                ONE PIECE
              </span>
            </a>
          </h3>
          <p class="hk-tile__meta"><span>TV</span><span>1999</span></p>
        </article>
      </div>
      <ul class="pagination">
        <li><a href="/search?keyword=one+piece&page=2">2</a></li>
        <li><a href="/search?keyword=one+piece&page=7">7</a></li>
      </ul>
    ''');

    final result = const SearchExtractor().parseSearch(
      document,
      'https://hianime.ms',
      keyword: 'one piece',
      page: 1,
    );

    expect(result.totalPages, 7);
    expect(result.results, hasLength(1));
    final anime = result.results.single;
    expect(anime.id, 'one-piece-1a877');
    expect(anime.name, 'ONE PIECE');
    expect(anime.jname, 'One Piece');
    expect(anime.type, 'TV');
    expect(anime.poster, 'https://hianime.ms/images/poster/one-piece.webp');
    expect(anime.url, 'https://hianime.ms/details/one-piece-1a877');
  });
}
