// 瞬間尖峰：模擬「開市」那一刻全場衝去刷卡。0 -> 150 VU 幾乎瞬間，撐 10s，退。
// k6 run loadtest/spike.js
import { check } from 'k6';
import { authedClient, pick } from './lib/auth.js';

const data = JSON.parse(open('./lib/data.json'));

export const options = {
  scenarios: {
    market_open_rush: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '5s', target: 150 },
        { duration: '10s', target: 150 },
        { duration: '5s', target: 0 },
      ],
    },
  },
};

export default function () {
  const uid = data.uids[__VU % data.uids.length];
  const staff = authedClient(pick(data.staff_tokens));
  const res = staff.post('/api/scan', { uid, stall_id: 'game_password', action: 'lookup' });
  check(res, {
    '200 (非逾時/被拒)': (r) => r.status === 200,
    'no 5xx': (r) => r.status < 500,
  });
}
