"""SOT v1.0 常數 — 唯一真相源。改數字只動這裡。"""

# 積分兌換牌價 tier -> points
TIER_MAP = {100: 100, 250: 300, 400: 500, 800: 1000}

# 公會
GUILD_FEE = 30
DIFFICULTY_REWARD = {"low": 60, "mid": 90, "high": 130}

# 9 款小遊戲：stall_id -> (game_key, difficulty, reward)
GAMES = {
    "game_color": ("顏色分類", "low", 60),
    "game_password": ("終極密碼", "low", 60),
    "game_moving": ("搬家人工", "low", 60),
    "game_basketball": ("投籃高手", "mid", 90),
    "game_plane": ("丟紙飛機", "mid", 90),
    "game_balloon": ("拍氣球", "mid", 90),
    "game_charades": ("比手畫腳", "mid", 90),
    "game_memory": ("記憶翻牌", "mid", 90),
    "game_tangram": ("七巧板", "high", 130),
}
# 公會抽取池（均勻隨機）= 上 9 個 game_key
GUILD_POOL = list(GAMES.keys())
# game_key -> stall_id（pending 反查用）
GAME_KEY_TO_STALL = {v[0]: k for k, v in GAMES.items()}

# 銀行
DEPOSIT_RATE = 0.2          # 20%/天，複利
MAX_SETTLEMENTS = 3
MARKET_CLOSE_RATE = 0.1     # 未兌換現金 + 定存本利 ×0.1

# 餐費
MEAL_DEFAULT = 150
MEAL_MIN, MEAL_MAX = 100, 250

# 感謝卡（郵政核銷，加給寄件人）
MAIL_KP = 20
MAIL_CARD_CAP = 3           # 每寄件人封頂 3 張 = 60 KP

# 天國點數
WITNESS_KP = 100
DONATE_D3_BONUS = 50        # D3 奉獻 ≥100 額外
DONATE_D3_BONUS_MIN = 100
RESPONSE_CARD_KP = 200

# 賭場桌限
BET_MIN, BET_MAX = 10, 100
DICE_PAYOUT = {"big": 2, "small": 2, "seven": 5}  # 命中 balance += amount × payout（含退本金）

# 起始金（抽籤）
SEED_OPTIONS = {500, 400, 300}
