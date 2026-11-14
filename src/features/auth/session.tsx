import { createContext, useContext, useEffect, useState, useSyncExternalStore, type ReactNode } from 'react';
import { createAuthClient } from '../../lib/auth-client';
import { tokenStorage } from '../../lib/token-storage';

type AuthClient = ReturnType<typeof createAuthClient>;
type SessionContextValue = ReturnType<AuthClient['getSnapshot']> &
  Pick<AuthClient, 'signIn' | 'signOut' | 'request'>;

const SessionContext = createContext<SessionContextValue | null>(null);

export function SessionProvider({ children }: { children: ReactNode }) {
  const [client] = useState(() => createAuthClient({
    origin: process.env.EXPO_PUBLIC_API_URL ?? '',
    storage: tokenStorage,
  }));
  const snapshot = useSyncExternalStore(client.subscribe, client.getSnapshot, client.getSnapshot);
  useEffect(() => { void client.restore(); }, [client]);

  return (
    <SessionContext.Provider value={{
      ...snapshot,
      signIn: client.signIn,
      signOut: client.signOut,
      request: client.request,
    }}>
      {children}
    </SessionContext.Provider>
  );
}

export function useSession() {
  const session = useContext(SessionContext);
  if (!session) throw new Error('useSession must be used inside SessionProvider.');
  return session;
}
