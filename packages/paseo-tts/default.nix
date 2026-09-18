# paseo-tts: o plugin que le em voz alta a ultima resposta de um agente do
# Paseo, com um botao no composer em vez de leitura automatica.
#
# O caminho e resumo -> sintese -> audio: a resposta passa por um modelo pequeno
# via `omp --print`, que a reescreve como briefing falado (sem codigo, sem
# tabela, direto nas conclusoes e no que ficou de acao), o texto vai para o
# /v1/audio/speech da OpenAI e o mp3 toca com o ffplay. Ler o Markdown cru em
# voz alta foi a primeira versao e nao presta: ninguem quer ouvir uma cerca de
# crase sendo narrada.
#
# O audio sai na MAQUINA DO DAEMON, nao no aparelho que mostra o app. Nao ha
# escolha aqui: o bundle do cliente so recebe react, react-native, zod e o SDK
# do plugin, sem nenhuma API de audio. Em host pessoal isso da na mesma porque
# daemon e app sao a mesma maquina; pelo celular, o som sai no desktop.
#
# Nao ha build: o Paseo bundla o plugin a partir da fonte, e as dependencias do
# package.json sao todas de desenvolvimento (o host injeta React, React Native,
# Zod e o SDK em runtime). O unico import de terceiro no servidor e
# `@getpaseo/protocol`, e e `import type`, apagado na compilacao. Por isso o
# derivation e uma copia com dois paths fixados, e nao um npm build.
{
  stdenvNoCC,
  lib,
  ffmpeg,
  omp,
}:

stdenvNoCC.mkDerivation {
  pname = "paseo-tts";
  version = "0.2.0";
  src = ./src;

  # A PATH do daemon e o que o profile de login exportou, e um plugin que so
  # fala em algumas maquinas e pior que um que falha no build. `--replace-fail`
  # existe para quebrar aqui, e nao em producao, se o default do
  # server/tools.ts mudar de nome.
  postPatch = ''
    substituteInPlace server/tools.ts \
      --replace-fail '?? "ffplay"' '?? "${ffmpeg}/bin/ffplay"' \
      --replace-fail '?? "omp"' '?? "${omp}/bin/omp"'
  '';

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r . $out/
    runHook postInstall
  '';

  meta = {
    description = "Paseo plugin that speaks an agent's last answer as a voice briefing";
    platforms = lib.platforms.linux;
  };
}
