-- =====================================================================
-- PokeCentral — coluna do "Compre já" (arremate instantâneo) nos lotes.
-- Rode no Supabase → SQL Editor ANTES de criar novos lotes.
-- Sem isto, abrir leilão dá erro "column preco_ja does not exist".
--
-- Não precisa de política de RLS nova: as políticas de "lotes" já cobrem
-- a coluna (select público, insert/delete só do dono).
-- =====================================================================

alter table lotes add column if not exists preco_ja numeric;
