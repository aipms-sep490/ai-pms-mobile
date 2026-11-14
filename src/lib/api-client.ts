export class ApiError extends Error {
  constructor(message: string, public readonly status = 0) {
    super(message);
    this.name = 'ApiError';
  }
}

export function apiOrigin(value: string): string {
  let url: URL;
  try {
    url = new URL(value.trim());
  } catch {
    throw new ApiError('Chưa cấu hình địa chỉ API. Kiểm tra EXPO_PUBLIC_API_URL.');
  }
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password ||
      url.search || url.hash || url.pathname !== '/') {
    throw new ApiError('Địa chỉ API phải là một HTTP(S) origin, không gồm đường dẫn.');
  }
  return url.origin;
}

const messages: Record<number, string> = {
  400: 'Thông tin chưa hợp lệ. Vui lòng kiểm tra và thử lại.',
  401: 'Thông tin đăng nhập không hợp lệ hoặc phiên đăng nhập đã hết hạn.',
  403: 'Tài khoản không được phép thực hiện thao tác này.',
  404: 'Không tìm thấy dữ liệu được yêu cầu.',
  409: 'Dữ liệu đã thay đổi. Vui lòng tải lại trước khi tiếp tục.',
  422: 'Thao tác chưa đáp ứng điều kiện của hệ thống.',
  429: 'Có quá nhiều yêu cầu. Vui lòng thử lại sau ít phút.',
};

export function createApiClient(
  origin: string,
  fetcher: typeof fetch = fetch,
  timeoutMs = 15_000,
) {
  return async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
    const base = apiOrigin(origin);
    const url = new URL(path, base);
    if (url.origin !== base || !path.startsWith('/api/v1/') || !url.pathname.startsWith('/api/v1/') || path.includes('\\')) {
      throw new ApiError('Đường dẫn API không hợp lệ.');
    }

    const controller = new AbortController();
    const abort = () => controller.abort();
    init.signal?.addEventListener('abort', abort, { once: true });
    if (init.signal?.aborted) controller.abort();
    let timedOut = false;
    const timeout = setTimeout(() => {
      timedOut = true;
      controller.abort();
    }, timeoutMs);
    try {
      const headers = new Headers(init.headers);
      headers.set('Accept', 'application/json');
      if (typeof init.body === 'string' && !headers.has('Content-Type')) {
        headers.set('Content-Type', 'application/json');
      }
      const response = await fetcher(url.toString(), {
        ...init,
        headers,
        credentials: 'omit',
        redirect: 'error',
        signal: controller.signal,
      });
      if (!response.ok) {
        // ProblemDetails may contain provider or database details; show a safe status message.
        throw new ApiError(messages[response.status] ?? 'Hệ thống chưa thể xử lý yêu cầu. Vui lòng thử lại.', response.status);
      }
      if (response.status === 204) return undefined as T;
      const body = await response.text();
      if (!body) return undefined as T;
      try {
        return JSON.parse(body) as T;
      } catch {
        throw new ApiError('Phản hồi từ máy chủ không hợp lệ.');
      }
    } catch (error) {
      if (error instanceof ApiError) throw error;
      if (timedOut) throw new ApiError('Kết nối quá thời gian chờ. Vui lòng thử lại.');
      if (init.signal?.aborted) throw new ApiError('Yêu cầu đã được hủy.');
      throw new ApiError('Không kết nối được máy chủ. Kiểm tra mạng và thử lại.');
    } finally {
      clearTimeout(timeout);
      init.signal?.removeEventListener('abort', abort);
    }
  };
}
