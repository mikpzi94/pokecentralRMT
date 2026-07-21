-- =====================================================================
-- PokeCentral — avisa no Discord quando entra anúncio NOVO pra aprovar.
-- Dispara só em anúncio 'pendente' (de jogador). Os seus (dono) já
-- nascem 'aprovado', então NÃO te notificam — só o que precisa moderar.
-- =====================================================================

-- 1) Habilita a extensão de rede (se ainda não estiver)
create extension if not exists pg_net;

-- 2) COMO PEGAR A URL DO WEBHOOK DO DISCORD:
--    No Discord → crie um canal (ex: #moderacao, só seu) →
--    Editar Canal → Integrações → Webhooks → Novo Webhook → "Copiar URL".
--    Cole a URL no lugar de COLE_A_URL_AQUI abaixo.

create or replace function notifica_novo_anuncio()
  returns trigger language plpgsql security definer as $$
begin
  if new.status = 'pendente' then
    perform net.http_post(
      url     := 'https://discord.com/api/webhooks/1528798114792607817/dgbl6nSvxI6EIzG2l_673we9ptNQqpkYOJ1XpXWOlTQIeKO1AWMfPePVq7s8Qz_BImVW',
      headers := jsonb_build_object('Content-Type','application/json'),
      body    := jsonb_build_object(
        'content',
        '🆕 **Anúncio novo pra aprovar!**' || chr(10) ||
        '**' || coalesce(new.nome,'?') || '**' ||
        ' · IV ' || coalesce(new.iv::text,'?') ||
        coalesce(' · Qualidade ' || new.qualidade, '') ||
        ' · R$ ' || coalesce(new.preco::text,'?') || chr(10) ||
        'Abra a loja no modo vendedor pra aprovar/rejeitar.'
      )
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notifica_anuncio on pokemons;
create trigger trg_notifica_anuncio after insert on pokemons
  for each row execute function notifica_novo_anuncio();

-- Pronto. Faça um insert de teste (conta de jogador) e veja cair no canal.
-- =====================================================================
