import { z } from 'zod';

export const RECORD_TYPES = [
  'Account', 'Category', 'Tag', 'Transaction', 'CreditCard', 'Invoice', 'Budget', 'Goal', 'GoalContribution',
  'Debt', 'Investment', 'NetWorthSnapshot', 'Household', 'FamilyMember', 'ExpenseSplit', 'SplitSettlement',
  'Allowance', 'ApprovalRequest', 'Tombstone',
] as const;
export type RecordType = (typeof RECORD_TYPES)[number];

export const MAX_RECORDS_PER_PUSH = 500;
export const MAX_RECORD_BYTES = 64 * 1024;

const email = z.string().trim().toLowerCase().max(254).pipe(z.email());

export const registerBody = z.strictObject({
  email,
  password: z.string().min(1).max(128),
  name: z.string().trim().min(1).max(80),
});
export const loginBody = z.strictObject({ email, password: z.string().min(1).max(128) });
export const refreshBody = z.strictObject({ refreshToken: z.string().min(20).max(200) });
export const inviteBody = z.strictObject({ role: z.enum(['member', 'dependent']).default('member') });
export const joinBody = z.strictObject({ code: z.string().min(6).max(20) });

export const syncQuery = z.strictObject({
  since: z.string().regex(/^\d{1,15}$/).default('0'),
  limit: z.coerce.number().int().min(1).max(5000).default(1000),
});

export const incomingRecord = z.strictObject({
  type: z.enum(RECORD_TYPES),
  id: z.guid(),
  data: z.record(z.string(), z.unknown()).default({}),
  updatedAt: z.iso.datetime({ offset: true }),
  deleted: z.boolean().default(false),
});
export type IncomingRecord = z.infer<typeof incomingRecord>;

export const syncBody = z.strictObject({
  records: z.array(incomingRecord).max(MAX_RECORDS_PER_PUSH),
});
