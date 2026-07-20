-- =====================================================================
-- PokeCentral — B1 Passo 2: dados do vendedor da comunidade no anúncio.
-- Preenchidos quando o jogador postar (Passo 3). Usados no card da aba
-- "Jogadores" pra mostrar quem vende e como falar com ele.
-- =====================================================================

alter table pokemons add column if not exists vendedor_nome    text;
alter table pokemons add column if not exists vendedor_contato text;
