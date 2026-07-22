-- =====================================================================
-- PokeCentral — PEDIDOS (MVP)
-- Rode no Supabase -> SQL Editor depois de B1, B2 e B3.
-- 2 pedidos ativos por jogador. Todo pedido válido é aprovado automaticamente.
-- =====================================================================

create table if not exists pedidos (
  id                bigint generated always as identity primary key,
  user_id           uuid not null references auth.users(id) on delete cascade,
  comprador_nome    text not null,
  comprador_contato text not null,
  pokemon_nome      text not null,
  poke_id           int,
  iv_min            int check (iv_min is null or iv_min between 0 and 192),
  qualidade_min     numeric,
  nivel_min         int check (nivel_min is null or nivel_min >= 1),
  shiny             text not null default 'opcional' check (shiny in ('nao','opcional','obrigatorio')),
  preco_min         numeric check (preco_min is null or preco_min >= 0),
  preco_max         numeric not null check (preco_max > 0 and preco_max <= 100000),
  obs               text,
  status            text not null default 'pendente' check (status in ('pendente','aprovado','rejeitado')),
  motivo_rejeicao   text,
  ativo             boolean not null default true,
  criado_em         timestamptz not null default now(),
  expira_em         timestamptz not null default (now() + interval '7 days')
);

alter table pedidos enable row level security;

create or replace function pedidos_ativos(uid uuid) returns int
  language sql security definer stable as $$
  select count(*)::int from pedidos
   where user_id = uid
     and ativo = true
     and status in ('pendente','aprovado')
     and expira_em > now();
$$;

create or replace function limite_pedidos(uid uuid) returns int
  language sql security definer stable as $$
  select 2;
$$;

-- Checagem rápida: o que passar entra no ar imediatamente; o que falhar é bloqueado.
create or replace function pedido_ok(
  p_nome text, p_iv int, p_qual numeric, p_nivel int, p_shiny text,
  p_min numeric, p_max numeric, p_obs text, p_contato text
) returns boolean language sql immutable as $$
  select p_nome is not null and length(btrim(p_nome)) between 2 and 40
     and (p_iv is null or p_iv between 0 and 192)
     and (p_qual is null or p_qual between 0.8 and 10)
     and (p_nivel is null or p_nivel between 1 and 9999)
     and p_shiny in ('nao','opcional','obrigatorio')
     and p_max is not null and p_max > 0 and p_max <= 100000
     and (p_min is null or (p_min >= 0 and p_min <= p_max))
     and (p_obs is null or length(p_obs) <= 160)
     and p_contato is not null
     and (p_contato like 'dc:%' or p_contato like 'wa:%')
     and length(btrim(p_contato)) >= 5;
$$;

create or replace function pedidos_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    new.user_id := auth.uid();
    if new.comprador_nome is null or length(btrim(new.comprador_nome)) < 2
       or not pedido_ok(new.pokemon_nome,new.iv_min,new.qualidade_min,new.nivel_min,new.shiny,
                        new.preco_min,new.preco_max,new.obs,new.comprador_contato) then
      raise exception 'Pedido inválido: confira Pokémon, requisitos, orçamento e contato.';
    end if;
    new.status := 'aprovado';
    new.ativo := true;
    new.motivo_rejeicao := null;
    new.expira_em := now() + interval '7 days';
    return new;
  end if;

  if auth.uid() is null or is_admin() then return new; end if;
  new.user_id := old.user_id;
  new.comprador_nome := old.comprador_nome;
  new.criado_em := old.criado_em;
  new.expira_em := old.expira_em;

  if (new.pokemon_nome,new.poke_id,new.iv_min,new.qualidade_min,new.nivel_min,new.shiny,
      new.preco_min,new.preco_max,new.obs,new.comprador_contato)
     is distinct from
     (old.pokemon_nome,old.poke_id,old.iv_min,old.qualidade_min,old.nivel_min,old.shiny,
      old.preco_min,old.preco_max,old.obs,old.comprador_contato)
  then
    if new.comprador_nome is null or length(btrim(new.comprador_nome)) < 2
       or not pedido_ok(new.pokemon_nome,new.iv_min,new.qualidade_min,new.nivel_min,new.shiny,
                        new.preco_min,new.preco_max,new.obs,new.comprador_contato) then
      raise exception 'Pedido inválido: confira Pokémon, requisitos, orçamento e contato.';
    end if;
    new.status := 'aprovado';
    new.motivo_rejeicao := null;
  else
    new.status := old.status;
    new.motivo_rejeicao := old.motivo_rejeicao;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_pedidos_guard on pedidos;
create trigger trg_pedidos_guard before insert or update on pedidos
  for each row execute function pedidos_guard();
-- Se a versão anterior já foi executada, publica os pedidos pendentes que passam na checagem.
update pedidos
   set status = 'aprovado', motivo_rejeicao = null
 where status = 'pendente'
   and pedido_ok(pokemon_nome,iv_min,qualidade_min,nivel_min,shiny,
                 preco_min,preco_max,obs,comprador_contato);

drop policy if exists "pedidos_select" on pedidos;
drop policy if exists "pedidos_insert" on pedidos;
drop policy if exists "pedidos_update" on pedidos;
drop policy if exists "pedidos_delete" on pedidos;

create policy "pedidos_select" on pedidos for select using (
  (status = 'aprovado' and ativo = true and expira_em > now())
  or user_id = auth.uid()
  or is_admin()
);

create policy "pedidos_insert" on pedidos for insert with check (
  auth.uid() is not null
  and user_id = auth.uid()
  and not esta_banido(auth.uid())
  and pedidos_ativos(auth.uid()) < limite_pedidos(auth.uid())
);

create policy "pedidos_update" on pedidos for update using (user_id = auth.uid() or is_admin());
create policy "pedidos_delete" on pedidos for delete using (user_id = auth.uid() or is_admin());

create index if not exists idx_pedidos_publicos on pedidos(status,ativo,expira_em desc);
create index if not exists idx_pedidos_usuario on pedidos(user_id,criado_em desc);
create index if not exists idx_pedidos_pokemon on pedidos(lower(pokemon_nome));

-- Teste rapido, logado com uma conta de jogador:
-- await sb.from('pedidos').insert({
--   user_id:(await sb.auth.getUser()).data.user.id,
--   comprador_nome:'teste', comprador_contato:'dc:SEU_ID', pokemon_nome:'Gengar',
--   iv_min:150, qualidade_min:1.78, shiny:'opcional', preco_max:30
-- }).select()
-- Todo pedido válido cria como aprovado e aparece imediatamente.
-- O terceiro pedido ativo deve ser bloqueado.
-- =====================================================================
