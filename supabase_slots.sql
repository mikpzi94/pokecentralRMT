-- =====================================================================
-- PokeCentral — limite de anúncios: 3 grátis, 5 pra vendedor Confiável.
-- Rode DEPOIS de B1, B2 e B3 (usa slots_ativos, esta_banido e eh_confiavel).
-- =====================================================================

create or replace function limite_slots(uid uuid) returns int
  language sql security definer stable as $$
  select case when eh_confiavel(uid) then 5 else 3 end;   -- confiável ganha mais espaço
$$;

-- atualiza a policy de insert pra usar o limite dinâmico
drop policy if exists "pokemons_insert" on pokemons;
create policy "pokemons_insert" on pokemons for insert with check (
  is_admin() or (
    auth.uid() is not null
    and user_id = auth.uid()
    and slots_ativos(auth.uid()) < limite_slots(auth.uid())
    and not esta_banido(auth.uid())
  )
);
