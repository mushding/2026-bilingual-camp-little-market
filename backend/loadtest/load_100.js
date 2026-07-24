// 主測試：100 VU 穩定負載，混合真實流量比例（刷卡消費為主，公會/銀行/賭場次之）。
// k6 run loadtest/load_100.js
import { check, group, sleep } from 'k6';
import { authedClient, pick } from './lib/auth.js';

const data = JSON.parse(open('./lib/data.json'));

export const options = {
  scenarios: {
    camp_traffic: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 100 },
        { duration: '3m', target: 100 },
        { duration: '20s', target: 0 },
      ],
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<800'],
  },
};

const STALLS = Object.keys({
  game_password: 0, game_moving: 0, game_basketball: 0, game_plane: 0, game_balloon: 0,
  game_charades: 0, game_memory: 0, game_color: 0, game_tangram: 0,
});

function ok(res) {
  return res.status === 200 && res.json('ok') === true;
}

export default function () {
  const uid = data.uids[__VU % data.uids.length];
  const otherUid = data.uids[(__VU + 1) % data.uids.length];
  const staff = authedClient(pick(data.staff_tokens));
  const stall = pick(STALLS);

  // 攤位刷卡消費（權重最高，模擬多數學生行為）
  group('scan', function () {
    const roll = Math.random();
    let body;
    if (roll < 0.35) {
      body = { uid, stall_id: stall, action: 'debit', amount: 1 + Math.floor(Math.random() * 100) };
    } else if (roll < 0.55) {
      body = { uid, stall_id: stall, action: 'lookup' };
    } else if (roll < 0.65) {
      body = { uid, stall_id: 'bank', action: 'deposit', amount: 50 };
    } else if (roll < 0.75) {
      body = { uid, stall_id: 'bank', action: 'withdraw', amount: 20 };
    } else if (roll < 0.85) {
      body = { uid, stall_id: 'chapel', action: 'donate', amount: 30 };
    } else if (roll < 0.93) {
      body = { uid, stall_id: 'exchange', action: 'exchange_points', tier: pick([100, 250, 400, 750]) };
    } else {
      body = { uid, stall_id: stall, action: 'guild_draw', amount: 1 };
    }
    const res = staff.post('/api/scan', body);
    check(res, { 'scan 200': (r) => r.status === 200, 'scan body ok field is bool': (r) => typeof r.json('ok') === 'boolean' });
  });

  // 銀行轉帳（低頻）
  if (Math.random() < 0.1) {
    group('bank_transfer', function () {
      const res = staff.post('/api/bank/transfer', { from_uid: uid, to_uid: otherUid, amount: 10 });
      check(res, { 'transfer 200': (r) => r.status === 200 });
    });
  }

  // 公會關主核銷（低頻，掃自己這關 pending）
  if (Math.random() < 0.15) {
    group('guild_complete', function () {
      const res = staff.post('/api/guild/complete', { student_uid: uid, stall_id: stall, staff_uid: 'staff-load' });
      check(res, { 'guild complete 200': (r) => r.status === 200 });
    });
  }

  // 賭場（低頻，開局+下注+結算）
  if (Math.random() < 0.05) {
    group('casino', function () {
      const openRes = staff.post('/api/casino/open', { table: 'dice', stall_id: 'casino_dice' });
      if (ok(openRes)) {
        const roundId = openRes.json('round_id');
        staff.post('/api/casino/bet', { round_id: roundId, uid, bet_type: pick(['big', 'small', 'seven']), amount: 20 });
        const settleRes = staff.post('/api/casino/settle', {
          round_id: roundId, dice: [1 + Math.floor(Math.random() * 6), 1 + Math.floor(Math.random() * 6)],
        });
        check(settleRes, { 'casino settle 200': (r) => r.status === 200 });
      }
    });
  }

  sleep(0.3 + Math.random() * 0.7);
}
