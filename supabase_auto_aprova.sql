-- =====================================================================
-- PokeCentral — auto-aprovação com checagem automática
-- Anúncio de jogador entra NA HORA se passar nas regras objetivas.
-- O que falhar cai na fila manual (status 'pendente'). Confiável passa sempre.
-- Você modera DEPOIS (falar com o vendedor / ✕ tirar / denúncia / ban).
-- Rode este arquivo no SQL Editor do Supabase DEPOIS do supabase_b3.sql.
-- =====================================================================

-- Checagem objetiva do anúncio. Ajuste o teto de preço se quiser.
create or replace function anuncio_ok(p_nome text, p_preco numeric, p_iv int, p_print text)
  returns boolean language sql immutable as $$
  select p_print is not null and length(btrim(p_print)) > 0          -- tem print
     and p_nome  is not null and length(btrim(p_nome))  > 0          -- tem nome
     and p_preco is not null and p_preco > 0 and p_preco <= 100000   -- preço são (segura troll)
     and (p_iv is null or (p_iv >= 0 and p_iv <= 192));              -- IV coerente
$$;

-- GUARD atualizado: confiável OU passou na checagem = aprovado na hora; senão, fila manual.
create or replace function pokemons_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    if is_admin() then
      if new.user_id is null then new.user_id := auth.uid(); end if;
      if new.status is null or new.status = 'pendente' then new.status := 'aprovado'; end if;
    else
      new.user_id := auth.uid();
      new.status  := case
        when eh_confiavel(auth.uid())                              then 'aprovado'   -- confiável: passa sempre
        when anuncio_ok(new.nome, new.preco, new.iv, new.print)    then 'aprovado'   -- passou na checagem: no ar
        else 'pendente'                                                              -- falhou algo: fila manual
      end;
    end if;
    return new;
  end if;

  -- UPDATE (edição do vendedor volta pra checagem se mexeu em campo relevante)
  if is_admin() then return new; end if;
  new.user_id := old.user_id;
  if (new.nome, new.qualidade, new.iv, new.nivel, new.preco, new.print, new.poke_id, new.obs)
     is distinct from
     (old.nome, old.qualidade, old.iv, old.nivel, old.preco, old.print, old.poke_id, old.obs)
  then
    new.status := case
      when eh_confiavel(auth.uid())                            then 'aprovado'
      when anuncio_ok(new.nome, new.preco, new.iv, new.print)  then 'aprovado'
      else 'pendente'
    end;
  else
    new.status := old.status;
  end if;
  return new;
end;
$$;
