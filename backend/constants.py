"""SOT v2.0 常數 — 唯一真相源。改數字只動這裡。

v2.0 平衡（2026-06-28）：起始金升為才幹 5000/2000/1000；真實台幣物價（餐/娃娃/
飲料不縮放）；遊戲幣（Day1攤、賭場、公會、兌換、KP）對應大起始金等比上調。
"""

# 積分兌換牌價 tier -> points（500 小檔 1.0；其餘 ×10，倍率 1.0/1.2/1.25/1.33）
TIER_MAP = {500: 500, 1000: 1000, 2500: 3000, 4000: 5000, 7500: 10000}

# 公會（打工水龍頭）
GUILD_FEE = 300                 # 每「抽」一次手續費（以抽取次數計，不論手上任務數）
GUILD_MAX_TASKS = 3             # 最多同時持有 3 個 pending 任務
TASK_TIMEOUT_MIN = 10          # 每個任務限時 10 分鐘
TASK_EXPIRE_PENALTY = 0        # 逾時不另外扣錢（手續費已收），任務僅自動作廢
DIFFICULTY_REWARD = {"low": 600, "mid": 900, "high": 1300}

# 9 款小遊戲：stall_id -> (game_key, difficulty, reward)
GAMES = {
    "game_color": ("顏色分類", "low", 600),
    "game_password": ("終極密碼", "low", 600),
    "game_moving": ("搬家人工", "low", 600),
    "game_basketball": ("投籃高手", "mid", 900),
    "game_plane": ("丟紙飛機", "mid", 900),
    "game_balloon": ("拍氣球", "mid", 900),
    "game_charades": ("比手畫腳", "mid", 900),
    "game_memory": ("記憶翻牌", "mid", 900),
    "game_tangram": ("七巧板", "high", 1300),
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
MAIL_KP = 200

# 天國點數（二三天同一套算法：無 D3 bonus、無回應卡）
WITNESS_KP = 1000

# 賭場桌限
BET_MIN, BET_MAX = 50, 500
DICE_PAYOUT = {"big": 2, "small": 2, "seven": 5}  # 命中 balance += amount × payout（含退本金）

# 起始金（才幹 5/2/1，非隨機：每組固定 1 人 5000、2 人 1000、其餘 2000）
SEED_OPTIONS = {5000, 2000, 1000}
