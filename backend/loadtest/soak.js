// 100 VU 撐 20 分鐘，看 http_req_duration 有沒有隨時間漂移（鎖等待累積 / WAL 檔案膨脹）。
// 建議搭配另開 terminal `watch -n5 ls -lh loadtest.db*` 觀察 WAL 檔大小。
// k6 run loadtest/soak.js
import { check, sleep } from 'k6';
import { authedClient, pick } from './lib/auth.js';

const data = JSON.parse(open('./lib/data.json'));

export const options = {
  scenarios: {
    soak: {
      executor: 'constant-vus',
      vus: 100,
      duration: '20m',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
  },
};

export default function () {
  const uid = data.uids[__VU % data.uids.length];
  const staff = authedClient(pick(data.staff_tokens));
  const roll = Math.random();
  let body;
  if (roll < 0.5) {
    body = { uid, stall_id: 'game_password', action: 'debit', amount: 5 };
  } else if (roll < 0.7) {
    body = { uid, stall_id: 'bank', action: 'credit', amount: 5 };
  } else {
    body = { uid, stall_id: 'game_password', action: 'lookup' };
  }
  const res = staff.post('/api/scan', body);
  check(res, { '200': (r) => r.status === 200 });
  sleep(1 + Math.random());
}
