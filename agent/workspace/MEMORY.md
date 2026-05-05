# MEMORY.md — Memória durável

Fatos duráveis, regras inegociáveis, decisões. Cap ~3KB. NÃO duplicar PERSONA/USER/BOOTSTRAP. Detalhes operacionais vão para `memory/YYYY-MM-DD.md`. Conteúdo grande para `vault/`.

## Negócio

**Márcio Medeiros Educação** — escola de educação contábil tributária para setor imobiliário e construção civil.

- **Produto flagship:** Formação Completa PF+PJ — **R$ 2.997**. NUNCA inventar/alterar preço.
- **Especialista:** Márcio Medeiros — filho de pedreiro que virou contador especializado em INSS de obras.
- **Prova social:** 1.500+ alunos, R$ 3M+ economizados, ferramenta CalcProObra.
- **Público-alvo:** contadores, engenheiros, arquitetos, profissionais de construção civil.

## Lançamento ativo

- Sempre verificar lançamento corrente em `memory/YYYY-MM-DD.md` mais recente.
- Lotes, datas, criativos e LP ficam no PC do operador (você não acessa diretamente).

## Regras inegociáveis de copy

- Nunca "pra"/"pro" — sempre "para"/"para o"
- Nunca travessão (—)
- Nunca inventar preço, escassez falsa, urgência apelativa
- Nunca começar copy com atributo de produto
- Hierarquia emocional: **85% emoção / 10% vaidade-status / 5% razão**
- Idioma: português BR sempre

## Agentes IA do PC do operador (referência, você não acessa)

Operador opera múltiplos agentes via Claude Code: especialistas em RAG técnico, estratégia/copy/lançamento, Meta Ads, oferta/escala, design UI. Entrada: `/orquestrar`.

Você é COO Digital — operacional, proativa. Copy séria, roteiro de lançamento e análise específica de concorrente são feitos pelos agentes locais. Você complementa, não substitui.

## Decisões importantes

- **2026-04-24 (v1) — Fallback de modelo:** Sonnet 4.6 → Haiku 4.5 → gpt-5.4-mini → deepseek-v3.2 → trinity-mini.
- **2026-04-24 (v1) — Heartbeat 12h** isolated/light/active 08-20.
- **2026-04-25 (v2) — cacheRetention "long"** (TTL 1h) para Anthropic. Cache hit em conversas próximas.
- **2026-04-25 (v2) — Healthcheck override Haiku.** Briefing fica em Sonnet (qualidade).
- **2026-04-25 (v2) — Bootstrap consolidado:** SOUL+IDENTITY → PERSONA. AGENTS, HEARTBEAT (workspace) deletados (config em openclaw.json). USER enxuto. -49% tokens/sessão.

## Lições aprendidas

_Adicionar quando padrão novo for confirmado. Formato: `YYYY-MM-DD — [contexto] → [lição 1 frase]`._

---
*v2 — 2026-04-25. Cap 3KB para forçar disciplina (detalhes em `memory/`). Confirmar com operador antes de apagar.*
