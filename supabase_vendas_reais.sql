-- =====================================================================
-- PokeCentral — referências de mercado e vendas reais.
-- Rode depois de B1/B2/B3.
-- =====================================================================
alter table pokemons add column if not exists shiny boolean not null default false;

create table if not exists vendas_reais (
  id bigint generated always as identity primary key,
  anuncio_id text,
  autor_id uuid references auth.users(id) on delete set null,
  autor_nome text,
  pokemon_nome text not null,
  poke_id int,
  iv int check (iv is null or iv between 0 and 192),
  qualidade numeric(6,3) check (qualidade is null or qualidade between 0.1 and 10),
  nivel int check (nivel is null or nivel >= 1),
  shiny boolean not null default false,
  preco_pedido numeric(10,2) check (preco_pedido is null or preco_pedido > 0),
  preco_vendido numeric(10,2) check (preco_vendido is null or preco_vendido > 0),
  preco_diamantes numeric(10,2) check (preco_diamantes is null or preco_diamantes > 0),
  tipo text not null default 'venda' check (tipo in ('anuncio','venda')),
  origem text not null default 'externa' check (origem in ('pokecentral','whatsapp','discord','externa')),
  confianca text not null default 'baixa' check (confianca in ('muito_baixa','baixa','media','alta')),
  status text not null default 'pendente' check (status in ('pendente','aprovado','rejeitado')),
  observacao text,
  data_referencia date not null default current_date,
  criado_em timestamptz not null default now()
);
create unique index if not exists idx_venda_unica_anuncio on vendas_reais(anuncio_id) where anuncio_id is not null and tipo='venda';
create index if not exists idx_vendas_status_data on vendas_reais(status,data_referencia desc);
create index if not exists idx_vendas_pokemon on vendas_reais(lower(pokemon_nome));

alter table vendas_reais enable row level security;
drop policy if exists "vendas_select" on vendas_reais;
drop policy if exists "vendas_insert" on vendas_reais;
drop policy if exists "vendas_update" on vendas_reais;
drop policy if exists "vendas_delete" on vendas_reais;
create policy "vendas_select" on vendas_reais for select using (autor_id=auth.uid() or is_admin());
create policy "vendas_insert" on vendas_reais for insert with check (auth.uid() is not null and autor_id=auth.uid());
create policy "vendas_update" on vendas_reais for update using (is_admin() or (autor_id=auth.uid() and status='pendente'));
create policy "vendas_delete" on vendas_reais for delete using (is_admin() or (autor_id=auth.uid() and status='pendente'));

create or replace function vendas_guard() returns trigger language plpgsql as $$
begin
  if is_admin() then return new; end if;
  if tg_op='INSERT' then
    new.autor_id:=auth.uid(); new.status:='pendente';
    new.confianca:=case when new.origem='pokecentral' then 'media' else 'baixa' end;
  else
    new.autor_id:=old.autor_id; new.status:=old.status; new.confianca:=old.confianca;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_vendas_guard on vendas_reais;
create trigger trg_vendas_guard before insert or update on vendas_reais for each row execute function vendas_guard();

create or replace function marcar_pokemon_vendido(p_anuncio_id text,p_preco_final numeric)
returns void language plpgsql security definer set search_path=public as $$
declare p pokemons%rowtype;
begin
  select * into p from pokemons where id::text=p_anuncio_id for update;
  if not found then raise exception 'anúncio não encontrado'; end if;
  if not (is_admin() or p.user_id=auth.uid()) then raise exception 'sem permissão'; end if;
  update pokemons set disponivel=false where id=p.id;
  if p_preco_final is not null and p_preco_final>0 then
    insert into vendas_reais(anuncio_id,autor_id,autor_nome,pokemon_nome,poke_id,iv,qualidade,nivel,shiny,preco_pedido,preco_vendido,tipo,origem,confianca,status)
    values(p.id::text,auth.uid(),coalesce(p.vendedor_nome,'PokeCentral'),p.nome,p.poke_id,p.iv,
      nullif(replace(p.qualidade::text,',','.'),'')::numeric,p.nivel,coalesce(p.shiny,false),p.preco,p_preco_final,
      'venda','pokecentral','media',case when is_admin() then 'aprovado' else 'pendente' end)
    on conflict(anuncio_id) where anuncio_id is not null and tipo='venda'
    do update set preco_vendido=excluded.preco_vendido,data_referencia=current_date,
      status=case when is_admin() then 'aprovado' else 'pendente' end;
  end if;
end;
$$;
grant execute on function marcar_pokemon_vendido(text,numeric) to authenticated;

create or replace function referencias_mercado_aprovadas()
returns table(pokemon_nome text,poke_id int,iv int,qualidade numeric,nivel int,shiny boolean,preco_pedido numeric,preco_vendido numeric,tipo text,origem text,confianca text,data_referencia date)
language sql security definer stable set search_path=public as $$
  select pokemon_nome,poke_id,iv,qualidade,nivel,shiny,preco_pedido,preco_vendido,tipo,origem,confianca,data_referencia
  from vendas_reais where status='aprovado';
$$;
grant execute on function referencias_mercado_aprovadas() to anon,authenticated;
