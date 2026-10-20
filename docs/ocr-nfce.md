# NFC-e, OCR de comprovantes e boletos

> **Estado:** a lógica de texto (Core) é testada com `swiftc`. O leitor de QR (AVFoundation), o reconhecimento de texto (Vision)
> e as telas foram compilados contra o SDK do iOS, mas **nunca rodaram com câmera real** neste ambiente. Revise no aparelho.

## NFC-e (QR Code do cupom)

- `NFCeParser` lê a URL do QR (`...?p=chave|versão|tpAmb|...`, o layout antigo `chNFe=` ou a chave pura) e valida a chave de 44
  dígitos: UF, mês de emissão, CNPJ (com dígito verificador), modelo (65 = NFC-e, 55 = NF-e), série, número e o **dígito
  verificador módulo 11** da chave. `NFCeAccessKey.cnpjIsValid` valida o CNPJ.
- **O QR online não traz o valor.** O valor (`vNF`) e o dia só vêm no QR da NFC-e emitida em **contingência offline**
  (`chave|2|tpAmb|dia|vNF|digestValue|idCSC|hash`). O app pré-preenche o valor quando existe e, caso contrário, pede para digitar.
  O layout dos campos segue a nota técnica da NFC-e (versão 2 do QR) conforme o autor a conhece; confira a versão vigente da sua SEFAZ,
  pois as versões do QR mudam. Chave e CNPJ são validados por regra matemática estável.
- O `externalId` do lançamento é `nfce:<chave>`: ler a mesma nota duas vezes avisa que ela já foi lançada.

### Consulta online à SEFAZ: NÃO implementada (de propósito)

`NFCeLookupService` é só um protocolo, sem implementação. Cada estado tem portal, formato e termos próprios; muitos exigem captcha ou
proíbem consulta automatizada. Para trazer o nome do estabelecimento e os itens seria preciso um serviço/contrato (um backend ou um
provedor de dados fiscais) e revisão jurídica. Sem isso, o app mostra UF, CNPJ, chave e (se existir) valor, e o usuário completa.

## OCR de comprovantes

- `ReceiptTextRecognizer` (Vision, `VNRecognizeTextRequest`, `pt-BR`, no aparelho) devolve texto em linhas, de cima para baixo.
  Sem correção de linguagem, para não trocar dígitos de boletos.
- `ReceiptTextExtractor` extrai **valor, data e estabelecimento** de **cupom fiscal**, **PIX/transferência** e **boleto**.
  São heurísticas testadas com textos de exemplo; fotos reais (reflexo, amassado, fonte térmica) podem errar. O resultado é sempre
  uma sugestão, conferida pela pessoa antes de salvar.
  - Cupom: total pelo rótulo (ignora subtotal, troco, desconto e tributos); sem rótulo, usa o maior valor e avisa.
  - PIX: valor, data (inclusive `18 OUT 2026`), favorecido/origem, direção (enviado = despesa, recebido = receita) e ID E2E.
  - Boleto: veja abaixo.

## Boleto

- **Linha digitável de 47 dígitos** (banco): valida os 3 dígitos de bloco (módulo 10) e o DV geral (módulo 11); extrai banco, valor
  e vencimento. **Convênio de 48 dígitos** (contas de consumo): valida os 4 blocos e o DV geral; extrai o valor quando é em reais.
  Também aceita o código de barras de 44 dígitos.
- **Fator de vencimento:** conta dias desde 07/10/1997 e reinicia em 1000 a partir de 22/02/2025 (ciclos de 9000 dias). O app escolhe
  a data dentro da janela de −3000 a +5500 dias de hoje; um boleto muito antigo pode cair no ciclo errado (ambiguidade do formato).
- Linha inválida: o app **não** usa os dígitos para preencher valor ou data, e avisa.
- Validar os dígitos não prova que o boleto existe, está em aberto ou é legítimo.
- Os vetores de teste de boleto/NFC-e foram gerados por uma implementação independente (Python) das regras; há também um boleto
  público do Banco do Brasil muito citado em tutoriais.

## Permissões e privacidade

- **Câmera** (`NSCameraUsageDescription`, já no `project.yml`): só para ler o QR Code. A imagem não é gravada nem enviada.
- **Fotos:** `PhotosPicker` roda fora do processo e não exige `NSPhotoLibraryUsageDescription`.
- Todo o processamento (QR e OCR) é local. Veja `docs/app-store-checklist.md`.
