/* =====================================================================
   pricing.js — fonte ÚNICA da curva de preço do PokeCentral.
   Usado por preco.html (calculadora) e leilao.html (sugestão de lote).
   Mudou a curva? Muda aqui, e as duas páginas atualizam juntas.
   ===================================================================== */
(function(global){

  /* Constantes de calibração. Ajuste aqui pra recalibrar tudo. */
  var CFG = {
    BREAKPOINT_IV: 150,   /* acima disso a curva desacelera            */
    ANCHOR_PRICE:  3,     /* preço observado no IV 100 (R$)            */
    ANCHOR_RATIO:  8/3,   /* multiplica a cada 20 pts de IV até o breakpoint (IV120 ≈ R$8) */
    ANCHOR_STEP:   20,
    QUAL_BASE:     1.75,  /* qualidade que os preços de referência assumem */
    QUAL_PESO:     1,     /* expoente da qualidade (força do efeito)   */
    SHINY_MULT:    2.5,   /* prêmio de shiny — chute, sem âncora       */
    TAIL_GROWTH:   15,    /* %/10pts acima do breakpoint               */
    LEVEL_PER_TEN: 0.5    /* R$ por 10 níveis                          */
  };

  function num(v, d){ v = parseFloat(v); return isFinite(v) ? v : d; }

  /* preço-base só pelo IV (sem qualidade/shiny/demanda) */
  function basePrice(iv, tailGrowthPct){
    var bp = CFG.BREAKPOINT_IV;
    var priceAtBp = CFG.ANCHOR_PRICE * Math.pow(CFG.ANCHOR_RATIO, (bp-100)/CFG.ANCHOR_STEP);
    if(iv <= bp) return CFG.ANCHOR_PRICE * Math.pow(CFG.ANCHOR_RATIO, (iv-100)/CFG.ANCHOR_STEP);
    return priceAtBp * Math.pow(1 + num(tailGrowthPct, CFG.TAIL_GROWTH)/100, (iv-bp)/10);
  }

  /* preço "justo".  p = {iv, qual, level, demand, shiny, + overrides opcionais} */
  function fair(p){
    p = p || {};
    var iv        = num(p.iv, 0);
    var qual      = num(p.qual, CFG.QUAL_BASE);
    var level     = Math.max(num(p.level, 1), 1);
    var demand    = num(p.demand, 1);
    var tail      = num(p.tail, CFG.TAIL_GROWTH);
    var perTen    = num(p.levelPerTen, CFG.LEVEL_PER_TEN);
    var qualBase  = num(p.qualBase, CFG.QUAL_BASE);
    var qualPeso  = num(p.qualPeso, CFG.QUAL_PESO);
    var shinyMult = num(p.shinyMult, CFG.SHINY_MULT);

    var shinyFactor = p.shiny ? shinyMult : 1;
    var qualFactor  = qualBase > 0 ? Math.pow(Math.max(qual, 0.01)/qualBase, qualPeso) : 1;
    var levelBonus  = (level/10) * perTen;

    return basePrice(iv, tail) * demand * qualFactor * shinyFactor + levelBonus;
  }

  /* 3 preços de venda (rápida / referência / flex) */
  function prices(p){
    var f = fair(p);
    return { fast: f*0.8, fair: f, flex: f*1.25 };
  }

  /* incremento sugerido pela faixa de valor do lote */
  function sugerirIncremento(fairV){
    if(fairV <= 30)  return 2;
    if(fairV <= 100) return 5;
    return 10;
  }

  /* sugestão completa pra abrir um leilão a partir das infos do Pokémon.
     Modelo de 2 números: começa no piso real (venda rápida) e sobe até o compre já. */
  function auction(p){
    var pr = prices(p);
    return {
      fast:       pr.fast,
      fair:       pr.fair,
      flex:       pr.flex,
      inicial:    pr.fair * 0.6,            /* chamariz: abre em 60% do justo pra atrair o 1º lance */
      incremento: sugerirIncremento(pr.fair),
      arremate:   pr.flex                   /* "compre já" ~= flex        */
    };
  }

  global.PokePrice = {
    CFG: CFG,
    basePrice: basePrice,
    fair: fair,
    prices: prices,
    auction: auction,
    sugerirIncremento: sugerirIncremento
  };

})(window);
