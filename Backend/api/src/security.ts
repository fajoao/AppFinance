import { createHash, randomBytes, randomInt } from 'node:crypto';
import argon2 from 'argon2';

// OWASP: argon2id com m=19 MiB, t=2, p=1 como mínimo.
const ARGON_OPTS = { type: argon2.argon2id, memoryCost: 19456, timeCost: 2, parallelism: 1 } as const;

export const hashPassword = (password: string): Promise<string> => argon2.hash(password, ARGON_OPTS);

export async function verifyPassword(hash: string, password: string): Promise<boolean> {
  try {
    return await argon2.verify(hash, password);
  } catch {
    return false;
  }
}

/** Hash usado quando o e-mail não existe, para o tempo de resposta não revelar contas. */
let dummy: Promise<string> | undefined;
export const dummyHash = (): Promise<string> => (dummy ??= hashPassword('dummy-password-not-used'));

export const sha256 = (s: string): string => createHash('sha256').update(s).digest('hex');

export const newRefreshToken = (): string => randomBytes(32).toString('base64url');

// Sem 0/O/1/I/L para evitar confusão ao digitar.
const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

export function newInviteCode(): string {
  let c = '';
  for (let i = 0; i < 8; i++) c += ALPHABET[randomInt(ALPHABET.length)];
  return c;
}

export const formatInviteCode = (c: string): string => `${c.slice(0, 4)}-${c.slice(4)}`;
export const normalizeInviteCode = (c: string): string => c.replace(/[^A-Za-z0-9]/g, '').toUpperCase();

const COMMON = new Set(['password12', 'password123', '1234567890', '12345678910', 'qwertyuiop', 'senha12345', 'senha123456', 'abcdefghij', '0123456789']);

/** Política mínima de senha (comprimento + lista curta de senhas óbvias). Retorna mensagem de erro ou null. */
export function passwordProblem(password: string, email: string): string | null {
  if (password.length < 10) return 'A senha deve ter pelo menos 10 caracteres.';
  if (password.length > 128) return 'A senha deve ter no máximo 128 caracteres.';
  if (new Set(password).size < 4) return 'A senha é simples demais.';
  const lower = password.toLowerCase();
  if (COMMON.has(lower) || lower === email.toLowerCase()) return 'Escolha uma senha menos previsível.';
  return null;
}
