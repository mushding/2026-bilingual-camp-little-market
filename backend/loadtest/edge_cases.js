// 模擬關主/學員現場會發生的各種手忙腳亂情況：狂按重掃、掃到一半放棄、兩關主搶同一學生、
// 賭場取消跟結算對撞、公會任務忘記回來核銷（逾時罰款）、token 被撤銷後還在用、
// 亂打的畸形/惡意輸入等。每個情境是獨立 k6 scenario，互不干擾（各用各的 uid）。
//
// 前置：需要先跑過 loadtest/inject_expired_task.py（注入一個「9分鐘前抽的任務」），
// 否則 expired_task_sweep 場景會印警告並跳過斷言。
//
// k6 run loadtest/edge_cases.js
import http from 'k6/http';
import { check, sleep } from 'k6';
import { authedClient, BASE_URL } from './lib/auth.js';

const data = JSON.parse(open('./lib/data.json'));
const admin = authedClient(data.admin_token);
const staff = authedClient(data.staff_tokens[0]);

// 各情境專用 uid，避免互相干擾（跟 load_100 用的池分開一段）
const UID_MASH = data.uids[50];
const UID_GUILD_RACE = data.uids[51];
const UID_CASINO_RACE = data.uids[52];
const UID_TRANSFER_A = data.uids[53];
const UID_TRANSFER_B = data.uids[54];
const UID_POOL_EXHAUST = data.uids[55];
const UID_WITNESS = data.uids[56];
const UID_DEADLOCK_A = data.uids[57];
const UID_DEADLOCK_B = data.uids[58];
const UID_BETSETTLE = data.uids[59];
const UID_DOUBLESETTLE = data.uids[60];
const UID_BETSETTLE_LATE = data.uids[61]; // 跟 setup 下注的人不同，避免撞到「已在桌上」的dup-bet檢查蓋掉真正想測的東西

export const options = {
  scenarios: {
    mash_debit: {
      executor: 'shared-iterations', vus: 1, iterations: 1, exec: 'mashDebit',
    },
    guild_complete_race: {
      executor: 'per-vu-iterations', vus: 2, iterations: 1, exec: 'guildCompleteRace',
      startTime: '1s',
    },
    casino_cancel_vs_settle: {
      executor: 'per-vu-iterations', vus: 2, iterations: 1, exec: 'casinoCancelVsSettle',
      startTime: '1s',
    },
    transfer_edges: {
      executor: 'shared-iterations', vus: 1, iterations: 1, exec: 'transferEdges',
    },
    guild_pool_exhaustion: {
      executor: 'shared-iterations', vus: 1, iterations: 1, exec: 'guildPoolExhaustion',
    },
    duplicate_witness: {
      executor: 'shared-iterations', vus: 1, iterations: 1, exec: 'duplicateWitness',
    },
    revoked_token_flow: {
      executor: 'shared-iterations', vus: 1, iterations: 1, exec: 'revokedTokenFlow',
    },
    weird_input_probe: {
      executor: 'shared-iterations', vus: 1, iterations: 1, exec: 'weirdInputProbe',
    },
    expired_task_sweep: {
      executor: 'shared-iterations', vus: 1, iterations: 1, exec: 'expiredTaskSweep',
      startTime: '2s',
    },
    transfer_deadlock_check: {
      executor: 'per-vu-iterations', vus: 2, iterations: 10, exec: 'transferDeadlockCheck',
      startTime: '3s', maxDuration: '30s',
    },
    bet_vs_settle_race: {
      executor: 'per-vu-iterations', vus: 2, iterations: 1, exec: 'betVsSettleRace',
      startTime: '4s',
    },
    double_settle_race: {
      executor: 'per-vu-iterations', vus: 2, iterations: 1, exec: 'doubleSettleRace',
      startTime: '5s',
    },
  },
};

// setup() 只跑一次（主 VU context），回傳值會傳給每個場景的 exec function 當第一參數。
// 賭場對戰情境的 round_id 必須在這裡準備好，因為 k6 的 VU 之間不共享記憶體。
export function setup() {
  const openDice = () => admin.post('/api/casino/open', { table: 'dice', stall_id: 'casino_dice' }).json('round_id');

  const cancelSettleRoundId = openDice();
  admin.post('/api/casino/bet', { round_id: cancelSettleRoundId, uid: UID_CASINO_RACE, bet_type: 'big', amount: 50 });

  const betSettleRoundId = openDice();
  admin.post('/api/casino/bet', { round_id: betSettleRoundId, uid: UID_BETSETTLE, bet_type: 'big', amount: 30 });

  const doubleSettleRoundId = openDice();
  admin.post('/api/casino/bet', { round_id: doubleSettleRoundId, uid: UID_DOUBLESETTLE, bet_type: 'seven', amount: 20 });

  // guild_draw 是全池隨機（不看 stall_id 抽到哪關），先在這裡抽好、把實際抽到的
  // game_key 傳給兩個 VU，兩邊才會搶同一個真的存在的任務，而不是各猜各的關卡。
  const drawRes = staff.post('/api/scan', { uid: UID_GUILD_RACE, stall_id: 'x', action: 'guild_draw', amount: 1 });
  const guildRaceGameKey = drawRes.json('pending_tasks.0.game_key');

  return { cancelSettleRoundId, betSettleRoundId, doubleSettleRoundId, guildRaceGameKey };
}

// ── 情境1：狂按重掃（同一張卡連續掃 5 次同一動作，不等回應心態）──────────────
// 現實：關主手滑連掃、或學員把卡在感應區來回摩。系統無 idempotency key，
// 每次掃描 = 一筆真交易，預期就是扣 5 次錢（非 bug，但要讓帶隊教練知道）。
export function mashDebit() {
  const lookupRes = staff.post('/api/scan', { uid: UID_MASH, stall_id: 'game_password', action: 'lookup' });
  const before = lookupRes.json('balance');
  const N = 5;
  const results = [];
  for (let i = 0; i < N; i++) {
    results.push(staff.post('/api/scan', { uid: UID_MASH, stall_id: 'game_password', action: 'debit', amount: 30 }));
  }
  const successes = results.filter((r) => r.json('ok') === true).length;
  const afterRes = staff.post('/api/scan', { uid: UID_MASH, stall_id: 'game_password', action: 'lookup' });
  const after = afterRes.json('balance');
  check(null, {
    '狂按重掃: 5次都拿到200': () => results.every((r) => r.status === 200),
    '狂按重掃: 扣款次數=請求次數(無idempotency，預期行為)': () => successes === N,
    '狂按重掃: 餘額精準扣N筆': () => before - after === successes * 30,
  });
  console.log(`[mash_debit] before=${before} after=${after} successes=${successes}/${N} (無防重掃機制，關主手滑會真的扣多次)`);
}

// ── 情境2：兩個關主同時對同一學生按「完成任務」（搶功）───────────────────────
// 抽任務已在 setup() 做好（guild_draw 全池隨機，兩個 VU 必須用同一個抽到的 game_key
// 才會真的搶到同一個任務）。
export function guildCompleteRace(setupData) {
  const gameKey = setupData.guildRaceGameKey;
  const res = staff.post('/api/guild/complete', {
    student_uid: UID_GUILD_RACE, stall_id: gameKey, staff_uid: `race-staff-${__VU}`,
  });
  check(res, { '搶完成任務: 200': (r) => r.status === 200 });
  console.log(`[guild_complete_race] VU${__VU} ok=${res.json('ok')} message=${res.json('message')}`);
}

// ── 情境3：賭場下注後，取消跟結算同時發生（關主跟學員步調沒對齊）───────────────
// 注意：k6 每個 VU 是獨立 JS runtime，不共享記憶體，round_id 必須靠 setup() 傳遞，
// 不能像單純腳本那樣用模組層變數在 VU 間傳（那樣 VU2 讀到的永遠是 undefined）。
export function casinoCancelVsSettle(setupData) {
  const roundId = setupData.cancelSettleRoundId;
  sleep(0.3);
  if (__VU % 2 === 1) {
    const res = admin.post('/api/casino/cancel', { round_id: roundId, uid: UID_CASINO_RACE });
    console.log(`[casino_race] VU1 cancel -> ok=${res.json('ok')} message=${res.json('message')}`);
  } else {
    const res = admin.post('/api/casino/settle', { round_id: roundId, dice: [3, 4] });
    console.log(`[casino_race] VU2 settle -> ok=${res.json('ok')} message=${res.json('message')}`);
  }
}

// ── 情境4：銀行轉帳邊界輸入（轉給自己、轉給不存在的人、金額 0/負數）────────────
export function transferEdges() {
  let r = staff.post('/api/bank/transfer', { from_uid: UID_TRANSFER_A, to_uid: UID_TRANSFER_A, amount: 10 });
  check(r, { '轉給自己: ok=false': (res) => res.status === 200 && res.json('ok') === false });

  r = staff.post('/api/bank/transfer', { from_uid: UID_TRANSFER_A, to_uid: 'no-such-uid', amount: 10 });
  check(r, { '轉給不存在uid: ok=false': (res) => res.status === 200 && res.json('ok') === false });

  r = staff.post('/api/bank/transfer', { from_uid: UID_TRANSFER_A, to_uid: UID_TRANSFER_B, amount: 0 });
  check(r, { '轉帳金額0: ok=false': (res) => res.status === 200 && res.json('ok') === false });

  r = staff.post('/api/bank/transfer', { from_uid: UID_TRANSFER_A, to_uid: UID_TRANSFER_B, amount: -100 });
  check(r, { '轉帳負金額: ok=false': (res) => res.status === 200 && res.json('ok') === false });

  // 沒掃完整：漏帶 amount 欄位（TransferReq 沒有 default，該 422）
  r = http.post(`${BASE_URL}/api/bank/transfer`, JSON.stringify({ from_uid: UID_TRANSFER_A, to_uid: UID_TRANSFER_B }), {
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${data.staff_tokens[0]}` },
  });
  check(r, { '轉帳漏欄位: 422': (res) => res.status === 422 });

  // 模擬網路重試：同一筆轉帳因為沒收到回應被前端重送一次（伺服器其實有處理）
  const before = staff.post('/api/scan', { uid: UID_TRANSFER_A, stall_id: 'x', action: 'lookup' }).json('balance');
  staff.post('/api/bank/transfer', { from_uid: UID_TRANSFER_A, to_uid: UID_TRANSFER_B, amount: 15 });
  const retryRes = staff.post('/api/bank/transfer', { from_uid: UID_TRANSFER_A, to_uid: UID_TRANSFER_B, amount: 15 });
  const after = staff.post('/api/scan', { uid: UID_TRANSFER_A, stall_id: 'x', action: 'lookup' }).json('balance');
  console.log(`[transfer_retry] 重送兩次相同轉帳: 第二次ok=${retryRes.json('ok')}，餘額前${before}後${after}（差=${before - after}，無idempotency故會真的轉兩次）`);
}

// ── 情境5：公會抽取池耗盡（學員一次要抽超過剩餘可抽的關卡數）────────────────
export function guildPoolExhaustion() {
  let r = staff.post('/api/scan', { uid: UID_POOL_EXHAUST, stall_id: 'game_password', action: 'guild_draw', amount: 15 });
  check(r, {
    '一次抽超過整池9個: ok=false': (res) => res.status === 200 && res.json('ok') === false,
  });
  r = staff.post('/api/scan', { uid: UID_POOL_EXHAUST, stall_id: 'game_password', action: 'guild_draw', amount: 5 });
  check(r, { '先抽5個: ok=true': (res) => res.status === 200 && res.json('ok') === true });
  r = staff.post('/api/scan', { uid: UID_POOL_EXHAUST, stall_id: 'game_password', action: 'guild_draw', amount: 5 });
  check(r, {
    '手上已持有5個再抽5個(剩4): ok=false': (res) => res.status === 200 && res.json('ok') === false,
    '訊息告知剩餘可抽數': (res) => /最多還能抽/.test(res.json('message') || ''),
  });
}

// ── 情境6：同一個關主對同一學生重複給「聽見證」點數（去重機制）─────────────────
export function duplicateWitness() {
  const staffUid = 'witness-staff-1';
  let r = staff.post('/api/scan', { uid: UID_WITNESS, stall_id: 'chapel', action: 'credit_kp', staff_uid: staffUid });
  check(r, { '第一次給見證點數: ok=true': (res) => res.status === 200 && res.json('ok') === true });
  r = staff.post('/api/scan', { uid: UID_WITNESS, stall_id: 'chapel', action: 'credit_kp', staff_uid: staffUid });
  check(r, {
    '同一關主重複給: ok=false去重': (res) => res.status === 200 && res.json('ok') === false,
    '去重訊息正確': (res) => /此同工已給過/.test(res.json('message') || ''),
  });
  // 換一個關主給同一學生 → 應該可以再給一次
  r = staff.post('/api/scan', { uid: UID_WITNESS, stall_id: 'chapel', action: 'credit_kp', staff_uid: 'witness-staff-2' });
  check(r, { '換關主再給: ok=true': (res) => res.status === 200 && res.json('ok') === true });
}

// ── 情境7：裝置 token 中途被總控撤銷（手機遺失現場處理），撤銷後應立即失效 ──────
export function revokedTokenFlow() {
  const enrollRes = http.post(`${BASE_URL}/api/auth/enroll`, JSON.stringify({ code: 'dev-staff-code', label: 'edge-case-temp' }), {
    headers: { 'Content-Type': 'application/json' },
  });
  check(enrollRes, { 'enroll臨時裝置: 200': (r) => r.status === 200 && r.json('ok') === true });
  const tempToken = enrollRes.json('token');
  const tempClient = authedClient(tempToken);

  let r = tempClient.post('/api/scan', { uid: UID_MASH, stall_id: 'x', action: 'lookup' });
  check(r, { '撤銷前可正常用: 200 ok': (res) => res.status === 200 && res.json('ok') === true });

  r = admin.post('/api/admin/revoke', { token: tempToken });
  check(r, { '撤銷成功': (res) => res.status === 200 && res.json('ok') === true });

  r = tempClient.post('/api/scan', { uid: UID_MASH, stall_id: 'x', action: 'lookup' });
  check(r, { '撤銷後立即401': (res) => res.status === 401 });
}

// ── 情境8：亂七八糟的輸入（超長字串、特殊符號、SQL injection式字串、空字串）─────
export function weirdInputProbe() {
  const weirdUids = [
    '', ' ', 'a'.repeat(5000), "' OR '1'='1", '<script>alert(1)</script>',
    ' ', '😀🎉🍔', 'stu001; DROP TABLE students;--',
  ];
  for (const uid of weirdUids) {
    const r = staff.post('/api/scan', { uid, stall_id: 'game_password', action: 'lookup' });
    check(r, {
      [`怪uid「${uid.slice(0, 20)}」不會5xx`]: (res) => res.status < 500,
      [`怪uid「${uid.slice(0, 20)}」回查無此卡`]: (res) => res.status === 200 && res.json('ok') === false,
    });
  }

  // 極大金額（int 不會 overflow，但要確定不會被誤判有錢）
  let r = staff.post('/api/scan', { uid: UID_WITNESS, stall_id: 'game_password', action: 'debit', amount: 999999999999 });
  check(r, { '極大金額debit: ok=false餘額不足': (res) => res.status === 200 && res.json('ok') === false });

  // tier 不在合法檔位
  r = staff.post('/api/scan', { uid: UID_WITNESS, stall_id: 'exchange', action: 'exchange_points', tier: 999 });
  check(r, { '非法兌換檔位: ok=false': (res) => res.status === 200 && res.json('ok') === false });

  // action 打錯字（未知 action，schema 允許任意字串，handle_scan 沒有對應分支）
  r = staff.post('/api/scan', { uid: UID_WITNESS, stall_id: 'game_password', action: 'not_a_real_action' });
  check(r, {
    '未知action不會5xx': (res) => res.status < 500,
  });
  console.log(`[weird_input] 未知action回應: status=${r.status} body=${r.body}`);
}

// ── 情境10：A⇄B 同時互轉（驗證 sorted() 上鎖真的防到 deadlock，不是碰運氣沒撞上）──
export function transferDeadlockCheck() {
  const [from, to] = __VU === 1 ? [UID_DEADLOCK_A, UID_DEADLOCK_B] : [UID_DEADLOCK_B, UID_DEADLOCK_A];
  const res = staff.post('/api/bank/transfer', { from_uid: from, to_uid: to, amount: 5 });
  check(res, {
    '互轉不逾時不5xx': (r) => r.status < 500,
    '互轉200': (r) => r.status === 200,
  });
}

// ── 情境11：下注途中另一邊已經 settle 完，晚到的 bet 有沒有被擋住？───────────────
// 風險：casino.bet() 檢查 round.status=='open' 在鎖學生之前，settle() 若在檢查後、
// 寫入前插隊完成，這筆 bet 可能「扣了款但沒被納入結算」變孤兒注單。
export function betVsSettleRace(setupData) {
  const roundId = setupData.betSettleRoundId;
  if (__VU % 2 === 1) {
    const res = admin.post('/api/casino/settle', { round_id: roundId, dice: [5, 6] });
    console.log(`[bet_vs_settle] VU1 settle -> ok=${res.json('ok')}`);
  } else {
    sleep(0.02); // 故意晚一點點，卡在「已開局但可能剛被settle」的窗口
    const res = admin.post('/api/casino/bet', { round_id: roundId, uid: UID_BETSETTLE_LATE, bet_type: 'small', amount: 30 });
    const late = res.json('ok') === true;
    console.log(`[bet_vs_settle] VU2 晚到的bet -> ok=${res.json('ok')} message=${res.json('message')}`
      + (late ? '　⚠️ 晚到的bet成功了，需人工確認這筆有沒有被結算納入，還是變孤兒注單' : '　OK：正確被擋'));
    check(res, { '晚到的bet不會5xx': (r) => r.status < 500 });
  }
}

// ── 情境12：同一個 round 被兩個關主同時按下「結算」（雙重派彩風險）─────────────
export function doubleSettleRace(setupData) {
  const roundId = setupData.doubleSettleRoundId;
  sleep(0.05);
  const res = admin.post('/api/casino/settle', { round_id: roundId, dice: [3, 4] });
  check(res, { '結算不會5xx': (r) => r.status < 500 });
  console.log(`[double_settle] VU${__VU} settle -> ok=${res.json('ok')} message=${res.json('message')}`);
}

// ── 情境9：學員抽了公會任務、玩到一半忘記回來核銷 → 逾時掃描應自動扣罰款 ────────
// 需先跑 loadtest/inject_expired_task.py 注入一個「9分鐘前抽的」任務。
export function expiredTaskSweep() {
  const uid = data.expired_task_uid;
  if (!uid) {
    console.warn('[expired_task_sweep] 跳過：沒找到 expired_task_uid，請先跑 python loadtest/inject_expired_task.py');
    return;
  }
  const beforeRes = staff.post('/api/scan', { uid, stall_id: 'z_trigger_sweep', action: 'lookup' });
  const balance = beforeRes.json('balance');
  const stillPending = (beforeRes.json('pending_tasks') || []).some((t) => t.game_key === data.expired_task_game_key);
  check(beforeRes, {
    '逾時任務已被掃描作廢(不再列在pending)': () => stillPending === false,
  });
  console.log(`[expired_task_sweep] uid=${uid} balance=${balance}（應已被扣${100}逾時罰款）pending剩=${JSON.stringify(beforeRes.json('pending_tasks'))}`);
}
