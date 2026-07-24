// 專打錯誤路徑：斷言正確 status + ok/message 語意。
// 注意：/api/scan 業務錯誤（餘額不足、查無此卡等）回 HTTP 200 + ok:false，不是 4xx——
// 只有 auth（401/403）、pydantic 驗證（422）、report 404 才是真的 HTTP 錯誤碼。
// 腳本結尾會呼叫 admin/reset 清乾淨，讓後面 soak.js 等測試接手時狀態正常。
// k6 run loadtest/error_handling.js
import http from 'k6/http';
import { check } from 'k6';
import { authedClient } from './lib/auth.js';
import { BASE_URL } from './lib/auth.js';

const data = JSON.parse(open('./lib/data.json'));

export const options = { vus: 1, iterations: 1 };

export default function () {
  const admin = authedClient(data.admin_token);
  const staff = authedClient(data.staff_tokens[0]);
  const uid = data.uids[1];

  // 1. 不存在 uid
  let r = staff.post('/api/scan', { uid: 'no-such-uid-xyz', stall_id: 'game_password', action: 'lookup' });
  check(r, {
    '不存在uid: 200': (res) => res.status === 200,
    '不存在uid: ok=false': (res) => res.json('ok') === false,
    '不存在uid: 查無此卡': (res) => res.json('message') === '查無此卡',
  });

  // 2. 餘額不足
  const lookupRes = staff.post('/api/scan', { uid, stall_id: 'game_password', action: 'lookup' });
  const balance = lookupRes.json('balance');
  r = staff.post('/api/scan', { uid, stall_id: 'game_password', action: 'debit', amount: balance + 999999 });
  check(r, {
    '餘額不足: 200': (res) => res.status === 200,
    '餘額不足: ok=false': (res) => res.json('ok') === false,
    '餘額不足: message含餘額不足': (res) => /餘額不足/.test(res.json('message') || ''),
  });

  // 3. 金額<=0
  r = staff.post('/api/scan', { uid, stall_id: 'game_password', action: 'debit', amount: -50 });
  check(r, {
    '負金額: 200': (res) => res.status === 200,
    '負金額: ok=false': (res) => res.json('ok') === false,
  });

  // 4. 沒帶 token
  r = http.post(`${BASE_URL}/api/scan`, JSON.stringify({ uid, stall_id: 'x', action: 'lookup' }), {
    headers: { 'Content-Type': 'application/json' },
  });
  check(r, { '無token: 401': (res) => res.status === 401 });

  // 5. token 錯誤
  r = http.post(`${BASE_URL}/api/scan`, JSON.stringify({ uid, stall_id: 'x', action: 'lookup' }), {
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer this-is-garbage-token' },
  });
  check(r, { '錯誤token: 401': (res) => res.status === 401 });

  // 6. staff token 打 admin 路徑
  r = staff.get('/api/admin/state');
  check(r, { 'staff打admin: 403': (res) => res.status === 403 });

  // 7. 畸形 JSON body
  r = http.post(`${BASE_URL}/api/scan`, '{not valid json', {
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${data.staff_tokens[0]}` },
  });
  check(r, { '畸形JSON: 422': (res) => res.status === 422 });

  // 8. 缺必要欄位（stall_id 缺）
  r = http.post(`${BASE_URL}/api/scan`, JSON.stringify({ uid, action: 'lookup' }), {
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${data.staff_tokens[0]}` },
  });
  check(r, { '缺欄位: 422': (res) => res.status === 422 });

  // 9. 查無此學生的 report
  r = admin.get('/api/report/no-such-uid-xyz/data');
  check(r, { 'report不存在: 404': (res) => res.status === 404 });

  // 10. guild complete 無 pending 任務
  r = staff.post('/api/guild/complete', { student_uid: uid, stall_id: 'game_password', staff_uid: 'staff-err' });
  check(r, {
    'guild無任務: 200': (res) => res.status === 200,
    'guild無任務: ok=false': (res) => res.json('ok') === false,
  });

  // 11. casino settle 不存在的 round
  r = staff.post('/api/casino/settle', { round_id: 999999999, dice: [1, 2] });
  check(r, {
    'casino不存在局: 200': (res) => res.status === 200,
    'casino不存在局: ok=false': (res) => res.json('ok') === false,
  });

  // 12. 市場關閉後仍消費
  r = admin.post('/api/admin/market_close', {});
  check(r, { '關市: ok': (res) => res.status === 200 && res.json('ok') === true });

  r = staff.post('/api/scan', { uid, stall_id: 'game_password', action: 'debit', amount: 10 });
  check(r, {
    '關市後debit: 200': (res) => res.status === 200,
    '關市後debit: ok=false': (res) => res.json('ok') === false,
    '關市後debit: message含市場已關閉': (res) => /市場已關閉/.test(res.json('message') || ''),
  });

  r = staff.post('/api/scan', { uid, stall_id: 'game_password', action: 'lookup' });
  check(r, { '關市後lookup仍可查詢: ok=true': (res) => res.status === 200 && res.json('ok') === true });

  // 收尾：全重置，讓後面測試（soak.js 等）拿到乾淨、market_open 的狀態
  r = admin.post('/api/admin/reset', {});
  check(r, { '收尾reset: ok': (res) => res.status === 200 && res.json('ok') === true });
}
