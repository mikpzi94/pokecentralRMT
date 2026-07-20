-- =====================================================================
-- PokeCentral — B2: denúncias + banimento de vendedor.
-- Rode no Supabase → SQL Editor (depois da fundação B1).
-- =====================================================================

-- ---------- BANIDOS ----------
create table if not exists banidos (
  user_id   uuid primary key references auth.users(id) on delete cascade,
  criado_em timestamptz default now()
);
alter table banidos enable row level security;

drop policy if exists "banidos_admin_insert" on banidos;
drop policy if exists "banidos_admin_select" on banidos;
drop policy if exists "banidos_admin_delete" on banidos;
create policy "banidos_admin_insert" on banidos for insert with check (is_admin());
create policy "banidos_admin_select" on banidos for select using (is_admin());
create policy "banidos_admin_delete" on banidos for delete using (is_admin());   -- des-banir

create or replace function esta_banido(uid uuid) returns boolean
  language sql security definer stable as $$
  select exists(select 1 from banidos where user_id = uid);
$$;

-- banido NÃO pode mais postar (atualiza a policy de insert da B1)
drop policy if exists "pokemons_insert" on pokemons;
create policy "pokemons_insert" on pokemons for insert with check (
  is_admin() or (
    auth.uid() is not null
    and user_id = auth.uid()
    and slots_ativos(auth.uid()) < 5
    and not esta_banido(auth.uid())
  )
);

-- ---------- DENÚNCIAS ----------
create table if not exists denuncias (
  id            bigint generated always as identity primary key,
  anuncio_id    text,
  vendedor_id   uuid,
  vendedor_nome text,
  anuncio_nome  text,
  motivo        text,
  resolvido     boolean default false,
  criado_em     timestamptz default now()
);
alter table denuncias enable row level security;

drop policy if exists "denuncias_insert_publico" on denuncias;
drop policy if exists "denuncias_admin_select"   on denuncias;
drop policy if exists "denuncias_admin_update"   on denuncias;
create policy "denuncias_insert_publico" on denuncias for insert with check (true);   -- qualquer um pode denunciar
create policy "denuncias_admin_select"   on denuncias for select using (is_admin());  -- só você lê
create policy "denuncias_admin_update"   on denuncias for update using (is_admin());  -- marcar resolvido

-- =====================================================================
-- (OPCIONAL) Ping no Discord quando chega denúncia.
-- Cole a MESMA URL do webhook do #moderacao. Se não quiser, é só NÃO
-- rodar este bloco — as denúncias ainda caem no painel admin.
-- =====================================================================
create or replace function notifica_denuncia() returns trigger language plpgsql security definer as $$
begin
  perform net.http_post(
    url := 'COLE_A_URL_AQUI',
    headers := jsonb_build_object('Content-Type','application/json'),
    body := jsonb_build_object('content',
      '🚩 **Denúncia** no anúncio **' || coalesce(new.anuncio_nome,'?') || '**' ||
      ' — vendedor: ' || coalesce(new.vendedor_nome,'?') || chr(10) ||
      'Motivo: ' || coalesce(new.motivo,'?') || chr(10) ||
      'Revise no painel da loja (modo dono).')
  );
  return new;
end;
$$;
drop trigger if exists trg_notifica_denuncia on denuncias;
create trigger trg_notifica_denuncia after insert on denuncias
  for each row execute function notifica_denuncia();
