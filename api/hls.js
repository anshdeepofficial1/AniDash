export default async function handler(request, response) {
  try {
    const upstream = await fetch('https://unpkg.com/hls.js@1.6.13/dist/hls.min.js');
    if (!upstream.ok) throw new Error(`HLS library returned ${upstream.status}`);
    response.setHeader('Content-Type', 'application/javascript; charset=utf-8');
    response.setHeader('Cache-Control', 'public, max-age=86400, s-maxage=604800');
    response.status(200).send(await upstream.text());
  } catch (error) {
    response.status(502).send(
      `console.error(${JSON.stringify('AniDash player library could not be loaded')});`
    );
  }
}
