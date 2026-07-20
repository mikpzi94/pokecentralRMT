// =====================================================================
// PokeCentral — preview de link por LOTE de leilão (Open Graph).
// Vercel serve em /api/leilao. O vercel.json mapeia /l/:id -> /api/leilao?id=:id
// Mostra lance atual + tempo restante + texto de urgência na prévia.
// =====================================================================

const SUPABASE_URL = 'https://gimluwxoaxfxpbcfosrj.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdpbWx1d3hvYXhmeHBiY2Zvc3JqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ0MDIxMzYsImV4cCI6MjA5OTk3ODEzNn0.uT05zvrnqU_sLnVQBFpHkw7TJL-WBUDaSqJ26RVPaSE';
const SITE = 'https://pokecentral-rmt.vercel.app';
const EXTENSAO_MIN = 5;

function esc(s){
  return String(s == null ? '' : s)
    .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
function brl(n){ return 'R$ ' + Number(n||0).toLocaleString('pt-BR',{minimumFractionDigits:2,maximumFractionDigits:2}); }
function tempoTxt(ms){
  var s = Math.floor(ms/1000);
  if(s <= 0) return 'encerrado';
  var d = Math.floor(s/86400), h = Math.floor(s%86400/3600), m = Math.floor(s%3600/60);
  if(d > 0) return d+'d '+h+'h';
  if(h > 0) return h+'h '+m+'m';
  return (m||1)+'m';
}

// mesma regra do leilao.html: mínimo, anti-sniping e compre-já
function apurar(lote, lances){
  var ext = (Number(lote.extensao_seg) || EXTENSAO_MIN*60) * 1000;
  var fim = new Date(lote.fim).getTime();
  var bids = (lances || []).map(function(b){ return { data:new Date(b.criado_em).getTime(), valor:Number(b.valor) }; })
    .sort(function(a,b){ return a.data - b.data; });
  var precoJa = Number(lote.preco_ja) || 0;
  var atual = 0, arrematado = false, n = 0;
  bids.forEach(function(b){
    if(arrematado) return;
    if(b.data > fim) return;
    var minimo = n === 0 ? Number(lote.lance_inicial) : atual + Number(lote.incremento);
    if(b.valor >= minimo){
      atual = b.valor; n++;
      if(precoJa && b.valor >= precoJa){ arrematado = true; fim = b.data; }
      else if(b.data > fim - ext){ fim = b.data + ext; }
    }
  });
  return { fim:fim, atual:atual, arrematado:arrematado };
}

module.exports = async function handler(req, res){
  const id = String((req.query && req.query.id) || '').replace(/[^a-zA-Z0-9-]/g,'');
  const destino = SITE + '/leilao?l=' + encodeURIComponent(id);
  const headers = { apikey: SUPABASE_KEY, Authorization: 'Bearer ' + SUPABASE_KEY };

  let lote = null, lances = [];
  try {
    if(id){
      const [lr, lcr] = await Promise.all([
        fetch(SUPABASE_URL + '/rest/v1/lotes?id=eq.' + encodeURIComponent(id) + '&select=*&limit=1', { headers }),
        fetch(SUPABASE_URL + '/rest/v1/lances?lote_id=eq.' + encodeURIComponent(id) + '&select=valor,criado_em&order=criado_em.asc', { headers })
      ]);
      lote = (await lr.json())[0] || null;
      lances = await lcr.json();
    }
  } catch(e){ /* fallback */ }

  let titulo, desc, img, nome;
  if(lote){
    const a = apurar(lote, lances);
    const resta = a.fim - Date.now();
    const aberto = resta > 0 && !a.arrematado;
    const valorTxt = a.atual ? brl(a.atual) : 'começa em ' + brl(lote.lance_inicial);
    nome = lote.nome;
    titulo = aberto
      ? esc('🔨 LEILÃO ATIVO: ' + lote.nome + ' (IV ' + lote.iv + ') — ' + valorTxt + ' · termina em ' + tempoTxt(resta))
      : esc('🔨 Leilão de ' + lote.nome + ' — ENCERRADO');
    desc = aberto
      ? 'Rolando AGORA no PokeCentral! ⏳ Dá teu lance antes que acabe — não perde.'
      : 'Este leilão já encerrou.';
    img = lote.print ? lote.print
        : (lote.poke_id
             ? 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/' + lote.poke_id + '.png'
             : SITE + '/favicon.png');
  } else {
    nome = 'Leilão';
    titulo = '🔨 Leilão — PokeCentral';
    desc = 'Leilões de Pokémon com lances públicos e imutáveis.';
    img = SITE + '/favicon.png';
  }

  const html =
'<!doctype html><html lang="pt-BR"><head>' +
'<meta charset="utf-8">' +
'<meta name="viewport" content="width=device-width, initial-scale=1">' +
'<title>' + esc(nome) + ' — Leilão PokeCentral</title>' +
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
'<p>Redirecionando pro leilão… <a href="' + esc(destino) + '" style="color:#8fc45a">clique aqui</a></p>' +
'</body></html>';

  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', 's-maxage=60, stale-while-revalidate=120');   // cache curto: leilão muda rápido
  res.status(200).send(html);
};
