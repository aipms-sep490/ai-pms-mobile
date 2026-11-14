import * as SecureStore from 'expo-secure-store';
import type { RefreshTokenStorage } from './auth-client';

const key = 'aipms.mobile.refresh-token';

export const tokenStorage: RefreshTokenStorage = {
  read: () => SecureStore.getItemAsync(key),
  write: (token) => SecureStore.setItemAsync(key, token, {
    keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY,
  }),
  clear: () => SecureStore.deleteItemAsync(key),
};
