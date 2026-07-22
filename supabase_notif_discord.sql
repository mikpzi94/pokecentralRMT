-- =====================================================================
-- PokeCentral — aviso privado de moderação para anúncio pendente.
--
-- Opcional: crie no Vault o segredo "discord_webhook_moderacao".
-- Sem esse segredo, o trigger apenas ignora o aviso e nunca bloqueia o anúncio.
-- =====================================================================

create extension if not exists pg_net;

create or replace function notifica_novo_anuncio()
returns trigger
language plpgsql
security definer
set search_path = public, vault, net
as $$
declare
  hook text;
begin
  if new.status <> 'pendente' then
    return new;
  end if;

  select decrypted_secret into hook
    from vault.decrypted_secrets
   where name = 'discord_webhook_moderacao'
   limit 1;

  if hook is null or hook not like 'https://discord.com/api/webhooks/%' then
    return new;
  end if;

  perform net.http_post(
    url := hook,
    headers := jsonb_build_object('Content-Type','application/json'),
    body := jsonb_build_object(
      'content',
      '🆕 **Anúncio novo para aprovar!**' || chr(10) ||
      '**' || coalesce(new.nome,'?') || '**' ||
      ' · IV ' || coalesce(new.iv::text,'?') ||
      coalesce(' · Qualidade ' || new.qualidade, '') ||
      ' · R$ ' || coalesce(new.preco::text,'?') || chr(10) ||
      'Abra a loja no modo vendedor para aprovar ou rejeitar.'
    )
  );
  return new;
exception when others then
  raise warning 'Falha ao avisar moderação no Discord: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists trg_notifica_anuncio on pokemons;
create trigger trg_notifica_anuncio
after insert on pokemons
for each row execute function notifica_novo_anuncio();

revoke all on function notifica_novo_anuncio() from public, anon, authenticated;