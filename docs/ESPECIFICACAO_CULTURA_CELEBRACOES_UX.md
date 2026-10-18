# Cultura & Celebrações — revisão de UX e especificação de melhorias

Autor: agente analista de requisitos (DHO/Cultura/Endomarketing) · Data: 18/10/2026
Escopo: `/cultura-celebracoes` (`src/pages/CulturaCelebracoes.tsx`, `src/components/cultura/*`, `src/hooks/useCultura.ts`) e o widget de avisos do Mural (`src/pages/Feed.tsx`).
Status: proposta para decisão humana (Leiri). Nada foi alterado no sistema. Itens com [VALIDAR] são suposições sem dado.

---

## 0. Entendimento inicial

**Resultado de pessoas a mover:** nenhum colaborador passa uma data importante (aniversário, tempo de casa, dia da profissão) sem ser lembrado, e o RH gasta minutos por semana nisso, não horas.

**Para quem:** RH/DP (executa), gestor (tem a relação direta), colaborador (recebe e define como quer ser celebrado).

**O que existe hoje (lido no código):**
- 3 faixas na tela: KPIs, "Próximas Celebrações (30 dias)", Indicadores, e 3 abas (Experiência, Preferências, Rituais e Reconhecimento, esta com 4 sub-abas).
- Detecta aniversário, tempo de casa e dia da profissão a partir de `admissoes` (status `concluido`), por empresa ativa.
- Cada celebração vira uma "ação" manual (botão *Criar Ação*), que aparece no Mural.
- Tabelas: `cultura_datas`, `cultura_marcos`, `cultura_config`, `cultura_acoes`, `cultura_rituais`, `cultura_preferencias`.

**Premissas / o que falta validar:**
- [VALIDAR] Quantos colaboradores por empresa cliente (define se o calendário precisa agrupar por dia).
- [VALIDAR] Hoje o RH celebra por WhatsApp/pessoalmente fora do sistema? Se sim, o sistema precisa gerar o texto/arte, não só o lembrete.
- [VALIDAR] Política de exposição de data de nascimento no Mural por cliente (LGPD, ver seção 10).

---

## 1. Descoberta e opções

**Framework:** reconhecimento frequente e integrado muda cultura, o ocasional não (biblioteca 4.4); jornada do colaborador como fio condutor; escuta e ação fechando o ciclo.

**Dor real do usuário (diagnóstico da tela atual):**

| # | Achado | Evidência no código | Impacto |
|---|---|---|---|
| D1 | **Não há calendário.** Só lista de 8 itens (`slice(0,8)`) e agenda em cards. O RH não "enxerga o mês". | `ProximasCelebracoes.tsx`, `AgendaCelebracoes.tsx` | Alto |
| D2 | **A Configuração não governa nada.** Os interruptores (aniversário, tempo de casa, dia da profissão), "dias de antecedência", presente, folga, responsável padrão e os **Marcos** são salvos, mas a detecção usa 30 dias fixos e sempre os 3 tipos. | `RituaisReconhecimento.tsx` grava; `ProximasCelebracoes.tsx` não lê `config`/`marcos` | Alto: desligar não desliga; o RH perde a confiança na tela |
| D3 | **Tudo é manual.** Cada celebração exige 1 clique em *Criar Ação*, e depois outro para *Concluir*. Em empresa de 200 pessoas são ~400 cliques/ano só para registrar. | `handleCriarAcao` | Alto |
| D4 | **Toggle "criar antecipada" no formulário não faz nada.** O estado existe, mas o `handleSubmit` não envia. | `AgendaCelebracoes.tsx` linhas 42, 226-239 vs 66-76 | Médio (promessa quebrada) |
| D5 | **Preferências ficam numa aba isolada** e não aparecem na hora de celebrar. Quem pediu "sem exposição" pode ser exposto no Mural. | `PreferenciasColaborador.tsx` não é consumido pelas outras telas | Alto (risco de constrangimento e LGPD) |
| D6 | **Criar ação duplica:** a celebração detectada continua na lista após virar ação, e não há trava por pessoa+tipo+ano. | `handleCriarAcao`; `criandoAcao` é chaveado só por nome | Médio |
| D7 | **Bug de "anos de empresa" na virada do ano.** Se o aniversário de admissão já passou neste ano, a data empurra para o ano seguinte mas `anos` é calculado com o ano atual: sai 1 a menos (ex.: em dezembro, quem faz 5 anos em janeiro aparece com "4"). O Mural calcula certo. | `ProximasCelebracoes.tsx` (`anos = today.getFullYear() - adm.getFullYear()`) | Médio (erro visível em marco) |
| D8 | **Datas de ação com fuso:** `new Date(a.data_referencia)` em `yyyy-MM-dd` é lido em UTC e pode cair 1 dia antes. A própria tela já tem um parser seguro para admissões, mas não o usa nas ações. | `acoesProximas` | Baixo/Médio |
| D9 | **Duas lógicas paralelas** para o mesmo cálculo (tela de Cultura e widget do Mural), com resultados diferentes (D7). | `ProximasCelebracoes.tsx` vs `Feed.tsx` | Médio (manutenção) |
| D10 | **Dia da profissão** só casa por texto exato do cargo (`diasProfissao`), e some para quem tem cargo fora da lista. 29/02 vira 01/03. | `buscarDiaProfissao` | Baixo |
| D11 | **Título e nomenclatura:** a tela se chama "PESSOAS" no cabeçalho, o menu diz "Cultura & Celebrações". Rituais têm `proxima_execucao`/`ultima_execucao`, mas a tela não mostra o próximo ritual nem cobra. | `CulturaCelebracoes.tsx`; `RituaisReconhecimento.tsx` | Médio |
| D12 | **Medimos execução, não efeito.** Os indicadores contam ações concluídas, no prazo, atrasadas. Nenhum diz se as pessoas foram *alcançadas* (cobertura) nem se isso mexe em clima/retenção. | `CulturaIndicadores.tsx` | Alto (regra 2 e 4 do mandato) |
| D13 | **Mobile:** filtros de largura fixa lado a lado; gestor e colaborador (quem mais precisa agir rápido) usam celular. | `AgendaCelebracoes.tsx` | Médio |

**Opções:**
1. **Incremental:** corrigir D2/D4/D6/D7/D8 e ligar a configuração. Barato, resolve a confiança, não muda a experiência.
2. **Calendário + Painel do Dia (recomendada):** opção 1 mais calendário visual e fluxo de 1 toque.
3. **Inovadora, "Íris Celebra" (piloto automático):** o sistema executa sozinho o que o RH autorizou por regra (cria a ação, avisa o gestor, publica no Mural com a voz da Íris, gera cartão), e o humano só intervém na exceção. Depende da opção 2.

**Recomendação:** entregar 2 como base e 3 como camada de automação, em fases (seção 11).

---

## 2. Personas e jornada

| Persona | Quer | Hoje | Depois |
|---|---|---|---|
| **RH/DP** | Não esquecer ninguém e gastar pouco tempo | Entra, lê lista, cria ação por pessoa | Abre o "Hoje", aprova em lote ou deixa no automático |
| **Gestor** | Parabenizar o time na hora certa, com personalização | Não é acionado | Recebe lembrete de 1 toque com sugestão de mensagem |
| **Colaborador** | Ser lembrado do jeito que gosta, sem exposição indesejada | Preferência não é respeitada na prática | Define a preferência uma vez; ela governa o que é publicado |

**Jornada afetada:** onboarding (primeiro mês de casa) → marcos de tempo de casa → dia da profissão → aniversário → saída (despedida). Hoje cobre só 3 pontos; o "1º mês" e a "despedida" ficam de fora [VALIDAR prioridade].

---

## 3. Experiência (UX leve)

### 3.1 Nova estrutura da tela (de 3 faixas + 7 abas para 1 fluxo)

```
┌ Cultura & Celebrações ──────────────────────── [Configurar ⚙] ┐
│ HOJE  (3 aniversários · 1 tempo de casa)          [Celebrar todos ▸] │
│  🎂 Ana Souza   32 anos      [Parabenizar] [Mural] [Cartão] [Pular]   │
│  🏆 Bruno Lima  5 anos de casa  ⚠ marco: certificado  [Parabenizar]   │
├───────────────────────────────────────────────────────────────────────┤
│ CALENDÁRIO   [Mês | Ano]   Filtro: Tudo · Pessoas · Datas · Rituais   │
│  seg  ter  qua  qui  sex  sáb  dom                                    │
│  ...  🎂   .    🎂🎂  🏆   .    .      ← bolinhas por tipo, nº se >3  │
│  clicar no dia abre gaveta lateral com os itens e as ações            │
├───────────────────────────────────────────────────────────────────────┤
│ SAÚDE DA CULTURA   Cobertura 92% · Sem celebração há +12m: 7 pessoas  │
└───────────────────────────────────────────────────────────────────────┘
  Abas secundárias (raramente usadas): Agenda · Preferências · Rituais · Configuração
```

### 3.2 Princípios

- **Hoje primeiro.** A pergunta do usuário é "o que preciso fazer agora?". A resposta ocupa o topo; o resto é consulta.
- **1 toque = celebrar.** O botão *Parabenizar* cria a ação, publica o que a preferência permite e marca como concluída num só gesto, com desfazer por 10 s (toast).
- **Calendário visual.** Visão Mês (operação) e Ano (planejamento do RH: onde há concentração de datas, onde é preciso distribuir campanhas e rituais). Cores por tipo, já usadas hoje (rosa aniversário, azul tempo de casa, âmbar profissão, violeta ação/ritual).
- **Complexidade escondida.** Regras, marcos e limites vivem em *Configurar*, preenchidos com padrão sensato (aniversário e tempo de casa ligados, D-7, responsável = RH). O RH só mexe se quiser.
- **Preferência manda.** Antes de qualquer publicação, o botão consulta a preferência (ex.: "discreto" publica só para o gestor e o próprio colaborador).
- **Mobile primeiro** no "Hoje" e no gesto do gestor.

### 3.3 Onde a IA assiste (sempre sugerindo)

- Redige a mensagem de parabéns com a voz da Íris, no tom escolhido pelo RH (formal/leve), para o gestor editar antes de enviar.
- Sugere o tipo de reconhecimento do marco (certificado em 1 ano; mimo em 5; homenagem em 10) com base nos **Marcos**.
- Resume o mês: "este mês foram 14 datas, 12 celebradas; 2 sem responsável".
- Nunca decide sobre pessoa: não ranqueia, não pontua mérito (ver 10).

---

## 4. Requisitos funcionais

| ID | Requisito | Prioridade |
|---|---|---|
| RF-001 | Painel **Hoje**: lista celebrações do dia (e atrasadas não tratadas) com ações de 1 toque: Parabenizar, Publicar no Mural, Gerar cartão, Pular (com motivo opcional). | Alta |
| RF-002 | **Calendário** visual com visão Mês e Ano; marcadores por tipo; clique no dia abre gaveta com itens e ações. Alimentado por aniversários, tempo de casa, dia da profissão, datas configuráveis, rituais (`proxima_execucao`) e ações. | Alta |
| RF-003 | Filtros do calendário por tipo, unidade e setor (campos `filtro_unidade`/`filtro_setor` já existem em `cultura_datas`). | Média |
| RF-004 | **A Configuração passa a governar a detecção:** `aniversario_ativo`, `tempo_casa_ativo`, `dia_profissao_ativo` e `dias_antecedencia_acao` valem para Hoje, Calendário e Mural. | Alta (corrige D2) |
| RF-005 | **Marcos de tempo** definem o que fazer em cada marco (certificado, mimo, homenagem): a celebração de tempo de casa traz o marco aplicável e, se `presente_padrao`, o limite de `limite_valor_presente`. | Alta (corrige D2) |
| RF-006 | Trava de duplicidade por **pessoa + tipo + ano**: celebração já tratada sai da lista de pendentes e mostra o status. | Alta (corrige D6) |
| RF-007 | **Preferência no ponto de uso:** o item exibe como a pessoa prefere (ícone) e respeita `preferencia_aniversario`/`tipo_reconhecimento` ao publicar. | Alta |
| RF-008 | **Regras de automação** ("Íris Celebra"): por tipo de celebração, o RH escolhe *Avisar gestor*, *Criar ação*, *Publicar no Mural*, *Enviar cartão*; e se roda sozinho ou pede aprovação. Padrão = pede aprovação. | Média (Fase 3) |
| RF-009 | **Lembrete ao gestor** (D-N configurado) com mensagem sugerida e botão de 1 toque, por notificação/e-mail e no Feed. | Média |
| RF-010 | **Cartão/mensagem** gerado com a identidade da empresa e a Íris; vai para o módulo Documentos quando for certificado/homenagem formal. | Média |
| RF-011 | **Cobertura de celebração** por pessoa: data da última celebração; lista "sem celebração há mais de 12 meses". | Alta |
| RF-012 | Corrigir `anos` de tempo de casa na virada do ano (D7) e ler datas `yyyy-MM-dd` como locais em ações (D8); **centralizar** a lógica de "próximas celebrações" num único hook/RPC usado por Cultura e Mural (D9). | Alta |
| RF-013 | O toggle **"criar antecipada"** do formulário passa a funcionar (cria a ação já com lembrete em `dias_antecedencia`) ou é removido. | Baixa (D4) |
| RF-014 | Rituais: mostrar **próximo ritual** no calendário e no Hoje, botão *Registrar realização* que atualiza `ultima_execucao`/`proxima_execucao`, e lembrete ao responsável. | Média |
| RF-015 | Acrescentar eventos de jornada configuráveis: **1º mês de casa** e **despedida/desligamento** [VALIDAR]. | Baixa |
| RF-016 | Alertas relevantes (ação atrasada, cobertura abaixo da meta) trazem **Analisar com IA** e **Criar ação no Plano de Ação**. | Média |
| RF-017 | Convite de **felicitação entre pares** no Mural (já existe `onFelicitar`); mostrar contagem de felicitações recebidas ao celebrado, sem ranking público. | Baixa |
| RF-018 | Responsividade: filtros em *drawer* no mobile; cabeçalho consistente ("Cultura & Celebrações"). | Média (D11, D13) |

---

## 5. Regras de negócio

| ID | Regra | Tipo |
|---|---|---|
| RN-001 | Só entram colaboradores com `admissoes.status = 'concluido'` e da empresa ativa (escopo `tenant_id` + `empresa_id`). | Dado/Segurança |
| RN-002 | Tipo desligado em `cultura_config` não gera item, nem no Hoje, nem no calendário, nem no Mural. | Produto |
| RN-003 | Tempo de casa só considera `anos ≥ 1` e usa o ano da **data celebrada**, não do ano corrente. | Produto |
| RN-004 | Uma celebração (pessoa + tipo + ano) gera no máximo uma ação. | Produto |
| RN-005 | Aniversário em 29/02 é celebrado em 28/02 nos anos não bissextos [VALIDAR]. | Produto |
| RN-006 | **Preferência restritiva vence a automação:** quem pediu discrição não é publicado no Mural nem recebe publicação aberta, mesmo com regra automática ligada. | LGPD / Produto |
| RN-007 | **Data de nascimento nunca expõe o ano de nascimento nem a idade** em publicação aberta; mostra só dia/mês. Idade pode induzir discriminação etária. | LGPD / Trabalhista |
| RN-008 | Presente/folga respeitam `limite_valor_presente` e `folga_permitida`; fora do limite exige aprovação. Reconhecimento material pode ter reflexo tributário/trabalhista. | Legal: **jurídico valida** |
| RN-009 | Automação nunca conclui sozinha uma ação que envolva valor (presente/folga); conclui só ações de comunicação. | Produto |
| RN-010 | Item "Pular" registra quem pulou e quando; não some do histórico de cobertura. | Rastreabilidade |
| RN-011 | Documento formal (certificado, homenagem) é arquivado no módulo Documentos. | Regra global YE |

---

## 6. Dados

- **Entidades existentes aproveitadas:** `cultura_acoes`, `cultura_config`, `cultura_marcos`, `cultura_datas`, `cultura_rituais`, `cultura_preferencias`. Dado único: nome, cargo, nascimento e admissão continuam vindo de `admissoes`, sem recadastro.
- **Acréscimos propostos (sempre por migration + script de entrega, conforme a regra da casa):**
  - `cultura_acoes`: `canal` (mural/cartão/presencial), `publicado_em`, `origem` (manual/automatica), `chave_unica` (pessoa+tipo+ano) com índice único parcial → RN-004.
  - `cultura_config`: `modo_automacao` por tipo (desligado/aprovar/auto), `tom_mensagem`, `lembrar_gestor`.
  - `cultura_preferencias`: `exposicao` (aberta/discreta/nenhuma) como campo estruturado, em vez de só texto livre [VALIDAR contra os valores atuais de `preferencia_aniversario`].
- **Sensibilidade:** data de nascimento e preferências são dado pessoal (LGPD art. 6º); **não** são dado de saúde nem de clima. Preferência é de livre fornecimento pelo próprio colaborador.
- Desfazer da ação de 1 toque: atualizar `status` de volta; qualquer script que altere dado existente guarda backup, conforme CLAUDE.md.

---

## 7. Automação e IA

| Hoje (humano) | Depois | Trabalho economizado |
|---|---|---|
| Ler lista e criar ação por pessoa | Ações criadas por regra em D-N | ~100% dos cliques de criação |
| Escrever o parabéns | IA sugere texto com voz da Íris; humano edita | minutos por celebração |
| Lembrar o gestor por fora | Lembrete automático com 1 toque | elimina cobrança manual |
| Descobrir quem ficou de fora | Lista de cobertura | substitui planilha |

**Supervisão humana:** a IA só **sugere** texto e tipo de reconhecimento; nada que envolva valor, folga ou exposição sai sem aprovação (RN-006, RN-009). Anti-viés: a sugestão de reconhecimento depende do marco (tempo de casa), nunca de desempenho ou potencial; sem pontuação nem ranking de pessoas.

---

## 8. Métricas e fechamento do ciclo

| Indicador | Definição | Meta sugerida |
|---|---|---|
| **Cobertura de celebração** | % de colaboradores com ao menos 1 celebração no ano | ≥ 95% em 12 meses [VALIDAR] |
| **Pontualidade** | % de celebrações concluídas até o dia da data | ≥ 90% |
| **Automação** | % de ações criadas por regra | ≥ 80% em 6 meses |
| **Tempo do RH** | minutos/semana no módulo (telemetria) | −70% vs. linha de base [VALIDAR base] |
| **Alcance** | felicitações de pares por celebração; leitura no Mural | acompanhar 90 dias para definir meta |
| **Efeito** | variação do eNPS/pulso e da rotatividade em quem tem alta cobertura vs. baixa | análise trimestral [VALIDAR volume de dados] |

Os indicadores atuais (Taxa de Realização, No Prazo, Atrasadas, Tempo Médio) ficam como **indicadores operacionais**; **Cobertura** passa a ser o principal.

**Fechar o ciclo:** ação atrasada ou cobertura abaixo da meta gera alerta com *Analisar com IA* e *Criar ação no Plano de Ação*. Quando o módulo de Ouvidoria/Clima apontar queda em "reconhecimento", sugere reforçar a regra automática.

---

## 9. Integração com o ecossistema

- **Mural Interno / Feed:** fonte única de "próximas celebrações" (RF-012); o Mural exibe só o que a preferência permite.
- **Reconhecimento entre pares:** botão felicitar (já existe) vira parte do cartão.
- **Feedback & Desenvolvimento:** marco de tempo de casa abre convite para conversa de carreira/PDI, ligando celebração a desenvolvimento.
- **Onboarding:** 1º mês de casa como celebração; boas-vindas já cadastradas.
- **Documentos:** certificados e homenagens arquivados (RN-011).
- **Plano de Ação:** alertas viram ação (RF-016).
- **Meu Bem-Estar / NR-1:** ponte opcional e **agregada**: "cobertura de reconhecimento" como um dos sinais de clima, nunca por pessoa [VALIDAR com SST]. Não entra dado individual no GRO.
- **Íris:** voz do endomarketing em mensagens e cartões.

---

## 10. Ética, viés e LGPD

- **Base legal:** celebração de aniversário/tempo de casa é legítimo interesse do empregador com **expectativa razoável**; publicação aberta de data de nascimento é a parte sensível: por isso preferência (RN-006), minimização (RN-007) e opção de saída. **Exige validação do agente jurídico.**
- **Não-vigilância:** o módulo não monitora comportamento; "Cobertura" mede se a empresa cuidou, não se a pessoa "engajou".
- **Sem ranking de pessoas:** felicitações recebidas são mostradas a quem recebeu, não a terceiros.
- **Viés etário e de gênero:** sem exibir idade; textos sugeridos revisados para neutralidade; presentes sem estereótipo.
- **Isolamento multi-tenant:** manter políticas RLS atuais (caso CULT-070).
- **Exclusão:** cultura que celebra só alguns é pior que nenhuma. A lista de cobertura é o antídoto.

---

## 11. Critérios de aceite, fases, riscos e dúvidas

### Critérios de aceite

- **CA-001** Com `tempo_casa_ativo = false`, nenhuma celebração de tempo de casa aparece em Hoje, Calendário ou Mural.
- **CA-002** Com `dias_antecedencia_acao = 10`, a janela de detecção usa 10 dias.
- **CA-003** Colaborador que completa 5 anos em janeiro aparece com "5 anos" quando consultado em dezembro.
- **CA-004** Clicar em *Parabenizar* duas vezes na mesma celebração não cria duas ações.
- **CA-005** Colaborador com exposição "discreta" não aparece no Mural, mesmo com regra automática ligada.
- **CA-006** O calendário mostra, num mês de teste, os mesmos itens que a lista de Próximas Celebrações para o mesmo intervalo.
- **CA-007** Em tela de 375 px, o Hoje e o calendário não têm rolagem horizontal.
- **CA-008** Sem nenhuma ação, indicadores mostram 0% sem erro (mantém CULT-060).
- **CA-009** Publicação aberta não exibe ano de nascimento nem idade.
- **CA-010** Ação atrasada oferece *Analisar com IA* e *Criar ação no Plano de Ação*.

### Fases propostas (cada uma entregável sozinha)

| Fase | Conteúdo | Esforço |
|---|---|---|
| **1. Confiança** | RF-004, 005, 006, 012, 013 (corrigem D2, D4, D6, D7, D8, D9) | Pequeno |
| **2. Experiência** | RF-001, 002, 003, 007, 011, 014, 018 (Hoje, Calendário, cobertura, preferência no ponto de uso) | Médio |
| **3. Automação** | RF-008, 009, 010, 016, 017 ("Íris Celebra") | Médio/Grande |

### Riscos

- Automação publicar algo indevido → mitigação: padrão "pedir aprovação", RN-006, desfazer em 10 s.
- Calendário pesado em empresas grandes → agregar por dia e paginar a gaveta.
- Duas lógicas divergentes (D9) → resolver na Fase 1 antes de qualquer tela nova.

### Inovação

"Íris Celebra": a Íris avisa o gestor, sugere a mensagem e publica, em linguagem humana, aprendendo o tom escolhido pelo RH. Segunda ideia: **"Mapa de calor do ano"** para o RH distribuir rituais onde há vazio de datas.

### Dúvidas para decisão humana

1. Rodar automático por padrão ou sempre pedir aprovação?
2. A empresa pode exigir celebração mesmo contra a preferência? (Sugestão: não.)
3. Entram 1º mês de casa e despedida?
4. Aceita fazer a regra de LGPD de nascimento (RN-007) como padrão do produto?
5. Qual a meta de cobertura para o piloto?

### Impacto nas três conferências da casa (quando for implementar)

1. **Onde afeta:** Mural/Feed (widget duplicado), `admissoes` (só leitura), `planFeatures` (`mod.cultura`), Documentos, Plano de Ação.
2. **Documentação de Testes:** atualizar CULT-002, 012, 020, 050, 060; **criar** casos para calendário, Hoje, trava de duplicidade, preferência vs. automação e fuso/virada de ano.
3. **Execução:** novos `it()` em `cypress/e2e/cultura-celebracoes.cy.ts` + ponte `qa_cobertura_e2e`; regras de negócio (RN-002/003/004/006) como rotinas `qa_caso_*()` de nível `api`.

---

## Avaliação crítica do agente (10 perguntas)

1. **Move um resultado medível ou é mais um formulário?** Move cobertura e tempo do RH; o formulário cai (1 toque). Linha de base de tempo não existe: [VALIDAR].
2. **A experiência é leve?** O topo "Hoje" é leve; a Configuração e as regras podem virar burocracia se o padrão não for bom. Por isso os padrões vêm ligados.
3. **A medição fecha o ciclo?** Sim via Plano de Ação (RF-016), mas depende de o RH usar o alerta.
4. **Clima/bem-estar estão anônimos?** Este módulo não coleta clima; a ponte com NR-1 é só agregada e está marcada [VALIDAR].
5. **Avaliação defensável?** Não há avaliação de desempenho aqui; evitei qualquer métrica de mérito por pessoa.
6. **IA só sugere?** Sim; nada com valor ou exposição sai sem aprovação.
7. **Integração ou ilha?** Une Mural, Feed, Onboarding, Documentos e Plano de Ação; o risco restante é a lógica duplicada (D9), tratada na Fase 1.
8. **O que assumi sem dado?** Metas (95%, 80%, −70%), tamanho das empresas, valor percebido de cartão/despedida, 29/02 e comportamento atual do RH.
9. **Tive viés de produto?** Posso estar superestimando automação; empresas pequenas talvez prefiram o toque humano. O padrão "aprovar" cobre isso.
10. **O que não verifiquei?** Não abri o banco nem rodei a tela; os achados vêm de leitura de código. Confirmar D2 e D5 no staging antes de priorizar.
