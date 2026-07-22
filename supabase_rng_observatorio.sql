-- =====================================================================
-- PokeCentral — Observatório comunitário de RNG.
-- Rode no Supabase SQL Editor depois dos arquivos B1/B2 (usa is_admin()).
-- Os registros são relatos da comunidade, não dados oficiais.
-- =====================================================================

create table if not exists capturas_rng (
  id                  bigint generated always as identity primary key,
  user_id             uuid not null references auth.users(id) on delete cascade,
  autor_nome          text not null,
  pokemon_nome        text not null,
  variante            text not null default 'normal',
  ball                text not null,
  custo_ball          numeric check (custo_ball is null or (custo_ball > 0 and custo_ball <= 1000000)),
  valor_alvo          numeric not null check (valor_alvo > 0 and valor_alvo <= 1000000000),
  tentativas          int not null check (tentativas between 1 and 100000),
  buff_profissao      numeric not null default 0 check (buff_profissao between 0 and 100),
  boost_multiplicador numeric not null default 1 check (boost_multiplicador between 0.01 and 100),
  resultado           text not null check (resultado in ('capturou','desistiu')),
  data_captura        date not null default current_date,
  observacao          text,
  status              text not null default 'aprovado' check (status in ('aprovado','removido')),
  criado_em           timestamptz not null default now()
);

alter table capturas_rng enable row level security;

create index if not exists idx_rng_status_data on capturas_rng(status, criado_em desc);
create index if not exists idx_rng_pokemon on capturas_rng(lower(pokemon_nome));
create index if not exists idx_rng_user_data on capturas_rng(user_id, criado_em desc);

create or replace function rng_envios_24h(uid uuid) returns int
  language sql security definer stable set search_path = public as $$
  select count(*)::int
    from capturas_rng
   where user_id = uid and criado_em >= now() - interval '24 hours';
$$;

create or replace function capturas_rng_guard() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  new.user_id := auth.uid();
  new.status := 'aprovado';
  new.autor_nome := left(btrim(new.autor_nome), 60);
  new.pokemon_nome := left(btrim(new.pokemon_nome), 60);
  new.variante := left(lower(btrim(new.variante)), 30);
  new.ball := left(lower(btrim(new.ball)), 40);
  new.observacao := nullif(left(btrim(coalesce(new.observacao,'')), 160), '');
  return new;
end;
$$;

drop trigger if exists trg_capturas_rng_guard on capturas_rng;
create trigger trg_capturas_rng_guard
  before insert on capturas_rng
  for each row execute function capturas_rng_guard();

drop policy if exists "rng_select_publico" on capturas_rng;
drop policy if exists "rng_insert_logado" on capturas_rng;
drop policy if exists "rng_delete_proprio_admin" on capturas_rng;

create policy "rng_select_publico" on capturas_rng
  for select using (status = 'aprovado' or user_id = auth.uid() or is_admin());

create policy "rng_insert_logado" on capturas_rng
  for insert with check (
    auth.uid() is not null
    and user_id = auth.uid()
    and rng_envios_24h(auth.uid()) < 20
  );

create policy "rng_delete_proprio_admin" on capturas_rng
  for delete using (user_id = auth.uid() or is_admin());

-- Teste rápido, logado com Discord no navegador:
-- await sb.from('capturas_rng').insert({
--   user_id:(await sb.auth.getUser()).data.user.id,
--   autor_nome:'teste', pokemon_nome:'Gengar', variante:'normal',
--   ball:'ultra', custo_ball:130, valor_alvo:3583, tentativas:51,
--   buff_profissao:3, boost_multiplicador:1,
--   resultado:'capturou', data_captura:'2026-07-22'
-- }).select()
-- =====================================================================