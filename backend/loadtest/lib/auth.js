import http from 'k6/http';

export const BASE_URL = __ENV.BASE_URL || 'http://127.0.0.1:8000';

export function authedClient(token) {
  const headers = { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` };
  return {
    get: (path) => http.get(`${BASE_URL}${path}`, { headers }),
    post: (path, body) => http.post(`${BASE_URL}${path}`, JSON.stringify(body || {}), { headers }),
  };
}

export function pick(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}
