import type { RefreshTokenStorage } from './auth-client';

// Browser previews deliberately keep credentials in memory, never localStorage or cookies.
export const tokenStorage: RefreshTokenStorage = {
  read: async () => null,
  write: async () => undefined,
  clear: async () => undefined,
};
