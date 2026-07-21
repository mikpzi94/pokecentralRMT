-- =====================================================================
-- PokeCentral — imagens otimizadas + remoção segura + limpeza de órfãs.
-- Rode no Supabase > SQL Editor antes de publicar o novo loja.html.
-- =====================================================================

-- O caminho interno permite excluir o objeto sem depender da URL pública.
alter table pokemons add column if not exists print_path text;
alter table lotes    add column if not exists print_path text;

-- Os uploads antigos ficam com print_path vazio. O site extrai o caminho da
-- URL quando necessário; uploads novos já gravam o caminho exato.

-- O dono do arquivo pode apagá-lo; o administrador pode apagar qualquer print.
-- A leitura pública e as policies de upload existentes continuam iguais.
drop policy if exists "prints_delete_proprio_ou_admin" on storage.objects;
create policy "prints_delete_proprio_ou_admin" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'prints'
    and (
      owner_id = auth.uid()::text
      or public.is_admin()
    )
  );

-- Lista somente objetos sem referência em loja OU leilão.
-- Arquivos com menos de uma hora são ignorados para evitar corrida com upload.
create or replace function public.listar_imagens_orfas()
returns table (caminho text, tamanho bigint)
language plpgsql
security definer
set search_path = public, storage
as $$
begin
  if not public.is_admin() then
    raise exception 'somente administrador';
  end if;

  return query
  select o.name::text,
         coalesce((o.metadata->>'size')::bigint, 0)
    from storage.objects o
   where o.bucket_id = 'prints'
     and o.created_at < now() - interval '1 hour'
     and not exists (
       select 1 from public.pokemons p
        where p.print_path = o.name
           or p.print like '%' || o.name
           or p.print like '%' || replace(o.name, ' ', '%20')
     )
     and not exists (
       select 1 from public.lotes l
        where l.print_path = o.name
           or l.print like '%' || o.name
           or l.print like '%' || replace(o.name, ' ', '%20')
     )
   order by o.created_at;
end;
$$;

revoke all on function public.listar_imagens_orfas() from public;
grant execute on function public.listar_imagens_orfas() to authenticated;

-- A função apenas LOCALIZA. A exclusão é feita pela API oficial do Storage,
-- em lotes de 100, depois de você conferir quantidade/tamanho e confirmar.
-- =====================================================================
