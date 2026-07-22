-- =====================================================================
-- PokeCentral — feeds públicos do Discord usando segredos do Supabase Vault
--
-- Segredos esperados no Vault:
--   discord_webhook_loja
--   discord_webhook_pedidos
--   discord_webhook_leilao
--
-- Rode uma vez no Supabase → SQL Editor.
-- Nenhuma URL secreta deve ser colocada neste arquivo.
-- =====================================================================

create extension if not exists pg_net;

-- ---------------------------------------------------------------------
-- LOJA: INSERT já aprovado OU transição pendente/rejeitado → aprovado.
-- Edições posteriores de anúncio aprovado não geram mensagem duplicada.
-- ---------------------------------------------------------------------
create or replace function discord_feed_loja()
returns trigger
language plpgsql
security definer
set search_path = public, vault, net
as $$
declare
  hook text;
  detalhes text;
  preco_txt text;
  link text;
  embed jsonb;
begin
  if new.status <> 'aprovado' or new.disponivel is false then
    return new;
  end if;

  if tg_op = 'UPDATE' and old.status = 'aprovado' then
    return new;
  end if;

  select decrypted_secret into hook
    from vault.decrypted_secrets
   where name = 'discord_webhook_loja'
   limit 1;

  if hook is null or hook not like 'https://discord.com/api/webhooks/%' then
    raise warning 'Webhook discord_webhook_loja ausente ou inválido';
    return new;
  end if;

  preco_txt := 'R$ ' || replace(to_char(coalesce(new.preco,0), 'FM999999990.00'), '.', ',');
  link := 'https://pokecentral-rmt.vercel.app/p/' || new.id::text;
  detalhes :=
    'IV ' || coalesce(new.iv::text, '?') ||
    ' · Qualidade ' || coalesce(new.qualidade::text, '?') ||
    ' · Nível ' || coalesce(new.nivel::text, '?') || chr(10) ||
    '**' || preco_txt || '** · ' ||
    case when coalesce(new.aceita_oferta,false) then 'aceita propostas' else 'valor fixo' end || chr(10) ||
    'Vendedor: ' || coalesce(nullif(btrim(new.vendedor_nome),''), 'PokeCentral');

  embed := jsonb_strip_nulls(jsonb_build_object(
    'title', '🛒 ' || coalesce(new.nome,'Novo Pokémon'),
    'url', link,
    'description', detalhes,
    'color', 15774761,
    'image', case when new.print is not null and btrim(new.print) <> ''
                  then jsonb_build_object('url',new.print) else null end,
    'footer', jsonb_build_object('text','PokeCentral · anúncio publicado')
  ));

  perform net.http_post(
    url := hook,
    headers := jsonb_build_object('Content-Type','application/json'),
    body := jsonb_build_object(
      'username','PokeCentral · Loja',
      'content','**Novo Pokémon disponível na loja!**',
      'embeds',jsonb_build_array(embed),
      'allowed_mentions',jsonb_build_object('parse',jsonb_build_array())
    )
  );
  return new;
exception when others then
  raise warning 'Falha ao avisar #loja no Discord: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists trg_discord_feed_loja on pokemons;
create trigger trg_discord_feed_loja
after insert or update of status on pokemons
for each row execute function discord_feed_loja();


-- ---------------------------------------------------------------------
-- PEDIDOS: novo pedido aprovado OU transição posterior para aprovado.
-- ---------------------------------------------------------------------
create or replace function discord_feed_pedidos()
returns trigger
language plpgsql
security definer
set search_path = public, vault, net
as $$
declare
  hook text;
  requisitos text := '';
  orcamento text;
  link text;
begin
  if new.status <> 'aprovado' or new.ativo is false or new.expira_em <= now() then
    return new;
  end if;

  if tg_op = 'UPDATE' and old.status = 'aprovado' then
    return new;
  end if;

  select decrypted_secret into hook
    from vault.decrypted_secrets
   where name = 'discord_webhook_pedidos'
   limit 1;

  if hook is null or hook not like 'https://discord.com/api/webhooks/%' then
    raise warning 'Webhook discord_webhook_pedidos ausente ou inválido';
    return new;
  end if;

  if new.iv_min is not null then requisitos := requisitos || 'IV ' || new.iv_min || '+'; end if;
  if new.qualidade_min is not null then
    requisitos := requisitos || case when requisitos<>'' then ' · ' else '' end ||
                  'Qualidade ' || new.qualidade_min || '+';
  end if;
  if new.nivel_min is not null then
    requisitos := requisitos || case when requisitos<>'' then ' · ' else '' end ||
                  'Nível ' || new.nivel_min || '+';
  end if;
  if new.shiny = 'obrigatorio' then
    requisitos := requisitos || case when requisitos<>'' then ' · ' else '' end || 'Shiny obrigatório';
  elsif new.shiny = 'opcional' then
    requisitos := requisitos || case when requisitos<>'' then ' · ' else '' end || 'Shiny opcional';
  end if;
  if requisitos = '' then requisitos := 'Sem requisitos mínimos adicionais'; end if;

  orcamento := case
    when new.preco_min is not null then
      'R$ ' || replace(to_char(new.preco_min,'FM999999990.00'),'.',',') ||
      ' a R$ ' || replace(to_char(new.preco_max,'FM999999990.00'),'.',',')
    else
      'Até R$ ' || replace(to_char(new.preco_max,'FM999999990.00'),'.',',')
  end;
  link := 'https://pokecentral-rmt.vercel.app/loja?pedido=' || new.id::text;

  perform net.http_post(
    url := hook,
    headers := jsonb_build_object('Content-Type','application/json'),
    body := jsonb_build_object(
      'username','PokeCentral · Pedidos',
      'content','**Novo pedido publicado pela comunidade!**',
      'embeds',jsonb_build_array(jsonb_build_object(
        'title','📋 Procuro: ' || coalesce(new.pokemon_nome,'Pokémon'),
        'url',link,
        'description',requisitos || chr(10) || '**Orçamento: ' || orcamento || '**' || chr(10) ||
                      'Comprador: ' || coalesce(new.comprador_nome,'Jogador'),
        'color',5088255,
        'footer',jsonb_build_object('text','PokeCentral · pedido ativo por 7 dias')
      )),
      'allowed_mentions',jsonb_build_object('parse',jsonb_build_array())
    )
  );
  return new;
exception when others then
  raise warning 'Falha ao avisar #pedidos no Discord: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists trg_discord_feed_pedidos on pedidos;
create trigger trg_discord_feed_pedidos
after insert or update of status on pedidos
for each row execute function discord_feed_pedidos();


-- ---------------------------------------------------------------------
-- LEILÃO: publica somente quando um novo leilão é criado.
-- ---------------------------------------------------------------------
create or replace function discord_feed_leilao()
returns trigger
language plpgsql
security definer
set search_path = public, vault, net
as $$
declare
  hook text;
  detalhes text;
  link text;
  embed jsonb;
begin
  select decrypted_secret into hook
    from vault.decrypted_secrets
   where name = 'discord_webhook_leilao'
   limit 1;

  if hook is null or hook not like 'https://discord.com/api/webhooks/%' then
    raise warning 'Webhook discord_webhook_leilao ausente ou inválido';
    return new;
  end if;

  link := 'https://pokecentral-rmt.vercel.app/l/' || new.id::text;
  detalhes :=
    'IV ' || coalesce(new.iv::text,'?') ||
    ' · Qualidade ' || coalesce(new.qualidade::text,'?') ||
    ' · Nível ' || coalesce(new.nivel::text,'?') || chr(10) ||
    '**Lance inicial: R$ ' || replace(to_char(new.lance_inicial,'FM999999990.00'),'.',',') || '**' ||
    case when new.preco_ja is not null and new.preco_ja > 0
         then ' · Compre já: R$ ' || replace(to_char(new.preco_ja,'FM999999990.00'),'.',',')
         else '' end || chr(10) ||
    'Encerra em ' || to_char(new.fim at time zone 'America/Sao_Paulo','DD/MM/YYYY "às" HH24:MI');

  embed := jsonb_strip_nulls(jsonb_build_object(
    'title','🔨 Leilão aberto: ' || coalesce(new.nome,'Pokémon'),
    'url',link,
    'description',detalhes,
    'color',10182117,
    'image',case when new.print is not null and btrim(new.print)<>''
                 then jsonb_build_object('url',new.print) else null end,
    'footer',jsonb_build_object('text','PokeCentral · dê seu lance antes do encerramento')
  ));

  perform net.http_post(
    url := hook,
    headers := jsonb_build_object('Content-Type','application/json'),
    body := jsonb_build_object(
      'username','PokeCentral · Leilão',
      'content','**Um novo leilão começou!**',
      'embeds',jsonb_build_array(embed),
      'allowed_mentions',jsonb_build_object('parse',jsonb_build_array())
    )
  );
  return new;
exception when others then
  raise warning 'Falha ao avisar #leilao no Discord: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists trg_discord_feed_leilao on lotes;
create trigger trg_discord_feed_leilao
after insert on lotes
for each row execute function discord_feed_leilao();

-- Triggers executam as funções; usuários da API não precisam chamá-las.
revoke all on function discord_feed_loja() from public, anon, authenticated;
revoke all on function discord_feed_pedidos() from public, anon, authenticated;
revoke all on function discord_feed_leilao() from public, anon, authenticated;

-- Conferência sem revelar segredos:
select name
from vault.secrets
where name in (
  'discord_webhook_loja',
  'discord_webhook_pedidos',
  'discord_webhook_leilao'
)
order by name;