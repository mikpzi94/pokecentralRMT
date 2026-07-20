-- =====================================================================
-- PokeCentral — leilão de streamers + modo ao vivo (Fases 1 e 2).
-- Rode no Supabase → SQL Editor ANTES de usar os recursos novos.
-- =====================================================================

-- Fase 1: de quem é o lote (streamer/vendedor)
alter table lotes add column if not exists vendedor text;

-- Fase 2: anti-sniping por lote (em segundos) — pra leilão ao vivo curto.
--         vazio/null = usa o padrão global (5 min).
alter table lotes add column if not exists extensao_seg int;

-- Fase 2: marca qual lote está "ao vivo" (a tela de OBS mostra esse).
alter table lotes add column if not exists ao_vivo boolean default false;

-- =====================================================================
-- IMPORTANTE — LANCES EM TEMPO REAL:
-- Ative o Realtime nas tabelas 'lances' e 'lotes' pra os lances
-- aparecerem na hora (na página e na tela de OBS):
--   Supabase → Database → Replication → supabase_realtime
--   → adicione as tabelas 'lances' e 'lotes'.
-- (Sem isso, ainda funciona, mas atualiza a cada 15s em vez de instantâneo.)
-- =====================================================================
