import { ApiError, createApiClient } from './api-client';

export interface SessionUser {
  id: number;
  email: string;
  displayName: string;
  role: string;
  roles: readonly string[];
}

interface AuthUserDto {
  id: number;
  email: string;
  fullName: string;
  roles: string[];
}

interface LoginResponse {
  accessToken: string;
  tokenType: string;
  expiresAtUtc: string;
  refreshToken: string;
  refreshTokenExpiresAtUtc: string;
  user: AuthUserDto;
}

export interface RefreshTokenStorage {
  read(): Promise<string | null>;
  write(token: string): Promise<void>;
  clear(): Promise<void>;
}

export interface SessionSnapshot {
  status: 'loading' | 'authenticated' | 'anonymous';
  user: SessionUser | null;
}

function userFromDto(value: AuthUserDto): SessionUser {
  if (!value || !Number.isSafeInteger(value.id) || value.id <= 0 ||
      typeof value.email !== 'string' || typeof value.fullName !== 'string' ||
      !Array.isArray(value.roles) || !value.roles.every((role) => typeof role === 'string')) {
    throw new ApiError('Thông tin tài khoản từ máy chủ không hợp lệ.', 401);
  }
  return {
    id: value.id,
    email: value.email,
    displayName: value.fullName,
    role: value.roles[0] ?? '',
    roles: value.roles,
  };
}

export function createAuthClient({
  origin,
  storage,
  fetcher,
}: {
  origin: string;
  storage: RefreshTokenStorage;
  fetcher?: typeof fetch;
}) {
  const http = createApiClient(origin, fetcher);
  let snapshot: SessionSnapshot = { status: 'loading', user: null };
  let session: LoginResponse | null = null;
  let savedRefreshToken: string | null = null;
  let generation = 0;
  let refreshFlight: { generation: number; promise: Promise<string> } | null = null;
  let restoreFlight: Promise<void> | null = null;
  let persistence = Promise.resolve();
  const listeners = new Set<() => void>();

  const publish = (next: SessionSnapshot) => {
    snapshot = next;
    listeners.forEach((listener) => listener());
  };
  const persist = (token: string | null, version: number) => {
    const operation = persistence.catch(() => undefined).then(async () => {
      if (version !== generation) return;
      try {
        if (token) await storage.write(token);
        else await storage.clear();
      } catch {
        throw new ApiError('Không truy cập được bộ nhớ an toàn trên thiết bị. Vui lòng thử lại.');
      }
    });
    persistence = operation;
    return operation;
  };
  const clear = async () => {
    generation += 1;
    session = null;
    savedRefreshToken = null;
    publish({ status: 'anonymous', user: null });
    await persist(null, generation);
  };
  const revoke = (token: string) => http<void>('/api/v1/auth/logout', {
    method: 'POST', body: JSON.stringify({ refreshToken: token }),
  }).catch(() => undefined);

  const adopt = async (next: LoginResponse, version: number) => {
    if (!next || typeof next.accessToken !== 'string' || !next.accessToken ||
        typeof next.refreshToken !== 'string' || !next.refreshToken || next.tokenType !== 'Bearer' ||
        !Number.isFinite(Date.parse(next.expiresAtUtc)) || Date.parse(next.expiresAtUtc) <= Date.now() ||
        !Number.isFinite(Date.parse(next.refreshTokenExpiresAtUtc)) || Date.parse(next.refreshTokenExpiresAtUtc) <= Date.now()) {
      throw new ApiError('Phiên đăng nhập từ máy chủ không hợp lệ.', 401);
    }
    const user = userFromDto(next.user);
    if (version !== generation) {
      void revoke(next.refreshToken);
      throw new ApiError('Phiên đăng nhập đã thay đổi.', 401);
    }
    try {
      await persist(next.refreshToken, version);
    } catch {
      if (version === generation) await clear().catch(() => undefined);
      void revoke(next.refreshToken);
      throw new ApiError('Không lưu được phiên đăng nhập an toàn trên thiết bị. Vui lòng thử lại.');
    }
    if (version !== generation) {
      void revoke(next.refreshToken);
      throw new ApiError('Phiên đăng nhập đã thay đổi.', 401);
    }
    session = next;
    savedRefreshToken = next.refreshToken;
    publish({ status: 'authenticated', user });
    return next.accessToken;
  };

  const refresh = (): Promise<string> => {
    const version = generation;
    if (refreshFlight?.generation === version) return refreshFlight.promise;
    const token = session?.refreshToken ?? savedRefreshToken;
    if (!token) return Promise.reject(new ApiError('Vui lòng đăng nhập để tiếp tục.', 401));
    const promise = (async () => {
      try {
        const next = await http<LoginResponse>('/api/v1/auth/refresh', {
          method: 'POST', body: JSON.stringify({ refreshToken: token }),
        });
        return await adopt(next, version);
      } catch (error) {
        if (version === generation && error instanceof ApiError && [401, 403].includes(error.status)) {
          await clear();
        }
        throw error;
      } finally {
        if (refreshFlight?.generation === version) refreshFlight = null;
      }
    })();
    refreshFlight = { generation: version, promise };
    return promise;
  };

  return {
    getSnapshot: () => snapshot,
    subscribe(listener: () => void) {
      listeners.add(listener);
      return () => { listeners.delete(listener); };
    },
    restore(): Promise<void> {
      if (restoreFlight) return restoreFlight;
      const version = generation;
      restoreFlight = (async () => {
        try {
          const token = await storage.read();
          if (version !== generation) return;
          savedRefreshToken = token;
          if (token) await refresh();
          else publish({ status: 'anonymous', user: null });
        } catch {
          // Keep a stored token on transient network failures; invalid tokens are cleared by refresh.
          if (version === generation) publish({ status: 'anonymous', user: null });
        }
      })();
      return restoreFlight;
    },
    async signIn(email: string, password: string) {
      const version = ++generation;
      session = null;
      savedRefreshToken = null;
      publish({ status: 'anonymous', user: null });
      await persist(null, version);
      const next = await http<LoginResponse>('/api/v1/auth/login', {
        method: 'POST', body: JSON.stringify({ email: email.trim(), password }),
      });
      try {
        if (!next || typeof next.accessToken !== 'string' || !next.accessToken) {
          throw new ApiError('Phiên đăng nhập từ máy chủ không hợp lệ.', 401);
        }
        // Fetch current account data instead of deriving identity or roles from a JWT on the device.
        const user = await http<AuthUserDto>('/api/v1/auth/me', {
          headers: { Authorization: `Bearer ${next.accessToken}` },
        });
        await adopt({ ...next, user }, version);
      } catch (error) {
        if (typeof next?.refreshToken === 'string') void revoke(next.refreshToken);
        throw error;
      }
    },
    async signOut() {
      const token = session?.refreshToken ?? savedRefreshToken;
      try {
        await clear();
      } finally {
        if (token) await revoke(token);
      }
    },
    async request<T>(path: string, init: RequestInit = {}): Promise<T> {
      const version = generation;
      if (!session) throw new ApiError('Vui lòng đăng nhập để tiếp tục.', 401);
      let token = session.accessToken;
      if (Date.parse(session.expiresAtUtc) <= Date.now() + 15_000) token = await refresh();
      const send = (accessToken: string) => {
        const headers = new Headers(init.headers);
        headers.set('Authorization', `Bearer ${accessToken}`);
        return http<T>(path, { ...init, headers });
      };
      try {
        return await send(token);
      } catch (error) {
        if (!(error instanceof ApiError) || error.status !== 401 || generation !== version) throw error;
        const nextToken = session?.accessToken !== token && session ? session.accessToken : await refresh();
        if (generation !== version) throw new ApiError('Phiên đăng nhập đã thay đổi.', 401);
        try {
          return await send(nextToken);
        } catch (retryError) {
          if (generation === version && retryError instanceof ApiError && retryError.status === 401) await clear();
          throw retryError;
        }
      }
    },
  };
}
