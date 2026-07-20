// =====================================================================
// PokeCentral — preview de link por Pokémon (Open Graph).
// Vercel serve isto em /api/og. O vercel.json mapeia /p/:id -> /api/og?id=:id
// O WhatsApp/Discord lê as tags OG daqui; a pessoa é redirecionada pra loja.
// =====================================================================

const SUPABASE_URL = 'https://gimluwxoaxfxpbcfosrj.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdpbWx1d3hvYXhmeHBiY2Zvc3JqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ0MDIxMzYsImV4cCI6MjA5OTk3ODEzNn0.uT05zvrnqU_sLnVQBFpHkw7TJL-WBUDaSqJ26RVPaSE';
const SITE = 'https://pokecentral-rmt.vercel.app';

function esc(s){
  return String(s == null ? '' : s)
    .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
function brl(n){ return 'R$ ' + Number(n||0).toLocaleString('pt-BR',{minimumFractionDigits:2,maximumFractionDigits:2}); }

module.exports = async function handler(req, res){
  const id = String((req.query && req.query.id) || '').replace(/[^a-zA-Z0-9-]/g,'');
  const destino = SITE + '/loja?p=' + encodeURIComponent(id);

  let p = null;
  try {
    if(id){
      const r = await fetch(
        SUPABASE_URL + '/rest/v1/pokemons?id=eq.' + encodeURIComponent(id) +
        '&status=eq.aprovado&select=nome,iv,nivel,qualidade,preco,print,poke_id&limit=1',
        { headers: { apikey: SUPABASE_KEY, Authorization: 'Bearer ' + SUPABASE_KEY } }
      );
      const data = await r.json();
      p = Array.isArray(data) ? data[0] : null;
    }
  } catch(e){ /* sem dados, cai no fallback */ }

  const titulo = p ? esc(p.nome + ' · IV ' + p.iv + ' · ' + brl(p.preco)) : 'PokeCentral';
  const desc   = p ? 'À venda na loja do PokeCentral — clique pra ver e negociar.'
                   : 'Marketplace e ferramentas de RMT do Poke Idle World.';
  const img    = p && p.print ? p.print
               : (p && p.poke_id
                    ? 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/' + p.poke_id + '.png'
                    : SITE + '/favicon.png');
  const nome   = p ? p.nome : 'Pokémon';

  const html =
'<!doctype html><html lang="pt-BR"><head>' +
'<meta charset="utf-8">' +
'<meta name="viewport" content="width=device-width, initial-scale=1">' +
'<title>' + esc(nome) + ' — PokeCentral</title>' +
'<link rel="icon" href="/favicon.png">' +
'<meta property="og:type" content="website">' +
'<meta property="og:site_name" content="PokeCentral">' +
'<meta property="og:title" content="' + titulo + '">' +
'<meta property="og:description" content="' + esc(desc) + '">' +
'<meta property="og:image" content="' + esc(img) + '">' +
'<meta property="og:url" content="' + esc(destino) + '">' +
'<meta name="twitter:card" content="summary_large_image">' +
'<meta name="twitter:title" content="' + titulo + '">' +
'<meta name="twitter:description" content="' + esc(desc) + '">' +
'<meta name="twitter:image" content="' + esc(img) + '">' +
'<meta http-equiv="refresh" content="0; url=' + esc(destino) + '">' +
'</head><body style="background:#12100c;color:#f2e8d5;font-family:monospace;text-align:center;padding:40px">' +
'<script>location.replace(' + JSON.stringify(destino) + ')</script>' +
'<p>Redirecionando pra loja… <a href="' + esc(destino) + '" style="color:#8fc45a">clique aqui</a></p>' +
'</body></html>';

  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', 's-maxage=300, stale-while-revalidate=600');
  res.status(200).send(html);
}
