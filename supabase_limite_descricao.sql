-- =====================================================================
-- PokeCentral — limita a descrição dos anúncios a 160 caracteres.
-- Rode no Supabase → SQL Editor.
--
-- NOT VALID preserva anúncios antigos que eventualmente já tenham textos
-- maiores, mas o limite passa a valer imediatamente para novos anúncios e
-- para anúncios editados.
-- =====================================================================

alter table pokemons
  drop constraint if exists pokemons_obs_max_160;

alter table pokemons
  add constraint pokemons_obs_max_160
  check (obs is null or char_length(obs) <= 160)
  not valid;
