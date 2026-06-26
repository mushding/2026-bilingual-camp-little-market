"""公會抽/完成/逾時 — docs/11 B-8（single source）。

規則：
- 每「抽」一次手續費 30（以抽取次數計，不論手上任務數）。
- 最多同時持有 3 個 pending 任務；抽到上限要先完成或讓任務逾時才能再抽。
- 每個任務限時 10 分鐘；逾時未完成自動作廢並罰 −20 元。
"""
import random
from datetime import datetime, timezone

from sqlalchemy import func, select

from constants import (GAMES, GUILD_FEE, GUILD_MAX_TASKS, GUILD_POOL,
                       TASK_EXPIRE_PENALTY, TASK_TIMEOUT_MIN)
from models import GameState, GuildTask, Student
from schemas import StudentState
from services.txn import lock_student, now_iso, state_to_out, write_txn

_DIFF_ZH = {"low": "低", "mid": "中", "high": "高"}


def sweep_expired(session, s: Student, day: str) -> int:
    """掃描該生逾時的 pending 任務：作廢 + 罰 −20。回作廢數。s 已鎖。"""
    now = datetime.now(timezone.utc)
    expired = 0
    for t in session.scalars(select(GuildTask).where(
            GuildTask.uid == s.uid, GuildTask.status == "pending")):
        try:
            drawn = datetime.fromisoformat(t.drawn_at)
        except (ValueError, TypeError):
            continue
        if (now - drawn).total_seconds() >= TASK_TIMEOUT_MIN * 60:
            t.status = "expired"
            penalty = min(TASK_EXPIRE_PENALTY, max(s.balance, 0))
            s.balance -= penalty
            write_txn(session, s, "guild", "task_expired", -penalty, day,
                      {"game_key": t.game_key, "penalty": penalty})
            expired += 1
    return expired


def draw(session, s: Student, day: str) -> StudentState:
    """guild_draw：手續費 30，累加 1 個任務（上限 3，不覆蓋）。s 已鎖。"""
    pending_n = session.scalar(select(func.count()).select_from(GuildTask).where(
        GuildTask.uid == s.uid, GuildTask.status == "pending"))
    if pending_n >= GUILD_MAX_TASKS:
        return state_to_out(s, "guild", "guild_draw",
                            f"已持有 {GUILD_MAX_TASKS} 個任務，先完成再抽", ok=False)
    if s.balance < GUILD_FEE:
        return state_to_out(s, "guild", "guild_draw",
                            f"餘額不足，公會手續費 ${GUILD_FEE}", ok=False)
    s.balance -= GUILD_FEE
    game_key = random.choice(GUILD_POOL)          # uniform random
    name, difficulty, reward = GAMES[game_key]
    session.add(GuildTask(uid=s.uid, game_key=game_key, difficulty=difficulty,
                          reward=reward, status="pending", drawn_at=now_iso()))
    write_txn(session, s, "guild", "guild_draw", -GUILD_FEE, day,
              {"game_key": game_key, "reward": reward})
    return state_to_out(
        s, "guild", "guild_draw",
        f"已扣手續費 ${GUILD_FEE}　派發：{name}（{_DIFF_ZH[difficulty]}・獎勵 {reward}）"
        f"　限 {TASK_TIMEOUT_MIN} 分　手上 {pending_n + 1}/{GUILD_MAX_TASKS}",
        assigned_game=name)


def pending(session, stall_id: str) -> list[dict]:
    """GET /api/guild/pending — 只列抽到本關（game_key == stall_id）的 pending。
    順便掃描逾時（需可寫 session）。"""
    if stall_id not in GAMES:
        return []
    # 掃描本關所有 pending 學生的逾時任務
    rows = session.scalars(select(GuildTask).where(
        GuildTask.status == "pending", GuildTask.game_key == stall_id)).all()
    for t in list(rows):
        s = lock_student(session, t.uid)
        if s:
            sweep_expired(session, s, _day(session))
    # 重查（逾時的已被作廢）
    rows = session.scalars(select(GuildTask).where(
        GuildTask.status == "pending", GuildTask.game_key == stall_id)).all()
    out = []
    now = datetime.now(timezone.utc)
    for t in rows:
        st = session.get(Student, t.uid)
        try:
            drawn = datetime.fromisoformat(t.drawn_at)
            remaining = max(TASK_TIMEOUT_MIN * 60 - int((now - drawn).total_seconds()), 0)
        except (ValueError, TypeError):
            remaining = 0
        out.append({"student_uid": t.uid,
                    "student_name": st.name if st else "?",
                    "student_group": (st.group or "") if st else "",
                    "game_key": t.game_key, "reward": t.reward,
                    "remaining_seconds": remaining, "drawn_at": t.drawn_at})
    return out


def complete(session, student_uid: str, stall_id: str, staff_uid: str | None) -> StudentState:
    """POST /api/guild/complete — 固定獎勵，server 端寫死。game_key == stall_id。"""
    from services.txn import err
    if stall_id not in GAMES:
        return err(stall_id, "guild_complete", "此攤非小遊戲關")
    s = lock_student(session, student_uid)
    if s is None:
        return err(stall_id, "guild_complete", "查無此卡")
    sweep_expired(session, s, _day(session))
    task = session.scalars(select(GuildTask).where(
        GuildTask.uid == student_uid, GuildTask.status == "pending",
        GuildTask.game_key == stall_id)).first()
    if task is None:
        return state_to_out(s, stall_id, "guild_complete", "無待完成任務（或非派到本關／已逾時）", ok=False)
    task.status = "completed"
    task.completed_at = now_iso()
    task.completed_by = staff_uid
    s.balance += task.reward
    write_txn(session, s, stall_id, "guild_complete", task.reward, _day(session),
              {"game_key": stall_id, "staff_uid": staff_uid})
    return state_to_out(s, stall_id, "guild_complete",
                        f"完成 {GAMES[stall_id][0]} +${task.reward}")


def _day(session) -> str:
    return session.get(GameState, 1).current_day
