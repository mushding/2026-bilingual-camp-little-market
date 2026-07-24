// 競態測試：同一 uid，N 個平行請求同時扣款（金額 = 目前餘額），驗證不會雙花 / 餘額變負。
// setup() 先把目標 uid 餘額喬到固定值 TARGET_BALANCE，再讓 N 個 VU 同時各打一次
// action=debit amount=TARGET_BALANCE。理論上只有 1 個該成功，其餘應回「餘額不足」。
// k6 run loadtest/race_double_spend.js
import { check } from 'k6';
import { Counter } from 'k6/metrics';
import { authedClient } from './lib/auth.js';

const data = JSON.parse(open('./lib/data.json'));
const RACE_UID = data.uids[0];
const TARGET_BALANCE = 500;
const N_PARALLEL = 50;

const debitSuccess = new Counter('debit_success');
const debitRejected = new Counter('debit_rejected');
const debitUnexpected = new Counter('debit_unexpected');

export const options = {
  scenarios: {
    race: {
      executor: 'per-vu-iterations',
      vus: N_PARALLEL,
      iterations: 1,
      maxDuration: '30s',
    },
  },
};

export function setup() {
  const admin = authedClient(data.admin_token);
  // lookup 目前餘額
  const lookupRes = admin.post('/api/scan', { uid: RACE_UID, stall_id: 'setup', action: 'lookup' });
  const balance = lookupRes.json('balance');
  const diff = balance - TARGET_BALANCE;
  if (diff > 0) {
    admin.post('/api/scan', { uid: RACE_UID, stall_id: 'setup', action: 'debit', amount: diff });
  } else if (diff < 0) {
    admin.post('/api/scan', { uid: RACE_UID, stall_id: 'setup', action: 'credit', amount: -diff });
  }
  return { targetBalance: TARGET_BALANCE };
}

export default function () {
  const staff = authedClient(data.staff_tokens[0]);
  const res = staff.post('/api/scan', {
    uid: RACE_UID, stall_id: 'race_test', action: 'debit', amount: TARGET_BALANCE,
  });
  const body = res.json();
  if (res.status === 200 && body.ok === true) {
    debitSuccess.add(1);
  } else if (res.status === 200 && body.ok === false && /餘額不足/.test(body.message || '')) {
    debitRejected.add(1);
  } else {
    debitUnexpected.add(1);
    console.error(`unexpected response: status=${res.status} body=${res.body}`);
  }
  check(res, { 'no 5xx': (r) => r.status < 500 });
}

export function teardown(setupData) {
  const admin = authedClient(data.admin_token);
  const finalRes = admin.post('/api/scan', { uid: RACE_UID, stall_id: 'teardown', action: 'lookup' });
  const finalBalance = finalRes.json('balance');
  const noDoubleSpend = finalBalance >= 0;
  console.log(`=== race_double_spend result ===`);
  console.log(`target debit amount: ${setupData.targetBalance}, N parallel requests: ${N_PARALLEL}`);
  console.log(`final balance: ${finalBalance} (should be 0, never negative)`);
  console.log(noDoubleSpend
    ? 'PASS: 餘額非負，無雙花跡象（成功筆數要另外看 debit_success counter，理論上應=1）'
    : 'FAIL: 餘額變負！有雙花 race condition，lock_student 序列化失效');
}
