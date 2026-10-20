# C4 nível 1: contexto do sistema

Mostra o App Finanças como uma caixa só, as pessoas que o usam e os sistemas externos com os quais ele conversa. É o diagrama para qualquer público.

**Legenda:** itens marcados "(planejado)" ainda não estão ligados. O que existe e foi testado não tem marca.

```mermaid
C4Context
  title Contexto do sistema: App Finanças

  Person(usuario, "Usuário ou família", "Controla contas, cartões, orçamento e metas")

  System(appFinancas, "App Finanças", "App iOS, versão web, API e banco de dados")

  System_Ext(cloudflare, "Cloudflare Tunnel", "Expõe a API na internet por HTTPS")
  System_Ext(cloudkit, "CloudKit (planejado)", "Sincronização entre aparelhos Apple")
  System_Ext(openFinance, "Provedor Open Finance (planejado)", "Extratos bancários automáticos")
  System_Ext(sefaz, "SEFAZ (planejado)", "Consulta de notas fiscais NFC-e")
  System_Ext(whatsapp, "WhatsApp Cloud API (planejado)", "Canal do agente por mensagem")

  Rel(usuario, appFinancas, "Registra e consulta finanças usando", "iOS e navegador")
  Rel(appFinancas, cloudflare, "Publica a API por meio de", "HTTPS")
  Rel(appFinancas, cloudkit, "Sincronizaria dados com", "CloudKit")
  Rel(appFinancas, openFinance, "Importaria extratos de", "API do provedor")
  Rel(appFinancas, sefaz, "Consultaria notas em", "HTTPS")
  Rel(whatsapp, appFinancas, "Enviaria mensagens do usuário para", "Webhook HTTPS")

  UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")
```
