-- =====================================================================
-- PokeCentral — B3: reviews + selo "Confiável" + auto-aprovação.
-- Rode no Supabase → SQL Editor (depois de B1 e B2).
-- =====================================================================

-- ---------- REVIEWS ----------
create table if not exists reviews (
  id          bigint generated always as identity primary key,
  vendedor_id uuid not null references auth.users(id) on delete cascade,
  autor_id    uuid not null references auth.users(id) on delete cascade,
  autor_nome  text,
  nota        int check (nota between 1 and 5),
  texto       text,
  criado_em   timestamptz default now()
);
alter table reviews enable row level security;

-- 1 review por pessoa por vendedor (anti-spam)
create unique index if not exists idx_review_unica on reviews (vendedor_id, autor_id);

drop policy if exists "reviews_select_publico" on reviews;
drop policy if exists "reviews_insert_logado"  on reviews;
drop policy if exists "reviews_admin_delete"   on reviews;
create policy "reviews_select_publico" on reviews for select using (true);   -- reputação é pública
create policy "reviews_insert_logado"  on reviews for insert
  with check (auth.uid() is not null and autor_id = auth.uid() and autor_id <> vendedor_id);  -- logado, no próprio nome, não avalia a si mesmo
create policy "reviews_admin_delete"   on reviews for delete using (is_admin());  -- você remove review abusiva

-- ---------- CONFIÁVEIS (selo conquistado) ----------
create table if not exists confiaveis (
  user_id   uuid primary key references auth.users(id) on delete cascade,
  criado_em timestamptz default now()
);
alter table confiaveis enable row level security;
drop policy if exists "confiaveis_select_publico" on confiaveis;
drop policy if exists "confiaveis_admin_insert"   on confiaveis;
drop policy if exists "confiaveis_admin_delete"   on confiaveis;
create policy "confiaveis_select_publico" on confiaveis for select using (true);   -- o selo é público
create policy "confiaveis_admin_insert"   on confiaveis for insert with check (is_admin());  -- você promove manual
create policy "confiaveis_admin_delete"   on confiaveis for delete using (is_admin());        -- ou tira

create or replace function eh_confiavel(uid uuid) returns boolean
  language sql security definer stable as $$
  select exists(select 1 from confiaveis where user_id = uid);
$$;

-- auto-promove a confiável: >= 5 reviews e média >= 4
create or replace function auto_confiavel() returns trigger language plpgsql security definer as $$
declare c int; m numeric;
begin
  select count(*), coalesce(avg(nota),0) into c, m from reviews where vendedor_id = new.vendedor_id;
  if c >= 5 and m >= 4 then
    insert into confiaveis (user_id) values (new.vendedor_id) on conflict do nothing;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_auto_confiavel on reviews;
create trigger trg_auto_confiavel after insert on reviews for each row execute function auto_confiavel();

-- ---------- GUARD: confiável = auto-aprovado ----------
create or replace function pokemons_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    if is_admin() then
      if new.user_id is null then new.user_id := auth.uid(); end if;
      if new.status is null or new.status = 'pendente' then new.status := 'aprovado'; end if;
    else
      new.user_id := auth.uid();
      new.status  := case when eh_confiavel(auth.uid()) then 'aprovado' else 'pendente' end;  -- confiável não espera fila
    end if;
    return new;
  end if;

  -- UPDATE
  if is_admin() then return new; end if;
  new.user_id := old.user_id;
  if (new.nome, new.qualidade, new.iv, new.nivel, new.preco, new.print, new.poke_id, new.obs)
     is distinct from
     (old.nome, old.qualidade, old.iv, old.nivel, old.preco, old.print, old.poke_id, old.obs)
  then
    new.status := case when eh_confiavel(auth.uid()) then 'aprovado' else 'pendente' end;
  else
    new.status := old.status;
  end if;
  return new;
end;
$$;
