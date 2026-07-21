-- PokeCentral — valor fixo ou aberto a propostas.
-- Rode uma vez no SQL Editor do Supabase.

alter table pokemons
  add column if not exists aceita_oferta boolean not null default false;

comment on column pokemons.aceita_oferta is
  'true = vendedor aceita propostas; false = valor anunciado é fixo';
