// 階梯式拉高 RPS，找 SQLite 寫鎖序列化 / uvicorn 單 process 的斷點。
// k6 run loadtest/stress.js
import { check } from 'k6';
import { authedClient, pick } from './lib/auth.js';

const data = JSON.parse(open('./lib/data.json'));

export const options = {
  scenarios: {
    stress: {
      executor: 'ramping-arrival-rate',
      startRate: 10,
      timeUnit: '1s',
      preAllocatedVUs: 50,
      maxVUs: 500,
      stages: [
        { target: 20, duration: '30s' },
        { target: 50, duration: '30s' },
        { target: 100, duration: '30s' },
        { target: 200, duration: '30s' },
        { target: 400, duration: '30s' },
        { target: 0, duration: '10s' },
      ],
    },
  },
  thresholds: {
    // 不設 abortOnFail，讓它跑完全部階段，最後看哪一階開始壞
    http_req_duration: ['p(95)<2000'],
  },
};

export default function () {
  const uid = pick(data.uids);
  const staff = authedClient(pick(data.staff_tokens));
  const res = staff.post('/api/scan', { uid, stall_id: 'game_password', action: 'debit', amount: 1 });
  check(res, { '200': (r) => r.status === 200 });
}
