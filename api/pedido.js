const SUPABASE_URL = 'https://gimluwxoaxfxpbcfosrj.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdpbWx1d3hvYXhmeHBiY2Zvc3JqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ0MDIxMzYsImV4cCI6MjA5OTk3ODEzNn0.uT05zvrnqU_sLnVQBFpHkw7TJL-WBUDaSqJ26RVPaSE';
const SITE = 'https://pokecentral-rmt.vercel.app';

function esc(value){
  return String(value == null ? '' : value)
    .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
function brl(value){
  return 'R$ ' + Number(value || 0).toLocaleString('pt-BR',{minimumFractionDigits:2,maximumFractionDigits:2});
}
function orcamento(p){
  const min = Number(p.preco_min) || 0;
  const max = Number(p.preco_max) || 0;
  if(min && max && min !== max) return brl(min) + ' a ' + brl(max);
  return 'até ' + brl(max || min);
}

module.exports = async function handler(req,res){
  const id = String((req.query && req.query.id) || '').replace(/[^a-zA-Z0-9-]/g,'');
  const destino = SITE + '/loja?pedido=' + encodeURIComponent(id);
  const headers = {apikey:SUPABASE_KEY, Authorization:'Bearer ' + SUPABASE_KEY};
  let p = null;

  try {
    if(id){
      const r = await fetch(
        SUPABASE_URL + '/rest/v1/pedidos?id=eq.' + encodeURIComponent(id) +
        '&status=eq.aprovado&ativo=eq.true&select=pokemon_nome,poke_id,iv_min,qualidade_min,nivel_min,shiny,preco_min,preco_max,obs&limit=1',
        {headers}
      );
      const data = await r.json();
      p = Array.isArray(data) ? data[0] : null;
    }
  } catch(e){}

  let nome = 'Pedido da comunidade';
  let titulo = 'Pedidos da comunidade · PokeCentral';
  let desc = 'Veja os Pokémon que os jogadores estão procurando.';
  let img = SITE + '/favicon.png';

  if(p){
    nome = p.pokemon_nome || 'Pokémon';
    titulo = '🔎 Procuro: ' + nome + ' · pago ' + orcamento(p);
    const reqs = [];
    if(p.iv_min != null) reqs.push('IV ' + p.iv_min + '+');
    if(p.qualidade_min != null) reqs.push('Qualidade ' + p.qualidade_min + '+');
    if(p.nivel_min != null) reqs.push('Nível ' + p.nivel_min + '+');
    if(String(p.shiny || '').toLowerCase() === 'sim') reqs.push('Shiny');
    desc = (reqs.length ? reqs.join(' · ') + '. ' : '') +
      (p.obs ? p.obs + ' ' : '') + 'Você tem este Pokémon? Veja o pedido no PokeCentral.';
    if(p.poke_id) img = 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/' + p.poke_id + '.png';
  }

  const canonical = SITE + '/pedido/' + id;
  const html = '<!doctype html><html lang="pt-BR"><head>' +
    '<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">' +
    '<title>' + esc(nome) + ' — Pedido no PokeCentral</title><link rel="icon" href="/favicon.png">' +
    '<meta property="og:type" content="website"><meta property="og:site_name" content="PokeCentral">' +
    '<meta property="og:title" content="' + esc(titulo) + '"><meta property="og:description" content="' + esc(desc) + '">' +
    '<meta property="og:image" content="' + esc(img) + '"><meta property="og:image:width" content="475"><meta property="og:image:height" content="475">' +
    '<meta property="og:url" content="' + esc(canonical) + '">' +
    '<meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="' + esc(titulo) + '">' +
    '<meta name="twitter:description" content="' + esc(desc) + '"><meta name="twitter:image" content="' + esc(img) + '">' +
    '<meta http-equiv="refresh" content="0;url=' + esc(destino) + '"></head>' +
    '<body style="background:#12100c;color:#f2e8d5;font-family:monospace;text-align:center;padding:40px">' +
    '<script>location.replace(' + JSON.stringify(destino) + ')</script>' +
    '<p>Redirecionando para o pedido… <a href="' + esc(destino) + '" style="color:#8fc45a">clique aqui</a></p></body></html>';

  res.setHeader('Content-Type','text/html; charset=utf-8');
  res.setHeader('Cache-Control','s-maxage=120, stale-while-revalidate=300');
  res.status(200).send(html);
};