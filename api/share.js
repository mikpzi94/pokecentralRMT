// PokeCentral — preview temporário para anúncios criados no Desktop.
// Os dados ficam no próprio link; nada é salvo no marketplace ou no banco.

const SITE = 'https://pokecentral-rmt.vercel.app';
const MAX_PAYLOAD_LENGTH = 6000;

function esc(value){
  return String(value == null ? '' : value)
    .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
}
function brl(value){ return Number(value || 0).toLocaleString('pt-BR',{style:'currency',currency:'BRL'}); }
function finite(value, fallback){ const number = Number(value); return Number.isFinite(number) ? number : fallback; }
function clean(value, max){ return String(value == null ? '' : value).replace(/[<>\u0000-\u001f]/g,'').slice(0,max); }
function decodePayload(encoded){
  if(!encoded || encoded.length > MAX_PAYLOAD_LENGTH || !/^[a-zA-Z0-9_-]+$/.test(encoded)) return null;
  const padded = encoded.replace(/-/g,'+').replace(/_/g,'/') + '='.repeat((4 - encoded.length % 4) % 4);
  const parsed = JSON.parse(Buffer.from(padded,'base64').toString('utf8'));
  if(!parsed || parsed.v !== 1) return null;
  return parsed;
}
function pokemonImage(speciesId, shiny){
  const id = Math.max(1, Math.floor(finite(speciesId,0)));
  if(!id) return SITE + '/favicon.png';
  const folder = shiny ? 'shiny/' : '';
  return 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/' + folder + id + '.png';
}
function destinationFor(data){
  if(data.destination === 'whatsapp'){
    const phone = clean(data.contact,24).replace(/\D/g,'');
    if(phone.length < 10 || phone.length > 15) return SITE;
    const message = 'Olá! Vi o anúncio do ' + clean(data.species,60) + ' no PokeCentral por ' + brl(data.price) + '.';
    return 'https://wa.me/' + phone + '?text=' + encodeURIComponent(message);
  }
  if(data.destination === 'discord'){
    const id = clean(data.contact,24).replace(/\D/g,'');
    if(!/^\d{17,20}$/.test(id)) return 'https://discord.com/app';
    return 'https://discord.com/users/' + id;
  }
  return SITE;
}

module.exports = async function handler(req,res){
  let data = null;
  try { data = decodePayload(String((req.query && req.query.data) || '')); } catch(e) { data = null; }
  if(!data){ res.status(400).send('Link de anúncio inválido.'); return; }

  const expiresAt = finite(data.expiresAt,0);
  const expired = expiresAt > 0 && Date.now() > expiresAt;
  const destination = expired ? SITE : destinationFor(data);
  const species = clean(data.species,60) || 'Pokémon';
  const player = clean(data.player,50) || 'Jogador não identificado';
  const rarity = clean(data.rarity,24) || 'Sem raridade';
  const title = expired ? 'Anúncio expirado — PokeCentral' : species + ' · IV ' + clean(data.iv,8) + ' · ' + brl(data.price);
  const description = expired
    ? 'Este link temporário expirou. Peça um novo link ao vendedor.'
    : rarity + ' · Quality ' + clean(data.quality,10) + ' · Power ' + clean(data.power,16) + ' · Jogador ' + player + (data.negotiable ? ' · Aceita propostas' : ' · Preço fixo');
  const image = pokemonImage(data.speciesId,Boolean(data.shiny));
  const canonical = SITE + '/s/' + encodeURIComponent(String(req.query.data || ''));
  const statusText = expired ? 'Este anúncio expirou.' : 'Abrindo o contato do vendedor…';

  const html = '<!doctype html><html lang="pt-BR"><head>' +
    '<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">' +
    '<title>' + esc(title) + '</title><link rel="icon" href="/favicon.png">' +
    '<meta property="og:type" content="website"><meta property="og:site_name" content="PokeCentral">' +
    '<meta property="og:title" content="' + esc(title) + '"><meta property="og:description" content="' + esc(description) + '">' +
    '<meta property="og:image" content="' + esc(image) + '"><meta property="og:url" content="' + esc(canonical) + '">' +
    '<meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="' + esc(title) + '">' +
    '<meta name="twitter:description" content="' + esc(description) + '"><meta name="twitter:image" content="' + esc(image) + '">' +
    (!expired ? '<meta http-equiv="refresh" content="1;url=' + esc(destination) + '">' : '') +
    '</head><body style="margin:0;background:#12100c;color:#f2e8d5;font-family:monospace;display:grid;place-items:center;min-height:100vh">' +
    '<main style="max-width:680px;padding:32px;border:2px solid #f0b429;background:#1d1811;text-align:center">' +
    '<img src="' + esc(image) + '" alt="" style="width:180px;height:180px;object-fit:contain">' +
    '<h1 style="color:#f0b429">' + esc(species) + '</h1><p>' + esc(description) + '</p><strong style="font-size:26px">' + esc(brl(data.price)) + '</strong>' +
    '<p style="color:#a89880">' + esc(statusText) + '</p>' +
    (!expired ? '<p><a href="' + esc(destination) + '" style="color:#8fc45a">Abrir contato</a></p><script>setTimeout(function(){location.replace(' + JSON.stringify(destination) + ')},1000)</script>' : '') +
    '</main></body></html>';

  res.setHeader('Content-Type','text/html; charset=utf-8');
  res.setHeader('Cache-Control','public, max-age=60, s-maxage=300, stale-while-revalidate=600');
  res.setHeader('X-Robots-Tag','noindex, nofollow');
  res.status(200).send(html);
};
