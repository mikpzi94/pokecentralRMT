-- =====================================================================
-- PokeCentral — Políticas de RLS (Row Level Security)
-- Dono do site (UID): d3607434-85a0-46eb-8a17-16dd3d0b247a
--
-- Rode no Supabase → SQL Editor. Aplica de uma vez.
-- Se já existirem políticas com estes nomes, o "drop policy if exists"
-- abaixo evita erro de duplicado.
-- =====================================================================

-- ---------------------------------------------------------------------
-- PASSO 1 — Ligar RLS (sem isto, política nenhuma vale e tudo fica aberto)
-- ---------------------------------------------------------------------
alter table pokemons enable row level security;
alter table lotes    enable row level security;
alter table lances   enable row level security;

-- ---------------------------------------------------------------------
-- PASSO 2 — POKEMONS: todo mundo vê (é a loja); só o DONO mexe
-- ---------------------------------------------------------------------
drop policy if exists "pokemons_select_publico" on pokemons;
drop policy if exists "pokemons_dono_insert"    on pokemons;
drop policy if exists "pokemons_dono_update"    on pokemons;
drop policy if exists "pokemons_dono_delete"    on pokemons;

create policy "pokemons_select_publico" on pokemons
  for select using (true);
create policy "pokemons_dono_insert" on pokemons
  for insert with check (auth.uid() = 'd3607434-85a0-46eb-8a17-16dd3d0b247a');
create policy "pokemons_dono_update" on pokemons
  for update using (auth.uid() = 'd3607434-85a0-46eb-8a17-16dd3d0b247a');
create policy "pokemons_dono_delete" on pokemons
  for delete using (auth.uid() = 'd3607434-85a0-46eb-8a17-16dd3d0b247a');

-- ---------------------------------------------------------------------
-- PASSO 3 — LOTES: todo mundo vê; só o DONO cria/apaga
-- ---------------------------------------------------------------------
drop policy if exists "lotes_select_publico" on lotes;
drop policy if exists "lotes_dono_insert"    on lotes;
drop policy if exists "lotes_dono_delete"    on lotes;

create policy "lotes_select_publico" on lotes
  for select using (true);
create policy "lotes_dono_insert" on lotes
  for insert with check (auth.uid() = 'd3607434-85a0-46eb-8a17-16dd3d0b247a');
create policy "lotes_dono_delete" on lotes
  for delete using (auth.uid() = 'd3607434-85a0-46eb-8a17-16dd3d0b247a');

-- ---------------------------------------------------------------------
-- PASSO 4 — LANCES: todo mundo vê; qualquer logado (Discord) dá lance;
--           NINGUÉM edita/apaga (imutabilidade que a página promete).
--           Ausência de política de update/delete = update/delete BLOQUEADOS.
-- ---------------------------------------------------------------------
drop policy if exists "lances_select_publico" on lances;
drop policy if exists "lances_insert_logado"  on lances;

create policy "lances_select_publico" on lances
  for select using (true);
create policy "lances_insert_logado" on lances
  for insert with check (auth.role() = 'authenticated');

-- ---------------------------------------------------------------------
-- PASSO 5 — Storage (bucket "prints"): leitura pública, upload só do dono
-- ---------------------------------------------------------------------
drop policy if exists "prints_leitura_publica" on storage.objects;
drop policy if exists "prints_upload_dono"     on storage.objects;

create policy "prints_leitura_publica" on storage.objects
  for select using (bucket_id = 'prints');
create policy "prints_upload_dono" on storage.objects
  for insert with check (
    bucket_id = 'prints'
    and auth.uid() = 'd3607434-85a0-46eb-8a17-16dd3d0b247a'
  );

-- =====================================================================
-- TESTE DE FOGO (rode no console do navegador, logado como conta Discord
-- de teste — NÃO a dona — na página do leilão):
--
--   await sb.from('lances').delete().eq('id', 1)              // deve FALHAR/0 linhas
--   await sb.from('pokemons').insert({ nome:'teste' })         // deve FALHAR
--   await sb.from('lances').insert({ lote_id:1, valor:999, nome_discord:'teste' })  // deve FUNCIONAR
--
-- Se delete/insert-pokemon derem erro e o lance passar → RLS OK.
-- =====================================================================
