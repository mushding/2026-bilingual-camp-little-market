/// 三天餐費菜單 — 收費同工看學生拿什麼，點品項即可，不用手打金額。
/// D1 晚餐（小市集攤位）、D2 午餐（掃卡）＝完整菜單；
/// D2 晚餐、D3 午餐主餐走 admin「全體扣餐費」，App 端只留加價購品項。
class MealItem {
  final String name;
  final int price;
  const MealItem(this.name, this.price);
}

const Map<String, List<MealItem>> kMealMenus = {
  'D1': [
    MealItem('林記滷肉飯', 60),
    MealItem('阿嬤飄香油飯', 50),
    MealItem('手作綜合飯團', 40),
    MealItem('陳家爆汁豆干', 30),
    MealItem('黃金雙拼', 120),
    MealItem('職人台式春捲', 40),
    MealItem('五色鮮脆蔬菜', 30),
    MealItem('香酥韓式煎餅', 40),
    MealItem('四季水果盤', 30),
    MealItem('手作香濃鮮奶酪', 40),
    MealItem('王記特調飲料', 30),
  ],
  'D2': [
    MealItem('日式馬鈴薯燉肉套餐（午餐）', 160),
    MealItem('加價購・起士片（晚餐）', 40),
  ],
  'D3': [
    MealItem('加價購・古早味豆乾（午餐）', 30),
  ],
};
