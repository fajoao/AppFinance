# Tokens de design: direção "Cédula"

Fonte da verdade: `Design/tokens.json`. Este arquivo explica as decisões e como aplicar em SwiftUI. O protótipo `Prototype/index.html` usa exatamente estes valores (variáveis CSS com o mesmo nome em kebab-case).

## Direção visual, em quatro frases

1. **A paleta vem do dinheiro brasileiro.** As cores de categoria são tiradas das cédulas do Real (garoupa, mico-leão, tartaruga, garça, arara, onça, lobo-guará). O brasileiro reconhece essas cores sem pensar, e elas fogem do roxo de banco digital e do verde-neon de fintech.
2. **O fundo é papel de algodão frio (#EEF2EF), não creme nem branco puro.** A tinta é verde-petróleo profundo (#0D5C63), a cor de um extrato impresso, sóbria e confiável.
3. **Vermelho não é despesa.** Despesa é texto normal com sinal −. Vermelho aparece só quando há problema real: saldo negativo, orçamento estourado, conta atrasada. Com isso o alerta continua chamando atenção e o app não deixa a pessoa ansiosa a cada café registrado.
4. **A assinatura é o numeral dividido.** Nos valores de destaque, os reais aparecem grandes e o "R$" e os centavos pequenos, alinhados pelo topo, como etiqueta de preço. Só existe esse elemento ousado. Fora dele a interface é contida: listas agrupadas do iOS, hairlines, quase sem sombras.

## Cores

Todas as combinações abaixo foram calculadas com a fórmula de luminância relativa do WCAG 2.1 (script em Node). Texto exige 4.5:1; barras, ícones e contornos exigem 3:1.

### Fundos e texto

| Token | Claro | Escuro | Uso |
|---|---|---|---|
| `canvas` | `#EEF2EF` | `#0E1513` | Fundo de tela |
| `surface` | `#FFFFFF` | `#17201D` | Grupos de lista, sheets |
| `surfaceRaised` | `#FFFFFF` | `#1F2A26` | Teclado, popovers |
| `sunken` | `#E3E9E5` | `#0A100E` | Campos, trilho de barra, segmentado |
| `textPrimary` | `#15241F` | `#E7EEEA` | Texto, despesas |
| `textSecondary` | `#4B5B55` | `#A9B7B1` | Rótulos secundários |
| `textTertiary` | `#56645F` | `#8D9C96` | Metadados |
| `separator` | `#CDD6D1` | `#2C3934` | Hairline (decorativa) |
| `border` | `#7F8E88` | `#6F7F79` | Contorno de controle |
| `brandPrimary` | `#0D5C63` | `#5CC2C6` | Ações, seleção, foco |
| `brandSoft` | `#D8EAE8` | `#173A3B` | Chip selecionado |
| `textOnBrand` | `#FFFFFF` | `#06292B` | Texto em botão primário |

### Semânticas

| Token | Claro | Escuro | Regra |
|---|---|---|---|
| `income` | `#176E3C` | `#57C98A` | Receita, sempre com `+` |
| `expense` | = `textPrimary` | = `textPrimary` | Despesa, sempre com `−` |
| `transfer` | = `brandPrimary` | = `brandPrimary` | Transferência, ícone ⇄, sem sinal |
| `warning` (texto) | `#8A5A00` | `#F2B551` | Orçamento ≥ 80%, vencimento em ≤ 3 dias |
| `warningFill` (barra) | `#A86A06` | `#E8A33D` | Preenchimento de barra em alerta |
| `danger` | `#B42318` | `#FF8B7E` | Saldo negativo, ≥ 100%, atrasado |
| `neutral` | `#56645F` | `#8D9C96` | Pendente, sem categoria |
| `incomeSoft` / `warningSoft` / `dangerSoft` | `#DDF0E3` / `#FBEBCF` / `#FBE3DF` | `#16301F` / `#3A2C12` / `#3D1D1A` | Fundo de badge |

### Contraste verificado (texto, mínimo 4.5:1)

| Par | Claro | Escuro |
|---|---|---|
| textPrimary / canvas | 14.25 | 15.69 |
| textPrimary / surface | 16.10 | 14.13 |
| textSecondary / canvas | 6.35 | 8.89 |
| textSecondary / sunken | 5.83 | 9.23 |
| textTertiary / canvas | 5.49 | 6.45 |
| textTertiary / sunken (pior caso) | 5.04 | 6.70 |
| brandPrimary / surface | 7.70 | 7.92 |
| brandPrimary / brandSoft | 6.18 | 5.86 |
| textOnBrand / brandPrimary | 7.70 | 7.34 |
| income / canvas | 5.58 | 8.92 |
| income / sunken (pior caso) | 5.12 | 9.26 |
| income / incomeSoft | 5.30 | 6.86 |
| warning / surface | 5.93 | 9.12 |
| warning / warningSoft | 5.05 | 7.43 |
| danger / surface | 6.57 | 7.33 |
| danger / dangerSoft | 5.37 | 6.66 |
| textOnDanger / danger | 6.57 | 8.04 |

### Contraste verificado (gráficos, mínimo 3:1 contra surface e trilho)

| Categoria | Claro | Escuro | vs surface (C/E) | vs trilho (C/E) |
|---|---|---|---|---|
| `catMoradia` | `#2E7D78` | `#56B3AD` | 4.86 / 6.70 | 3.95 / 5.35 |
| `catMercado` | `#B86F0B` | `#E7A443` | 3.95 / 7.76 | 3.21 / 6.20 |
| `catTransporte` | `#3A6EA5` | `#77A6DA` | 5.31 / 6.54 | 4.31 / 5.23 |
| `catLazer` | `#7653A8` | `#A88BD6` | 5.88 / 5.81 | 4.77 / 4.64 |
| `catSaude` | `#B8456A` | `#E07C9E` | 5.13 / 5.99 | 4.16 / 4.78 |
| `catEducacao` | `#8E6236` | `#C79A6A` | 5.32 / 6.55 | 4.32 / 5.23 |
| `catOutros` | `#6E7479` | `#9BA2A8` | 4.73 / 6.45 | 3.84 / 5.15 |
| `warningFill` | `#A86A06` | `#E8A33D` | 4.44 / 7.72 | 3.61 / 6.17 |
| `border` | `#7F8E88` | `#6F7F79` | 3.43 / 3.96 | n/a |

Cor nunca é a única pista. Categoria sempre tem nome; alerta sempre tem texto ("80% usado", "Estourou R$ 42,10"); tipo de lançamento sempre tem sinal.

## Tipografia

SF Pro do sistema, com Dynamic Type obrigatório. Não há fonte customizada: a personalidade vem do tratamento dos números, não do tipo de letra.

| Estilo | pt | Peso | SwiftUI |
|---|---|---|---|
| largeTitle | 34 | Bold | `.largeTitle.bold()` |
| title1 | 28 | Bold | `.title.bold()` |
| title2 | 22 | Semibold | `.title2.weight(.semibold)` |
| title3 | 20 | Semibold | `.title3.weight(.semibold)` |
| headline | 17 | Semibold | `.headline` |
| body | 17 | Regular | `.body` |
| callout | 16 | Regular | `.callout` |
| subheadline | 15 | Regular | `.subheadline` |
| footnote | 13 | Regular | `.footnote` |
| caption1 | 12 | Regular | `.caption` |
| caption2 | 11 | Regular | `.caption2` |

Regras de texto: sentence case em tudo (nada de rótulo em caixa alta), cabeçalhos de seção em `footnote` semibold `textSecondary`, máximo de 2 pesos por tela além do valor de destaque.

### Valores monetários

| Estilo | Tamanho | Peso | Dividido | Escala com |
|---|---|---|---|---|
| `amountHero` | 48 | Semibold | sim, R$ e centavos a 45% | `.largeTitle` |
| `amountLarge` | 28 | Semibold | sim, 55% | `.title` |
| `amountRow` | 17 | Medium | não | `.body` |
| `amountCaption` | 13 | Medium | não | `.footnote` |

```swift
struct SplitAmount: View {
    let value: Decimal
    var base: CGFloat = 48            // amountHero; use 28 para amountLarge
    var minorScale: CGFloat = 0.45    // 0.55 para amountLarge
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    var body: some View {
        let size = base * scale
        let p = MoneyFormatter.parts(value) // sign "−", symbol "R$", integer "1.234", fraction ",56"
        let minor = size * minorScale
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(p.sign + p.symbol).font(.system(size: minor, weight: .medium))
                .baselineOffset(size * 0.70 - minor * 0.70).padding(.trailing, minor * 0.12)
            Text(p.integer).font(.system(size: size, weight: .semibold)).tracking(-size * 0.025)
            Text(p.fraction).font(.system(size: minor, weight: .medium))
                .baselineOffset(size * 0.70 - minor * 0.70)
        }
        .monospacedDigit()
        .foregroundStyle(value < 0 ? Color.danger : Color.textPrimary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.formatted(.currency(code: "BRL").locale(Locale(identifier: "pt_BR"))))
    }
}
```
O deslocamento de baseline alinha o topo do "R$" e dos centavos ao topo dos dígitos grandes (altura de versal do SF Pro ≈ 0,70 do tamanho). Ajuste fino no Simulador.

### Regras para números financeiros

1. **Formato:** `R$ 1.234,56`, com espaço inseparável depois de R$, ponto no milhar e vírgula no decimal. Use `Decimal.FormatStyle.Currency(code: "BRL").locale(.init(identifier: "pt_BR"))`. Nunca `Double`.
2. **Dígitos tabulares sempre:** `.monospacedDigit()`. Colunas de valores não "dançam" ao rolar ou digitar.
3. **Alinhamento:** em linhas, o rótulo fica à esquerda e o valor à direita, na mesma baseline. Em telas de resumo, o valor de destaque é alinhado à esquerda (é o primeiro ponto que o olho lê).
4. **Sinal:** use o menos tipográfico `−` (U+2212), antes do símbolo: `−R$ 45,90`. Receita em lista leva `+R$`. Saldo positivo não leva sinal.
5. **Cor:** receita `income`, despesa `textPrimary`, transferência `brandPrimary`, saldo negativo `danger`, zero `textSecondary`.
6. **Centavos:** sempre exibidos (exceto eixos de gráfico, que usam `R$ 1,2 mil`).
7. **Ocultar valores:** o botão de olho no Início troca todos os valores por `R$ ••••`. VoiceOver lê "valor oculto".
8. **VoiceOver:** ler o valor por extenso ("menos quarenta e cinco reais e noventa centavos"). O sinal visual não é lido como "traço".
9. **Truncamento:** valor nunca trunca. Com Dynamic Type grande, a linha quebra: rótulo em cima, valor embaixo, alinhado à direita (`ViewThatFits`).

## Espaçamento (base 4pt)

| Token | pt | Uso |
|---|---|---|
| `xxs` | 2 | Ajuste ótico |
| `xs` | 4 | Ícone ↔ texto curto |
| `sm` | 8 | Entre chips |
| `md` | 12 | Padding vertical de linha |
| `lg` | 16 | Padding horizontal de linha |
| `xl` | 20 | Margem de tela |
| `xxl` | 24 | Bloco ↔ bloco interno |
| `xxxl` | 32 | Entre seções grandes |
| `huge` | 48 | Respiro do hero |

Alvos de toque têm no mínimo 44×44 pt. Linhas de lista têm no mínimo 52 pt.

## Raios (`RoundedRectangle(cornerRadius:, style: .continuous)`)

| Token | pt | Uso |
|---|---|---|
| `xs` | 6 | Tag |
| `sm` | 10 | Campo, tecla do teclado numérico |
| `md` | 14 | Grupo de lista |
| `lg` | 20 | Bloco destacado (fatura, meta) |
| `sheet` | 28 | Topo de sheet |
| `full` | 999 | Chip, barra de progresso, botão primário |

O raio cresce com o tamanho do contêiner. A interface não usa um raio único para tudo.

## Sombras

Só elementos flutuantes têm sombra: o botão "+" da tab bar, toasts e sheets. No modo claro a sombra é tingida com a tinta (`#15241F`, 10–12%). No escuro não há sombra; a elevação vem de `surfaceRaised`. Listas e blocos não têm sombra, só fundo `surface` sobre `canvas`.

## Movimento

`fast` 0.15 s, `standard` 0.25 s, `sheet` 0.35 s, curva `.snappy`. Há um único momento orquestrado: o saldo do Início faz contagem rápida ao abrir o mês. Com Reduzir Movimento ativo, os deslocamentos viram fade e a contagem é desligada.

## Mapa para SwiftUI

- Cores: um Color Set por token em `Assets.xcassets/Colors/` (Any + Dark), com acesso tipado por `extension Color { static let canvas = Color("canvas") ... }`.
- Categorias: `catMoradia`, `catMercado`, `catTransporte`, `catLazer`, `catSaude`, `catEducacao`, `catOutros`.
- Espaçamento e raios: `enum Space { static let xs: CGFloat = 4 ... }` e `enum Radius { ... }`.
- Foco: o anel de foco do sistema basta no iOS. No protótipo web, o foco é `2px solid brandPrimary` com `offset 2px`.
