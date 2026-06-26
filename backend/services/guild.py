"""公會抽/完成 — docs/app/31 §3。"""
import random

from sqlalchemy import select

from constants import GAMES, GUILD_FEE, GUILD_POOL
from models import GameState, GuildTask, Student
from schemas import StudentState
from services.txn import lock_student, now_iso, state_to_out, write_txn


def draw(session, s: Student, day: str) -> StudentState:
    """guild_draw：扣 30，舊 pending 轉 superseded，隨機派 1 款。s 已鎖。"""
    if s.balance < GUILD_FEE:
        return state_to_out(s, "guild", "guild_draw",
                            f"餘額不足，公會手續費 ${GUILD_FEE}", ok=False)
    s.balance -= GUILD_FEE
    # 舊 pending → superseded
    for t in session.scalars(select(GuildTask).where(
            GuildTask.uid == s.uid, GuildTask.status == "pending")):
        t.status = "superseded"
    game_key = random.choice(GUILD_POOL)          # uniform random
    name, difficulty, reward = GAMES[game_key]
    session.add(GuildTask(uid=s.uid, game_key=game_key, difficulty=difficulty,
                          reward=reward, status="pending", drawn_at=now_iso()))
    write_txn(session, s, "guild", "guild_draw", -GUILD_FEE, day,
              {"game_key": game_key, "reward": reward})
    diff_zh = {"low": "低", "mid": "中", "high": "高"}[difficulty]
    return state_to_out(s, "guild", "guild_draw",
                        f"派發任務：{name}（{diff_zh}・獎勵 {reward}）",
                        assigned_game=name)


def pending(session, stall_id: str) -> list[dict]:
    """GET /api/guild/pending — 只列該攤對應 game_key 的 pending。"""
    from constants import GAMES as _G
    if stall_id not in _G:
        return []
    game_key = _G[stall_id][0]
    rows = session.scalars(select(GuildTask).where(
        GuildTask.status == "pending", GuildTask.game_key == game_key)).all()
    out = []
    for t in rows:
        st = session.get(Student, t.uid)
        out.append({"student_uid": t.uid,
                    "student_name": st.name if st else "?",
                    "game_key": t.game_key, "drawn_at": t.drawn_at})
    return out


def complete(session, student_uid: str, stall_id: str, staff_uid: str | None) -> StudentState:
    """POST /api/guild/complete — 固定獎勵，server 端寫死。"""
    from constants import GAMES as _G
    if stall_id not in _G:
        return state_to_out_safe(student_uid, stall_id, "此攤非小遊戲關")
    game_key = _G[stall_id][0]
    s = lock_student(session, student_uid)
    if s is None:
        from services.txn import err
        return err(stall_id, "guild_complete", "查無此卡")
    task = session.scalars(select(GuildTask).where(
        GuildTask.uid == student_uid, GuildTask.status == "pending",
        GuildTask.game_key == game_key)).first()
    if task is None:
        return state_to_out(s, stall_id, "guild_complete", "無待完成任務（或非派到本關）", ok=False)
    task.status = "completed"
    task.completed_at = now_iso()
    task.completed_by = staff_uid
    s.balance += task.reward
    day = session.get(GameState, 1).current_day
    write_txn(session, s, stall_id, "guild_complete", task.reward, day,
              {"game_key": game_key, "staff_uid": staff_uid})
    return state_to_out(s, stall_id, "guild_complete", f"完成任務 +${task.reward}")


def state_to_out_safe(uid, stall, msg):
    from services.txn import err
    return err(stall, "guild_complete", msg)
