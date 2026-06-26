/// 後端 /api/scan 等回傳的學生狀態。對應 backend StudentState。
class StudentState {
  final String uid;
  final String studentName;
  final int balance;
  final int points;
  final int kingdomPoints;
  final int depositBalance;
  final String stall;
  final String action;
  final String message;
  final bool ok;
  final String? assignedGame;

  StudentState({
    required this.uid,
    required this.studentName,
    required this.balance,
    required this.points,
    required this.kingdomPoints,
    required this.depositBalance,
    required this.stall,
    required this.action,
    required this.message,
    required this.ok,
    this.assignedGame,
  });

  factory StudentState.fromJson(Map<String, dynamic> j) => StudentState(
        uid: j['uid'] ?? '',
        studentName: j['student_name'] ?? '',
        balance: j['balance'] ?? 0,
        points: j['points'] ?? 0,
        kingdomPoints: j['kingdom_points'] ?? 0,
        depositBalance: j['deposit_balance'] ?? 0,
        stall: j['stall'] ?? '',
        action: j['action'] ?? '',
        message: j['message'] ?? '',
        ok: j['ok'] ?? false,
        assignedGame: j['assigned_game'],
      );
}
