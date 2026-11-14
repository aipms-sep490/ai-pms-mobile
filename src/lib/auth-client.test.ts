import assert from 'node:assert/strict';
import test from 'node:test';
import { ApiError, apiOrigin, createApiClient } from './api-client';
import { createAuthClient, type RefreshTokenStorage } from './auth-client';

const userDto = { id: 7, email: 'student@example.test', fullName: 'Sinh viên', roles: ['STUDENT'] };
const loginResponse = (suffix = 'initial') => ({
  accessToken: `access-${suffix}`,
  tokenType: 'Bearer',
  expiresAtUtc: new Date(Date.now() + 3_600_000).toISOString(),
  refreshToken: `refresh-${suffix}`,
  refreshTokenExpiresAtUtc: new Date(Date.now() + 86_400_000).toISOString(),
  user: userDto,
});
function memoryStorage(initial: string | null = null) {
  let value = initial;
  const writes: (string | null)[] = [];
  const storage: RefreshTokenStorage = {
    read: async () => value,
    write: async (token) => { value = token; writes.push(token); },
    clear: async () => { value = null; writes.push(null); },
  };
  return { storage, writes, get: () => value };
}
const json = (value: unknown, status = 200) => new Response(JSON.stringify(value), { status });
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((next) => { resolve = next; });
  return { promise, resolve };
}
function authorizedClient(fetcher: typeof fetch, initial: string | null = null) {
  const store = memoryStorage(initial);
  return { ...store, client: createAuthClient({ origin: 'https://api.example.test', storage: store.storage, fetcher }) };
}

test('API configuration and route guards prevent credential delivery to another origin', async () => {
  assert.equal(apiOrigin('https://api.example.test/'), 'https://api.example.test');
  for (const invalid of ['', 'file:///private', 'https://user:secret@api.example.test', 'https://api.example.test/api']) {
    assert.throws(() => apiOrigin(invalid), ApiError);
  }
  let calls = 0;
  const http = createApiClient('https://api.example.test', async () => { calls += 1; return json({}); });
  for (const route of ['https://attacker.test/api/v1/users', '//attacker.test/api/v1/users', '/api/v1/../../private', '/api/v1/\\attacker']) {
    await assert.rejects(http(route), ApiError);
  }
  assert.equal(calls, 0);
});

test('API errors hide sensitive ProblemDetails content and handle request timeout', async () => {
  const http = createApiClient('https://api.example.test', async () => json({ detail: 'SQL password=private' }, 500));
  await assert.rejects(http('/api/v1/auth/me'), (error: unknown) => {
    if (!(error instanceof ApiError)) return false;
    assert.equal(error.status, 500);
    assert.doesNotMatch(error.message, /SQL|password|private/);
    return true;
  });
  const slow = createApiClient('https://api.example.test', async (_url, init) => new Promise((_resolve, reject) => {
    init?.signal?.addEventListener('abort', () => reject(new Error('aborted')), { once: true });
  }), 5);
  await assert.rejects(slow('/api/v1/auth/me'), /quá thời gian/);
});

test('login uses email/password contract, verifies /me, and persists only refresh token', async () => {
  const calls: { path: string; init?: RequestInit }[] = [];
  const { client, writes, get } = authorizedClient(async (url, init) => {
    calls.push({ path: new URL(String(url)).pathname, init });
    if (calls.length === 1) return json(loginResponse());
    return json({ ...userDto, fullName: 'Tên mới nhất' });
  });
  await client.signIn(' student@example.test ', 'password');
  assert.deepEqual(JSON.parse(String(calls[0].init?.body)), { email: userDto.email, password: 'password' });
  assert.equal(calls[1].path, '/api/v1/auth/me');
  assert.equal(new Headers(calls[1].init?.headers).get('Authorization'), 'Bearer access-initial');
  assert.equal(client.getSnapshot().user?.displayName, 'Tên mới nhất');
  assert.deepEqual(client.getSnapshot().user?.roles, ['STUDENT']);
  assert.deepEqual(writes, [null, 'refresh-initial']);
  assert.equal(get(), 'refresh-initial');
});

test('concurrent 401 responses share one token rotation and replay with the replacement token', async () => {
  let rotations = 0;
  const rotation = deferred<Response>();
  const { client, get } = authorizedClient(async (url, init) => {
    const path = new URL(String(url)).pathname;
    if (path.endsWith('/login')) return json(loginResponse());
    if (path.endsWith('/me')) return json(userDto);
    if (path.endsWith('/refresh')) { rotations += 1; return rotation.promise; }
    const token = new Headers(init?.headers).get('Authorization');
    return token === 'Bearer access-rotated' ? json({ ok: true }) : json({}, 401);
  });
  await client.signIn(userDto.email, 'password');
  const first = client.request('/api/v1/projects');
  const second = client.request('/api/v1/tasks');
  await new Promise<void>((resolve) => setImmediate(resolve));
  assert.equal(rotations, 1);
  rotation.resolve(json(loginResponse('rotated')));
  assert.deepEqual(await Promise.all([first, second]), [{ ok: true }, { ok: true }]);
  assert.equal(get(), 'refresh-rotated');
});

test('invalid refresh session clears persisted credentials; restore is single-flight', async () => {
  let rotations = 0;
  const { client, get } = authorizedClient(async () => { rotations += 1; return json({}, 401); }, 'expired');
  await Promise.all([client.restore(), client.restore()]);
  assert.equal(rotations, 1);
  assert.equal(client.getSnapshot().status, 'anonymous');
  assert.equal(get(), null);
});

test('403 resource denial preserves the session instead of refreshing or clearing it', async () => {
  let rotations = 0;
  const { client } = authorizedClient(async (url) => {
    const path = new URL(String(url)).pathname;
    if (path.endsWith('/login')) return json(loginResponse());
    if (path.endsWith('/me')) return json(userDto);
    if (path.endsWith('/refresh')) rotations += 1;
    return json({}, 403);
  });
  await client.signIn(userDto.email, 'password');
  await assert.rejects(client.request('/api/v1/dashboards/admin'), (error: unknown) => error instanceof ApiError && error.status === 403);
  assert.equal(rotations, 0);
  assert.equal(client.getSnapshot().status, 'authenticated');
});

test('logout clears local state even if server revocation fails', async () => {
  const { client, get } = authorizedClient(async (url) => {
    const path = new URL(String(url)).pathname;
    if (path.endsWith('/login')) return json(loginResponse());
    if (path.endsWith('/me')) return json(userDto);
    throw new Error('offline');
  });
  await client.signIn(userDto.email, 'password');
  await client.signOut();
  assert.equal(client.getSnapshot().status, 'anonymous');
  assert.equal(get(), null);
});

test('a late token rotation cannot restore a logged-out user and revokes the replacement', async () => {
  const rotation = deferred<Response>();
  const revoked: string[] = [];
  const { client, get } = authorizedClient(async (url, init) => {
    const path = new URL(String(url)).pathname;
    if (path.endsWith('/login')) return json(loginResponse());
    if (path.endsWith('/me')) return json(userDto);
    if (path.endsWith('/refresh')) return rotation.promise;
    if (path.endsWith('/logout')) {
      revoked.push(JSON.parse(String(init?.body)).refreshToken);
      return new Response(null, { status: 204 });
    }
    return json({}, 401);
  });
  await client.signIn(userDto.email, 'password');
  const request = client.request('/api/v1/projects');
  await new Promise<void>((resolve) => setImmediate(resolve));
  await client.signOut();
  rotation.resolve(json(loginResponse('late')));
  await assert.rejects(request, ApiError);
  await new Promise<void>((resolve) => setImmediate(resolve));
  assert.equal(client.getSnapshot().status, 'anonymous');
  assert.equal(get(), null);
  assert.deepEqual(revoked.sort(), ['refresh-initial', 'refresh-late']);
});
