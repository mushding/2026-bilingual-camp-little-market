// 1 VU 跑一輪全部 endpoint，確認腳本本身沒寫錯、seed 資料對得起來。
// k6 run loadtest/smoke.js
import { check, sleep } from 'k6';
import { authedClient, pick } from './lib/auth.js';

const data = JSON.parse(open('./lib/data.json'));

export const options = { vus: 1, iterations: 1 };

export default function () {
  const admin = authedClient(data.admin_token);
  const staff = authedClient(pick(data.staff_tokens));
  const uid = pick(data.uids);
  const uid2 = data.uids.find((u) => u !== uid);

  let r = admin.get('/health');
  check(r, { 'health 200': (res) => res.status === 200 });

  r = admin.get('/api/state');
  check(r, { 'state 200': (res) => res.status === 200 });

  r = staff.post('/api/scan', { uid, stall_id: 'lookup', action: 'lookup' });
  check(r, { 'lookup 200 ok': (res) => res.status === 200 && res.json('ok') === true });

  r = staff.post('/api/scan', { uid, stall_id: 'game_password', action: 'debit', amount: 50 });
  check(r, { 'debit 200 ok': (res) => res.status === 200 && res.json('ok') === true });

  r = staff.post('/api/scan', { uid, stall_id: 'bank', action: 'credit', amount: 50 });
  check(r, { 'credit 200 ok': (res) => res.status === 200 && res.json('ok') === true });

  r = staff.post('/api/scan', { uid, stall_id: 'bank', action: 'deposit', amount: 100 });
  check(r, { 'deposit 200 ok': (res) => res.status === 200 && res.json('ok') === true });

  r = staff.post('/api/scan', { uid, stall_id: 'bank', action: 'withdraw', amount: 100 });
  check(r, { 'withdraw 200 ok': (res) => res.status === 200 && res.json('ok') === true });

  r = staff.post('/api/scan', { uid, stall_id: 'chapel', action: 'donate', amount: 50 });
  check(r, { 'donate 200 ok': (res) => res.status === 200 && res.json('ok') === true });

  r = staff.post('/api/scan', { uid, stall_id: 'exchange', action: 'exchange_points', tier: 100 });
  check(r, { 'exchange 200 ok': (res) => res.status === 200 && res.json('ok') === true });

  r = staff.post('/api/scan', { uid, stall_id: 'mail', action: 'mail_kp', cards: 1 });
  check(r, { 'mail_kp 200 ok': (res) => res.status === 200 && res.json('ok') === true });

  r = staff.post('/api/scan', {
    uid, stall_id: 'guild', action: 'credit_kp', staff_uid: 'staff-smoke-1',
  });
  check(r, { 'credit_kp 200 ok': (res) => res.status === 200 && res.json('ok') === true });

  r = staff.post('/api/bank/transfer', { from_uid: uid, to_uid: uid2, amount: 20 });
  check(r, { 'transfer 200 ok': (res) => res.status === 200 && res.json('ok') === true });

  r = staff.post('/api/scan', {
    uid, stall_id: 'game_password', action: 'guild_draw', amount: 1,
  });
  check(r, { 'guild_draw 200 ok': (res) => res.status === 200 && res.json('ok') === true });
  const drawnGameKey = r.json('pending_tasks.0.game_key'); // draw 是全池隨機，不一定等於下籤的 stall_id

  r = staff.get(`/api/guild/pending?stall_id=${drawnGameKey}`);
  check(r, { 'guild pending 200': (res) => res.status === 200 });

  r = staff.post('/api/guild/complete', { student_uid: uid, stall_id: drawnGameKey, staff_uid: 'staff-smoke-1' });
  check(r, { 'guild complete 200 ok': (res) => res.status === 200 && res.json('ok') === true });

  r = staff.post('/api/casino/open', { table: 'dice', stall_id: 'casino_dice' });
  check(r, { 'casino open 200 ok': (res) => res.status === 200 && res.json('ok') === true });
  const roundId = r.json('round_id');

  r = staff.post('/api/casino/bet', { round_id: roundId, uid, bet_type: 'big', amount: 20 });
  check(r, { 'casino bet 200 ok': (res) => res.status === 200 && res.json('ok') === true });

  r = staff.post('/api/casino/settle', { round_id: roundId, dice: [5, 6] });
  check(r, { 'casino settle 200 ok': (res) => res.status === 200 && res.json('ok') === true });

  r = staff.get(`/api/casino/round/${roundId}`);
  check(r, { 'casino round 200 ok': (res) => res.status === 200 && res.json('ok') === true });

  r = admin.get('/api/admin/state');
  check(r, { 'admin state 200': (res) => res.status === 200 });

  r = admin.get('/api/admin/dashboard');
  check(r, { 'admin dashboard 200': (res) => res.status === 200 });

  r = admin.get(`/api/report/${uid}/data`);
  check(r, { 'report 200': (res) => res.status === 200 });

  sleep(0.1);
}
