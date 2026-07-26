"""SOT v2.3 常數 — 唯一真相源。改數字只動這裡。

v2.3 企劃對齊（2026-07-20）：依 2026FY 小市集企劃書（07-19 版）數值為準。
公會改版：免手續費、學生一次指定抽 N 個不重複任務（上限＝9 款整池，扣掉
手上已持有的）、逾時改扣 100 元（原本不扣，因為手續費已收；現在免手續費
改用逾時罰款當唯一嚇阻）。銀行轉帳新增：轉出方（A）金額 1:1 轉天國點數。
詳見 docs/CHANGELOG.md v2.3。
"""

# 積分兌換牌價 tier -> points（倍率 1.0/1.2/1.25/1.33）
TIER_MAP = {100: 100, 250: 300, 400: 500, 750: 1000}

# 公會（打工水龍頭）
GUILD_FEE = 0                    # 免手續費（v2.3：學生指定抽幾個，關主輸入數字，一次派 N 個不重複任務）
TASK_TIMEOUT_MIN = 15           # 每個任務限時 15 分鐘（試玩後從 8 調長，減少誤逾時）
TASK_EXPIRE_PENALTY = 100       # 逾時扣 100（免手續費後，逾時罰款是唯一嚇阻）
DIFFICULTY_REWARD = {"low": 30, "mid": 60, "high": 100}

# 9 款小遊戲：stall_id -> (game_key, difficulty, reward)（低2/中5/高2）
GAMES = {
    "game_password": ("終極密碼", "low", 30),
    "game_moving": ("搬家人工", "low", 30),
    "game_basketball": ("投籃高手", "mid", 60),
    "game_plane": ("丟紙飛機", "mid", 60),
    "game_balloon": ("拍氣球", "mid", 60),
    "game_charades": ("比手畫腳", "mid", 60),
    "game_memory": ("記憶翻牌", "mid", 60),
    "game_color": ("顏色分類", "high", 100),
    "game_tangram": ("七巧板", "high", 100),
}
# 公會抽取池（均勻隨機）= 上 9 個 game_key
GUILD_POOL = list(GAMES.keys())
# game_key -> stall_id（pending 反查用）
GAME_KEY_TO_STALL = {v[0]: k for k, v in GAMES.items()}

# 銀行
DEPOSIT_RATE = 0.2          # 20%/天，複利
MAX_SETTLEMENTS = 3
MARKET_CLOSE_RATE = 0.1     # 未兌換現金 + 定存本利 ×0.1

# 餐費（真實台幣物價，不隨遊戲幣縮放）
MEAL_DEFAULT = 150
MEAL_MIN, MEAL_MAX = 100, 250

# 感謝卡（郵政核銷，加給寄件人）— 不限張數
MAIL_KP = 100

# 天國點數（二三天同一套算法：無 D3 bonus、無回應卡）
WITNESS_KP = 100

# 賭場桌限
BET_MIN, BET_MAX = 10, 100
DICE_PAYOUT = {"big": 2, "small": 2, "seven": 5}  # 命中 balance += amount × payout（含退本金）

# Day1 賣娃娃固定三檔
DOLL_PRICES = {"大": 1000, "中": 500, "小": 300}

# 起始金（才幹 5/2/1，非隨機：每組固定 1 人 5000、1 人 1000、其餘全部 2000）
SEED_OPTIONS = {5000, 2000, 1000}
