import { Dec } from './decimal'
import { format } from './money'

export type FinanceErrorCode =
  | 'invalidAmount' | 'sameAccount' | 'invalidInstallmentCount' | 'invalidDay' | 'overpayment'
  | 'budgetBelowMinimums' | 'malformedFile' | 'notFound' | 'invalidQuantity' | 'insufficientQuantity'
  | 'invalidPercentages' | 'noParticipants' | 'permissionDenied' | 'lastAdmin' | 'invalidState'

const MESSAGES: Record<Exclude<FinanceErrorCode, 'budgetBelowMinimums' | 'malformedFile' | 'invalidState'>, string> = {
  invalidAmount: 'Valor inválido',
  sameAccount: 'Origem e destino devem ser contas diferentes',
  invalidInstallmentCount: 'Número de parcelas inválido',
  invalidDay: 'Dia inválido',
  overpayment: 'Pagamento maior que o saldo da fatura',
  notFound: 'Registro não encontrado',
  invalidQuantity: 'Quantidade inválida',
  insufficientQuantity: 'Quantidade maior que a posição',
  invalidPercentages: 'Os percentuais devem somar 100%',
  noParticipants: 'Escolha ao menos um participante',
  permissionDenied: 'Seu papel na família não permite esta ação',
  lastAdmin: 'A família precisa ter ao menos um administrador',
}

export class FinanceError extends Error {
  constructor(public code: FinanceErrorCode, message?: string, public required?: Dec) {
    super(
      message ??
        (code === 'budgetBelowMinimums'
          ? `Orçamento abaixo dos pagamentos mínimos (${format(required!)})`
          : MESSAGES[code as keyof typeof MESSAGES]),
    )
    this.name = 'FinanceError'
  }
}
export const invalidState = (m: string) => new FinanceError('invalidState', m)
