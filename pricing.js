/* =====================================================================
   pricing.js — modelo conservador de preço do PokeCentral.
   Compartilhado por preco.html, loja.html e leilao.html.
   O custo/RNG de captura NÃO define o preço do exemplar.
   ===================================================================== */
(function(global){
  var CFG = {
    VERSION:       2,
    BREAKPOINT_IV: 150,
    BASE_IV:       120,
    BASE_PRICE:    12,
    IV_RATE:       0.018,
    IV_TAIL_RATE:  0.027,
    QUAL_BASE:     1.75,
    QUAL_PESO:     3,
    SHINY_MULT:    1.6,
    SHINY_PREMIUM: 15,
    LEVEL_SCALE:   10,
    LEVEL_REF:     350,
    LEVEL_EXP:     1.7,
    LEVEL_CAP:     12
  };

  function num(v,d){ v=parseFloat(v); return isFinite(v)?v:d; }
  function clamp(v,a,b){ return Math.max(a,Math.min(b,v)); }
  function normName(v){ return String(v||'').trim().toLowerCase().replace(/^(brave|furious|enraged|ancient|tribal|war|enigmatic|charged|magnetic|evil|freezing|psy|heavy|roll|hard|brute|dark|trickmaster|banshee|taekwondo)\\s+/,'').replace(/^milch-/,''); }

  function ivFactor(iv){
    iv=clamp(num(iv,CFG.BASE_IV),0,192);
    if(iv<=CFG.BREAKPOINT_IV) return Math.exp((iv-CFG.BASE_IV)*CFG.IV_RATE);
    var ate=Math.exp((CFG.BREAKPOINT_IV-CFG.BASE_IV)*CFG.IV_RATE);
    return ate*Math.exp((iv-CFG.BREAKPOINT_IV)*CFG.IV_TAIL_RATE);
  }
  function qualityFactor(q,base,peso){
    q=Math.max(num(q,CFG.QUAL_BASE),0.1);
    base=Math.max(num(base,CFG.QUAL_BASE),0.1);
    return Math.pow(q/base,num(peso,CFG.QUAL_PESO));
  }
  function levelBonus(level){
    level=Math.max(num(level,1),1);
    var bonus=CFG.LEVEL_SCALE*Math.pow(Math.max(level-1,0)/CFG.LEVEL_REF,CFG.LEVEL_EXP);
    return Math.min(bonus,CFG.LEVEL_CAP);
  }

  function speciesInfo(name){
    var n=normName(name), list=global.PokeSpecies||[];
    for(var i=0;i<list.length;i++) if(normName(list[i].name)===n)return list[i];
    return null;
  }
  function speciesFactor(name,shiny){
    var sp=speciesInfo(name); if(!sp)return 1;
    var bst=shiny?num(sp.bst,500):num(sp.finalBst||sp.bst,500);
    var forca=clamp(Math.pow(bst/500,0.55),0.88,1.18);
    var custo=num(sp.priceNpc,0);
    var economia=custo>0?clamp(Math.pow(custo/18000,0.18),0.70,1.30):1;
    var raridade={COMMON:1,UNCOMMON:1.03,RARE:1.07,EPIC:1.15,LEGENDARY:1.30}[String(sp.rarity||'').toUpperCase()]||1;
    return clamp(forca*economia*raridade,0.65,1.60);
  }
  function model(p){
    p=p||{};
    var demand=clamp(num(p.demand,1),0.5,2);
    var shiny=p.shiny?num(p.shinyMult,CFG.SHINY_MULT):1;
    var especie=num(p.speciesFactor,speciesFactor(p.name,p.shiny));
    var shinyPremium=p.shiny?num(p.shinyPremium,CFG.SHINY_PREMIUM):0;
    return CFG.BASE_PRICE*ivFactor(p.iv)*qualityFactor(p.qual,p.qualBase,p.qualPeso)*demand*shiny*especie+shinyPremium+levelBonus(p.level);
  }

  function refValue(r){ return num(r.preco_vendido,0)>0?num(r.preco_vendido,0):num(r.preco_pedido,0); }
  function weightedMedian(items){
    items.sort(function(a,b){return a.v-b.v;});
    var total=items.reduce(function(s,x){return s+x.w;},0),acc=0;
    for(var i=0;i<items.length;i++){ acc+=items[i].w; if(acc>=total/2)return items[i].v; }
    return items.length?items[items.length-1].v:null;
  }
  function comparable(p,refs){
    refs=Array.isArray(refs)?refs:[];
    var alvoNome=normName(p.name), alvoShiny=!!p.shiny, alvoModel=model(p), itens=[];
    refs.forEach(function(r){
      var valor=refValue(r); if(!(valor>0) || !!r.shiny!==alvoShiny)return;
      var mesmo=alvoNome && normName(r.pokemon_nome)===alvoNome;
      var venda=num(r.preco_vendido,0)>0;
      var refModel=model({name:r.pokemon_nome,iv:r.iv,qual:r.qualidade,level:r.nivel,shiny:r.shiny,demand:1});
      var razao=clamp(alvoModel/Math.max(refModel,1),0.5,2);
      var conf={alta:1.35,media:1,baixa:.7,muito_baixa:.4}[r.confianca]||.7;
      var peso=(venda?3:1)*(mesmo?2.5:1)*conf;
      itens.push({v:valor*razao,w:peso,mesmo:mesmo,venda:venda});
    });
    if(!itens.length)return null;
    var mesmas=itens.filter(function(x){return x.mesmo;});
    var usadas=mesmas.length?mesmas:itens;
    var med=weightedMedian(usadas);
    var vendas=usadas.filter(function(x){return x.venda;}).length;
    var blend=mesmas.length?(vendas?(mesmas.length>=2?0.65:0.5):(mesmas.length>=2?0.4:0.25)):(vendas>=2?0.35:0.2);
    return {value:med,count:usadas.length,sales:vendas,sameSpecies:mesmas.length,blend:blend};
  }

  function fair(p,refs){
    var base=model(p), comp=comparable(p,refs);
    return comp?base*(1-comp.blend)+comp.value*comp.blend:base;
  }
  function prices(p,refs){
    var m=model(p),comp=comparable(p,refs),f=comp?m*(1-comp.blend)+comp.value*comp.blend:m;
    var confidence=!comp?'baixa':(comp.sameSpecies>=2&&comp.sales>=1?'alta':(comp.sales>=1||comp.count>=3?'média':'baixa'));
    return {fast:f*.85,fair:f,flex:f*1.15,model:m,market:comp,confidence:confidence};
  }
  function sugerirIncremento(v){ if(v<=30)return 2;if(v<=100)return 5;return 10; }
  function auction(p,refs){
    var pr=prices(p,refs);
    return {fast:pr.fast,fair:pr.fair,flex:pr.flex,inicial:pr.fair*.6,incremento:sugerirIncremento(pr.fair),arremate:pr.flex,confidence:pr.confidence};
  }

  global.PokePrice={CFG:CFG,speciesInfo:speciesInfo,speciesFactor:speciesFactor,model:model,fair:fair,prices:prices,auction:auction,sugerirIncremento:sugerirIncremento,comparable:comparable};
})(window);