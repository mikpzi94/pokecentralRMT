-- =====================================================================
-- PokeCentral — B1: fundação do marketplace multi-vendedor.
-- Rode no Supabase → SQL Editor. Substitui o RLS single-owner antigo
-- da tabela pokemons por um RLS multi-tenant com moderação.
--
-- SEGURO: seus anúncios atuais viram 'aprovado' + atribuídos a você.
-- O RLS já força jogador = 'pendente' mesmo antes do código novo da loja.
-- =====================================================================

-- ---------- 1. Colunas novas em pokemons ----------
alter table pokemons add column if not exists user_id uuid references auth.users(id);
alter table pokemons add column if not exists status text not null default 'pendente';
alter table pokemons add column if not exists motivo_rejeicao text;

-- migra o que já existe (seus anúncios) → oficial + aprovado
update pokemons
   set status = 'aprovado',
       user_id = coalesce(user_id, 'd3607434-85a0-46eb-8a17-16dd3d0b247a')
 where status is null or status = 'pendente' or user_id is null;

-- ---------- 2. Tabela de admins (quem modera) ----------
create table if not exists admins ( user_id uuid primary key references auth.users(id) on delete cascade );
insert into admins (user_id) values ('d3607434-85a0-46eb-8a17-16dd3d0b247a') on conflict do nothing;

alter table admins enable row level security;   -- ninguém lê pela API; só as funções SECURITY DEFINER abaixo

-- ---------- 3. Funções auxiliares ----------
create or replace function is_admin() returns boolean
  language sql security definer stable as $$
  select exists(select 1 from admins where user_id = auth.uid());
$$;

-- conta anúncios ATIVOS do vendedor (vendido = disponivel=false NÃO conta)
create or replace function slots_ativos(uid uuid) returns int
  language sql security definer stable as $$
  select count(*)::int from pokemons
   where user_id = uid and status in ('pendente','aprovado') and disponivel is not false;
$$;

-- ---------- 4. Trigger de proteção (o cérebro) ----------
create or replace function pokemons_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    if is_admin() then
      if new.user_id is null then new.user_id := auth.uid(); end if;
      if new.status is null or new.status = 'pendente' then new.status := 'aprovado'; end if;  -- dono posta = oficial aprovado
    else
      new.user_id := auth.uid();     -- jogador não escolhe dono
      new.status  := 'pendente';     -- jogador sempre entra na fila
    end if;
    return new;
  end if;

  -- UPDATE
  if is_admin() then return new; end if;              -- admin aprova/edita à vontade
  new.user_id := old.user_id;                          -- não pode roubar anúncio
  if (new.nome, new.qualidade, new.iv, new.nivel, new.preco, new.print, new.poke_id, new.obs)
     is distinct from
     (old.nome, old.qualidade, old.iv, old.nivel, old.preco, old.print, old.poke_id, old.obs)
  then
    new.status := 'pendente';   -- editou conteúdo → volta pra moderação
  else
    new.status := old.status;   -- só togglou vendido/etc → mantém
  end if;
  return new;
end;
$$;

drop trigger if exists trg_pokemons_guard on pokemons;
create trigger trg_pokemons_guard before insert or update on pokemons
  for each row execute function pokemons_guard();

-- ---------- 5. RLS multi-tenant (troca o single-owner antigo) ----------
alter table pokemons enable row level security;

drop policy if exists "pokemons_select_publico" on pokemons;
drop policy if exists "pokemons_dono_insert"    on pokemons;
drop policy if exists "pokemons_dono_update"    on pokemons;
drop policy if exists "pokemons_dono_delete"    on pokemons;
drop policy if exists "pokemons_select"         on pokemons;
drop policy if exists "pokemons_insert"         on pokemons;
drop policy if exists "pokemons_update"         on pokemons;
drop policy if exists "pokemons_delete"         on pokemons;

-- ver: público só aprovado; vendedor vê os próprios; admin vê tudo
create policy "pokemons_select" on pokemons for select using (
  status = 'aprovado' or user_id = auth.uid() or is_admin()
);

-- criar: logado, como próprio, e (se não-admin) dentro do limite de 5 slots
create policy "pokemons_insert" on pokemons for insert with check (
  is_admin() or (
    auth.uid() is not null
    and user_id = auth.uid()
    and slots_ativos(auth.uid()) < 5
  )
);

-- editar / apagar: dono ou admin (o trigger cuida de status/dono)
create policy "pokemons_update" on pokemons for update using ( user_id = auth.uid() or is_admin() );
create policy "pokemons_delete" on pokemons for delete using ( user_id = auth.uid() or is_admin() );

-- ---------- 6. Índices (pra escalar) ----------
create index if not exists idx_pokemons_status  on pokemons(status);
create index if not exists idx_pokemons_user    on pokemons(user_id);
create index if not exists idx_pokemons_criado  on pokemons(criado_em desc);

-- =====================================================================
-- TESTE DE FOGO (console do navegador)
--
-- Logado com conta Discord de TESTE (não a dona):
--   await sb.from('pokemons').insert({nome:'teste', preco:10})       // vira 'pendente' (não aparece pro público)
--   (await sb.from('pokemons').select('*')).data                      // vê os próprios + os aprovados
--   // inserir 6x seguidas → a 6ª deve FALHAR (limite de 5 slots)
--   await sb.from('pokemons').update({status:'aprovado'}).eq('id', SEU_ID_PENDENTE)  // trigger devolve pra 'pendente' (não auto-aprova)
--
-- Deslogado (anônimo):
--   (await sb.from('pokemons').select('*')).data                      // só os 'aprovado'
--
-- Logado como DONO (email/senha):
--   await sb.from('pokemons').update({status:'aprovado'}).eq('id', UM_PENDENTE)  // aprova de verdade
-- =====================================================================
