/// 後端 /api/scan 等回傳的學生狀態。對應 backend StudentState。
class PendingTask {
  final String gameKey;
  final String gameName;
  final int reward;
  final int remainingSeconds;
  PendingTask(this.gameKey, this.gameName, this.reward, this.remainingSeconds);

  factory PendingTask.fromJson(Map<String, dynamic> j) => PendingTask(
        j['game_key'] ?? '',
        j['game_name'] ?? '',
        j['reward'] ?? 0,
        j['remaining_seconds'] ?? 0,
      );
}

class StudentState {
  final String uid;
  final String studentName;
  final String group;
  final int balance;
  final int points;
  final int kingdomPoints;
  final int depositBalance;
  final String stall;
  final String action;
  final String message;
  final bool ok;
  final String? assignedGame;
  final List<PendingTask> pendingTasks;

  StudentState({
    required this.uid,
    required this.studentName,
    required this.group,
    required this.balance,
    required this.points,
    required this.kingdomPoints,
    required this.depositBalance,
    required this.stall,
    required this.action,
    required this.message,
    required this.ok,
    this.assignedGame,
    this.pendingTasks = const [],
  });

  factory StudentState.fromJson(Map<String, dynamic> j) => StudentState(
        uid: j['uid'] ?? '',
        studentName: j['student_name'] ?? '',
        group: j['group'] ?? '',
        balance: j['balance'] ?? 0,
        points: j['points'] ?? 0,
        kingdomPoints: j['kingdom_points'] ?? 0,
        depositBalance: j['deposit_balance'] ?? 0,
        stall: j['stall'] ?? '',
        action: j['action'] ?? '',
        message: j['message'] ?? '',
        ok: j['ok'] ?? false,
        assignedGame: j['assigned_game'],
        pendingTasks: ((j['pending_tasks'] ?? []) as List)
            .map((e) => PendingTask.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
