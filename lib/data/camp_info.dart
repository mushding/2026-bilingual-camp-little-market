// 營會靜態資訊 — 小組名單、三天細流、三天大架構（中英雙語）。
// 資料來源：docs 細流 HTML（2026雙語營-細流-byDay.html），營會前若有改版直接改這裡重 build。
// 細流「執行內容/備註」為關主操作細節，保留中文；標題/地點/大架構含英文。

// ─────────────────────────── 小組 ───────────────────────────

class CampStudent {
  final String name;
  final String english;
  final String grade; // 升小五 / 升國一 …
  final String? note; // 過敏、服藥等紅字備註
  const CampStudent(this.name, this.english, this.grade, [this.note]);
}

class CampGroup {
  final int number;
  final String band; // 國小 / 國中
  final String classroom; // 石門國小教室
  final String churchVenue; // 水庫教會場地
  final List<String> coaches;
  final List<CampStudent> students;
  const CampGroup({
    required this.number,
    required this.band,
    required this.classroom,
    required this.churchVenue,
    required this.coaches,
    required this.students,
  });
}

/// 中文場地/年級 → 英文（groups/maps 畫面共用）。
const Map<String, String> kVenueEn = {
  '自然教室': 'Science Room',
  '活動中心（大）': 'Activity Center (L)',
  '活動中心（中）': 'Activity Center (M)',
  '活動中心（小）': 'Activity Center (S)',
  '圖書室': 'Library',
  '兒童室（外）': 'Kids Room (outer)',
  '兒童室（內）': 'Kids Room (inner)',
  '地下室玻璃屋': 'Basement Glass Room',
  '青年營地': 'Youth Camp Room',
  '副堂': 'Side Hall',
  '二樓沙發區': '2F Sofa Area',
};

const Map<String, String> kGradeEn = {
  '升小五': 'Rising G5',
  '升小六': 'Rising G6',
  '升國一': 'Rising G7',
  '升國二': 'Rising G8',
  '升國三': 'Rising G9',
};

const List<CampGroup> kGroups = [
  CampGroup(
    number: 1, band: '國小', classroom: '自然教室', churchVenue: '活動中心（大）',
    coaches: ['周玲玲 Tissa', '湯詠恩 Anthony', 'Joyce Poon（美國同工）'],
    students: [
      CampStudent('曹少驊', 'Eddie', '升小五'),
      CampStudent('劉威圻', 'Leo', '升小六'),
      CampStudent('吳霈倪', 'Panny', '升小五'),
      CampStudent('林佳薇', 'Dora', '升小五'),
      CampStudent('劉宸希', 'Tracy', '升小六'),
      CampStudent('詹喬依', 'Joy', '升小六'),
    ],
  ),
  CampGroup(
    number: 2, band: '國小', classroom: '3-1', churchVenue: '圖書室',
    coaches: ['林啟昌 Paul', '田世豪 Steve', 'Jennifer Wong（美國同工）'],
    students: [
      CampStudent('盧宥霖', '', '升小六'),
      CampStudent('莊晨晞', 'Leo', '升小五'),
      CampStudent('陳渝絜', 'Jamie', '升小五'),
      CampStudent('蕭安禧', 'Anshi', '升小五'),
      CampStudent('龍采欣', 'Amber', '升小六'),
      CampStudent('林芸安', 'Eall', '升小六'),
    ],
  ),
  CampGroup(
    number: 3, band: '國小', classroom: '3-2', churchVenue: '兒童室（外）',
    coaches: ['陳貞瑾 Debbie', '陳世惟 Richie', 'Jason Lee（美國同工）'],
    students: [
      CampStudent('吳心睿', 'Zack', '升小六'),
      CampStudent('林芷萓', 'Yvonne', '升小五'),
      CampStudent('黃羽恩', 'Abby', '升小五'),
      CampStudent('邱柔兒', 'Zoey', '升小六'),
      CampStudent('劉羽倢', '', '升小六'),
      CampStudent('林塏璇', 'Claire', '升小六'),
    ],
  ),
  CampGroup(
    number: 4, band: '國小', classroom: '3-3', churchVenue: '活動中心（中）',
    coaches: ['葉禮瑋 Leo', '張心樂 Joy', '魏加恩 Luke', 'Elise Chow（美國同工）'],
    students: [
      CampStudent('鍾揚恩', 'Jeremy', '升小五', '不喝牛奶/豆漿'),
      CampStudent('黃俊睿', 'Rayray', '升小六'),
      CampStudent('鍾美恩', 'Phoebe', '升小五'),
      CampStudent('張宸菲', 'Phoebe', '升小五'),
      CampStudent('余娉嫻', '', '升小六'),
    ],
  ),
  CampGroup(
    number: 5, band: '國小', classroom: '3-4', churchVenue: '地下室玻璃屋',
    coaches: ['鄭安康 Ankang', '隋季庭 Ester', '沈智如 Tina', 'Kay Chow（美國同工）'],
    students: [
      CampStudent('徐浚瀧', 'Gino', '升小五'),
      CampStudent('林楷叡', 'Carrey', '升小六'),
      CampStudent('洪婕庭', 'Candy', '升小五'),
      CampStudent('詹沐晴', 'Zora', '升小五'),
      CampStudent('李芯妮', 'Joanna', '升小六'),
    ],
  ),
  CampGroup(
    number: 6, band: '國小', classroom: '3-5', churchVenue: '青年營地',
    coaches: ['黃嘉慶 Eric', '楊文臻 David', '林宛萱 Destiny', '（方睿帆 Jerry）', 'Caleb Leung（美國同工）'],
    students: [
      CampStudent('鍾浩恩', 'Joseph', '升小五'),
      CampStudent('陳登斈', 'Anderson', '升小六', '過動（持續服藥）'),
      CampStudent('王若彤', 'Anna', '升小六'),
      CampStudent('陳恩慈', 'Estelle', '升小六'),
      CampStudent('吳沛然', 'Sophia', '升小五', '奶蛋、小麥過敏'),
    ],
  ),
  CampGroup(
    number: 7, band: '國中', classroom: '4-1', churchVenue: '副堂',
    coaches: ['楊芳齊 Anna', '陳宥安 Money', 'Anne Leung（美國同工）'],
    students: [
      CampStudent('傅泰晨', 'Chen', '升國一'),
      CampStudent('戴柏霖', 'Michael', '升國二'),
      CampStudent('林采蓉', 'Elsa', '升國一'),
      CampStudent('徐悅慈', 'RES', '升國二'),
      CampStudent('劉峻民', 'Jeremy', '升國三'),
      CampStudent('田以樂', 'Jireh', '升國三', '花生、牛奶、帶殼海鮮過敏'),
    ],
  ),
  CampGroup(
    number: 8, band: '國中', classroom: '4-2', churchVenue: '兒童室（內）',
    coaches: ['張詩平 Timothy', '尹暄旻 Doris', 'Evan Leung（美國同工）'],
    students: [
      CampStudent('張紹真', 'Benjamin', '升國一'),
      CampStudent('徐嵩恩', 'Ben', '升國一'),
      CampStudent('傅泰霖', 'Terrin', '升國三'),
      CampStudent('吳心慈', 'Lovey', '升國一'),
      CampStudent('黃品瑜', 'Emma', '升國二'),
      CampStudent('黃悅真', 'Joyic', '升國一'),
      CampStudent('陳婕晞', 'Jessie', '升國一'),
      CampStudent('陳玟妤', 'Ann', '升國二', '過敏'),
    ],
  ),
  CampGroup(
    number: 9, band: '國中', classroom: '4-4', churchVenue: '活動中心（小）',
    coaches: ['劉家榮 Rong', '馬翔恩 Vincent', 'Michelle Leung（美國同工）'],
    students: [
      CampStudent('朝迦樂', 'Caleb', '升國二'),
      CampStudent('張桀睿', 'Jerry', '升國二'),
      CampStudent('簡以柔', 'Zoey', '升國一'),
      CampStudent('甘采靈', 'Lilian', '升國三'),
      CampStudent('陳宥心', 'Sara', '升國三', '海鮮過敏'),
      CampStudent('邱以超', 'Nick', '升國二'),
      CampStudent('吳澄睿', 'Ray', '升國一'),
    ],
  ),
  CampGroup(
    number: 10, band: '國中', classroom: '4-5', churchVenue: '二樓沙發區',
    coaches: ['劉啟宇 Kiwi', '張孝恂 Christina', 'Alex Leung（美國同工）'],
    students: [
      CampStudent('徐崇理', 'Larry', '升國一'),
      CampStudent('周寘融', 'Ron', '升國三'),
      CampStudent('李均樺', 'Jessica', '升國一'),
      CampStudent('陳品瑄', 'Sharon', '升國二'),
      CampStudent('張嫚庭', 'Mandy', '升國三'),
      CampStudent('郭振嘉', 'Allen', '升國一'),
      CampStudent('呂研', 'Ian', '升國三'),
      CampStudent('楊婕誼', 'Tanya', '升國一'),
    ],
  ),
];

// ─────────────────────────── 細流 ───────────────────────────

class RundownItem {
  final String time; // 12:30–13:00
  final String? duration; // (30)
  final String title;
  final String? titleEn;
  final String place;
  final String? placeEn;
  final List<String> details; // 每行可含【組別】前綴（中文）
  final List<String> sideNotes; // 各組備註（中文）
  const RundownItem({
    required this.time,
    this.duration,
    required this.title,
    this.titleEn,
    required this.place,
    this.placeEn,
    this.details = const [],
    this.sideNotes = const [],
  });
}

class CampDay {
  final String label; // Day 1
  final String date; // 08/07（五）
  final String dateEn; // Aug 7 (Fri)
  final String shirt;
  final String shirtEn;
  final String summary;
  final String summaryEn;
  final List<RundownItem> rundown;
  final List<(String, String, String)> overview; // 時間, 中文, English
  final List<(String, String, String)> maps; // asset, 圖說中文, English
  const CampDay({
    required this.label,
    required this.date,
    required this.dateEn,
    required this.shirt,
    required this.shirtEn,
    required this.summary,
    required this.summaryEn,
    required this.rundown,
    required this.overview,
    this.maps = const [],
  });
}

const List<CampDay> kCampDays = [
  // ══════════ DAY 1 ══════════
  CampDay(
    label: 'Day 1',
    date: '08/07（五）',
    dateEn: 'Aug 7 (Fri)',
    shirt: '非輔導：白 T ／ 輔導：淺藍 T',
    shirtEn: 'Staff: white tee / Coaches: light blue tee',
    summary: '下午報到 → 石小主題一 → 走回教會 → 夕陽會＋小市集一 → 營火晚會',
    summaryEn: 'PM check-in → Theme 1 at Shimen ES → walk to church → Sunset Party + Market 1 → Campfire',
    overview: [
      ('09:00', '同工集合、造就、營長時間', 'Staff gathering & devotion'),
      ('11:00', '同工午餐', 'Staff lunch'),
      ('11:40', '出發石小', 'Depart for Shimen ES'),
      ('12:30', '學員報到', 'Student check-in'),
      ('13:00', '相見歡', 'Meet & Greet'),
      ('13:40', '小組時間 1', 'Group Time 1'),
      ('14:40', '主題一（大地遊戲）', 'Theme 1 (Field Game)'),
      ('16:40', '走路回教會', 'Walk back to church'),
      ('17:00', '夕陽會＋小市集一', 'Sunset Party + Market 1'),
      ('18:20', '營火晚會', 'Campfire Party'),
      ('19:20', '小組時間 2', 'Group Time 2'),
      ('20:30', '回家', 'Heading home'),
    ],
    maps: [
      ('assets/maps/market1.jpg', '小市集一・晴天（水庫教會）', 'Market 1 — fair weather (church)'),
      ('assets/maps/market1_rain.jpg', '小市集一・雨備', 'Market 1 — rain backup'),
    ],
    rundown: [
      RundownItem(
        time: '12:30–13:00', duration: '30',
        title: '學員報到', titleEn: 'Student Check-in',
        place: '石小川堂／禮堂', placeEn: 'Shimen ES hallway / auditorium',
        details: [
          '【生活】10:30 發防蚊液、冷氣卡、手持牌',
          '【輔導】到石小後去各小組場地整理，整理完回禮堂禱告；報到時段 8 人在一樓指引路線到禮堂',
          '【生活】到石小後去各川堂場地整理，整理完回禮堂禱告；鳳熒姐引導走錯地點的學生與家長（@教會）；門口放角錐（車導）；A 棟報到處放長桌 2–3 張',
          '【生活】備一箱瓶裝礦泉水（學員不配發飲水，鼓勵自帶水壺）；報到：點名單＆手冊、名牌＋感應卡片 → 總採',
          '【多媒】播放前年雙語營影片、確認音響；12:20 準備拖拉 mic',
          '【活動】12:20 門口唱歌歡迎',
          '【宣攝】拍照',
          '【其它同工】回禮堂開始禱告',
          '【大會】禱告一直到 12:20',
          '學員行李統一放禮堂行李區',
        ],
        sideNotes: ['【主持】12:45 預備', '【小卡(安琪)、樂團】12:45 預備'],
      ),
      RundownItem(
        time: '13:00–13:40', duration: '40',
        title: '相見歡', titleEn: 'Meet & Greet',
        place: '石小禮堂', placeEn: 'Shimen ES auditorium',
        details: [
          '【主持】13:00 開場；13:00–13:12 介紹輔導、cue 安琪介紹小卡信箱、介紹小市集',
          '【樂團】13:12–13:20 樂團；13:20–13:27 cue 宣恩堂樂團',
          '【主持】13:27–13:31 宣示；13:31–13:32 cue 魏哥',
          '【魏哥】13:32–13:35 祝禱',
          '【主持】13:35–13:37 報告小組場地、大地集合時間',
          '【輔導】移動至小組場地',
        ],
        sideNotes: [
          '【生活】放桌牌',
          '【魏哥】13:20 預備',
          '【生活、多媒】13:40 出發教會，準備夕陽會、營火；16:00 先吃飯（等等要忙搬東西）',
        ],
      ),
      RundownItem(
        time: '13:40–14:40', duration: '60',
        title: '小組時間 1', titleEn: 'Group Time 1',
        place: '石小各小組教室', placeEn: 'Shimen ES group classrooms',
        details: ['【輔導】組內相見歡'],
        sideNotes: ['【關主】14:10 營本集合'],
      ),
      RundownItem(
        time: '14:40–16:40', duration: '120',
        title: '主題一（大地遊戲・試探之途）',
        titleEn: 'Theme 1 — Field Game: Path of Trials',
        place: '石小禮堂／各處', placeEn: 'Shimen ES auditorium & campus',
        details: [
          '【企劃、主持】14:40 開場',
          '【企劃、主持】16:30 禮堂結關',
          '【主持】宣布移動回教會',
        ],
        sideNotes: ['【主持、企劃、多媒】14:20 預備開場'],
      ),
      RundownItem(
        time: '16:40–17:00', duration: '20',
        title: '回教會 🚶', titleEn: 'Walk back to church 🚶',
        place: '馬路', placeEn: 'On the road',
        details: [
          '【主持】帶隊回教會',
          '【輔導】管秩序',
          '【生活】路口指揮（美國路／圓環）、沿途車導；下雨找教會弟兄姊妹開車接送',
        ],
        sideNotes: ['【關主】收關後回教會吃飯'],
      ),
      RundownItem(
        time: '17:00–18:20', duration: '80',
        title: '夕陽會＋小市集一 🏪', titleEn: 'Sunset Party + Market 1 🏪',
        place: '教會籃球場', placeEn: 'Church basketball court',
        details: [
          '【同工】@籃球場吃飯',
          '【輔導】幫忙學員行李放小組場地',
          '【主持】17:00 開場；學員 17:00–17:30 吃飯',
          '【主持】17:30 宣布市集開場；學員 17:30–18:10 小市集一',
          '【主持】18:10–18:20 引導至營火晚會場地',
          '【輔導】18:05 收心、管秩序',
          '【生活】閒置同工 18:20 收盤子、場地',
        ],
        sideNotes: [
          '【小市集關主】17:15 集合備關',
          '【生活】夕陽會組 16:00 吃飯、16:30–17:00 場佈',
          '【生活】17:00 營火組開始準備、17:30 最後確認',
          '【吃飯順序】16:00 生活＋多媒 → 17:00 輔導＋學生（12、34、56…組）→ 17:15 其它同工',
          '【活動、晚會主持、多媒】18:00 預備、確認設備',
        ],
      ),
      RundownItem(
        time: '18:20–19:10', duration: '50',
        title: '營火晚會 🔥', titleEn: 'Campfire Party 🔥',
        place: '晴天：草皮／雨備：正堂', placeEn: 'Lawn (rain backup: Main Hall)',
        details: [
          '【晚會主持】18:10–18:20 整隊；18:20–18:25 營火舞教學；18:25–19:00 營火舞、遊戲；19:00–19:10 報告、引導回小組場地',
          '【輔導】管秩序、參與活動',
          '【活動】參與活動',
          '【多媒】協助音控',
          '【生活】控火',
        ],
        sideNotes: ['【生活】協助防蚊液；18:25 點火'],
      ),
      RundownItem(
        time: '19:20–20:30', duration: '70',
        title: '小組時間 2', titleEn: 'Group Time 2',
        place: '教會各小組場地', placeEn: 'Church group rooms',
        details: [
          '【造就＆組長】19:20 晚禱',
          '【同工】推細流、拿大會 T @正堂',
          '【生活】小組分隊：分大會 T 到各組場地、確認無誤、協助更換；同工分隊：大會 T 放正堂講台分組；同工宵夜',
          '【輔導】確認大會 T 無誤；收興趣分組志願序',
        ],
      ),
      RundownItem(
        time: '20:30–',
        title: '回家 🏠', titleEn: 'Heading home 🏠',
        place: '教會', placeEn: 'Church',
        details: [
          '【生活】20:15 準備車導 @教會',
          '小組提早結束 → 到副堂等，否則直接上車回家；多媒同工在外面拿拖拉麥叫學員名字',
          '【輔導】20:30 小輔在副堂、兒童室陪伴等候家長接送；陪同組員確認家長領回',
          '【晚上開會】要給輔導：主題二的地圖＋五色手環',
        ],
        sideNotes: ['【生活】20:15–20:40 兩位在石小', '【輔導、活動、生活】20:45 聚集'],
      ),
    ],
  ),
  // ══════════ DAY 2 ══════════
  CampDay(
    label: 'Day 2',
    date: '08/08（六）',
    dateEn: 'Aug 8 (Sat)',
    shirt: '全體：今年大會 T',
    shirtEn: "Everyone: this year's camp tee",
    summary: '石小主題二 → 五色環 → 小市集二 → 興趣分組 → 回教會戲劇佈道會',
    summaryEn: 'Theme 2 at Shimen ES → Five-Color Bracelet → Market 2 → Interest Groups → drama & rally at church',
    overview: [
      ('07:50', '同工集合、詩歌禱告', 'Staff gathering & worship'),
      ('08:30', '學員集合', 'Student assembly'),
      ('08:40', '主題二（聖經故事與日常生活）', 'Theme 2 (Bible & daily life)'),
      ('10:50', '大合照', 'Group photo'),
      ('11:00', '小組時間・五色手環', 'Group Time — Five-Color Bracelet'),
      ('12:00', '午餐午休', 'Lunch & rest'),
      ('13:00', '小市集二', 'Market 2'),
      ('14:00', '興趣分組', 'Interest Groups'),
      ('16:40', '走路回教會', 'Walk back to church'),
      ('17:00', '晚餐／同工禁禱', 'Dinner / staff prayer'),
      ('17:40', '戲劇／樂團', 'Drama / band'),
      ('18:30', '佈道會', 'Evangelistic Rally'),
      ('19:40', '小組時間 3', 'Group Time 3'),
      ('20:30', '回家', 'Heading home'),
    ],
    maps: [
      ('assets/maps/market23.jpg', '小市集二／三（石門國小）', 'Market 2/3 (Shimen ES)'),
      ('assets/maps/market23_rain.jpg', '小市集二／三・雨備', 'Market 2/3 — rain backup'),
      ('assets/maps/day2_lunch_route.jpg', '第二天午餐動線（石小川堂）', 'Day 2 lunch route'),
      ('assets/maps/day2_interest_venue.jpg', '第二天興趣分組場地', 'Day 2 interest group venues'),
    ],
    rundown: [
      RundownItem(
        time: '07:50–08:20', duration: '30',
        title: '同工集合', titleEn: 'Staff Gathering',
        place: '石小禮堂', placeEn: 'Shimen ES auditorium',
        details: [
          '【同工】07:50 開始巡迴巴士；08:00 直接在石小禮堂集合',
          '【造就】08:05–08:20 同工詩歌禱告會',
        ],
        sideNotes: ['【生活】教會留人；留意提早到的學員', '【多媒】08:00 準備'],
      ),
      RundownItem(
        time: '08:30–08:40', duration: '10',
        title: '學員集合', titleEn: 'Student Assembly',
        place: '石小川堂／禮堂', placeEn: 'Shimen ES hallway / auditorium',
        details: [
          '【生活】08:20 在大門口報到',
          '【輔導、活動】08:20 在門口迎接同隊學員',
          '【主持】08:40 整隊集合',
        ],
        sideNotes: ['【樂團】08:20 確認設備、試音', '【活動】08:20 主題二關主道具上手'],
      ),
      RundownItem(
        time: '08:40–10:50', duration: '130',
        title: '主題二（聖經故事與日常生活的連結）',
        titleEn: 'Theme 2 — Bible Stories & Daily Life',
        place: '石小各小組場地', placeEn: 'Shimen ES group rooms',
        details: [
          '【企劃】08:40 開場',
          '【企劃、主持】10:40 禮堂結關',
          '【主持】宣布拍大合照',
        ],
      ),
      RundownItem(
        time: '10:50–11:00',
        title: '大合照 📸', titleEn: 'Group Photo 📸',
        place: '石小禮堂', placeEn: 'Shimen ES auditorium',
        details: ['【生活】拆大字', '【宣攝】拍照'],
      ),
      RundownItem(
        time: '11:00–12:00', duration: '60',
        title: '小組時間・五色手環', titleEn: 'Group Time — Five-Color Bracelet',
        place: '石小各小組場地', placeEn: 'Shimen ES group rooms',
        details: ['【輔導】組內分享，帶出信仰 1（五色環）'],
        sideNotes: [
          '【其它同工】11:00 回教會吃飯',
          '【生活】10:00–11:00 在教會準備便當；11:20 送便當來；11:40 整理便當場地（川堂有自助餐）',
        ],
      ),
      RundownItem(
        time: '12:00–13:00', duration: '60',
        title: '午餐午休 🍱', titleEn: 'Lunch & Rest 🍱',
        place: '石小各小組場地', placeEn: 'Shimen ES group rooms',
        details: [
          '【活動】今天學員午餐用買的 @川堂',
          '【輔導】吃飯＋直接在小組場地午休',
          '【同工】@營本吃飯',
        ],
        sideNotes: ['【關主、生活】12:40 營本集合備關'],
      ),
      RundownItem(
        time: '13:00–14:00', duration: '60',
        title: '小市集二 🏪', titleEn: 'Market 2 🏪',
        place: '石小禮堂／各處', placeEn: 'Shimen ES auditorium & campus',
        details: ['【主持】13:00 小市集開場 @禮堂'],
        sideNotes: [
          '【主持】12:40 預備',
          '【多媒】15:10 回教會',
          '【宣恩堂】13:30 預備興趣分組 @營本',
        ],
      ),
      RundownItem(
        time: '14:00–16:40', duration: '160',
        title: '興趣分組（帶出信仰 2）', titleEn: 'Interest Groups',
        place: '石小各處', placeEn: 'Shimen ES campus',
        details: [
          '【主持】集合開場，接興趣分組；16:35 禮堂集合',
          '【宣恩堂】興趣分組，帶出信仰 2',
          '共 6 班：水彩、舞蹈、急救、手作、籃球、防身術',
        ],
      ),
      RundownItem(
        time: '16:40–17:00', duration: '20',
        title: '回教會 🚶', titleEn: 'Walk back to church 🚶',
        place: '馬路', placeEn: 'On the road',
        details: [
          '【主持】引導回教會',
          '【輔導】管秩序',
          '【生活】沿途車導、協助管秩序',
        ],
        sideNotes: ['【關主、生活】收關後打掃教室，回教會'],
      ),
      RundownItem(
        time: '17:00–17:30', duration: '30',
        title: '晚餐／禁禱', titleEn: 'Dinner / Staff Prayer',
        place: '教會地下室／正堂', placeEn: 'Church basement / Main Hall',
        details: [
          '【輔導】17:00 帶學生至地下室用餐；每組留一位輔導陪小組，其餘正堂禱告（宣恩堂也參加）',
          '【同工】17:00–17:25 正堂禁食禱告會',
          '【樂團】17:25–17:30 試音；【多媒】協助試音',
          '【生活】17:00 於一樓樓梯間讓學員不要上正堂（輔導控好！）',
        ],
        sideNotes: ['【黃哥】接待講員'],
      ),
      RundownItem(
        time: '17:40–18:30', duration: '50',
        title: '戲劇／樂團 🎭', titleEn: 'Drama / Band 🎭',
        place: '正堂', placeEn: 'Main Hall',
        details: [
          '【樂團】17:40–18:00 (20)',
          '【主持】18:00–18:01 串場',
          '【活動組戲劇】18:01–18:29「一個人有多少土地」(28)',
          '【主持】18:29–18:30 串場',
        ],
        sideNotes: ['【樂團、戲劇】17:30 預備', '【信息】18:20 預備', '【生活】備衛生紙'],
      ),
      RundownItem(
        time: '18:30–19:30', duration: '60',
        title: '佈道會 ✝️', titleEn: 'Evangelistic Rally ✝️',
        place: '正堂', placeEn: 'Main Hall',
        details: ['【信息】信息分享及呼召', '【主持】19:35 引導回小組'],
      ),
      RundownItem(
        time: '19:40–20:30', duration: '50',
        title: '小組時間 3', titleEn: 'Group Time 3',
        place: '教會各小組場地', placeEn: 'Church group rooms',
        details: ['【輔導】小組分享晚上信息', '【同工】晚禱、推細流 @正堂'],
      ),
      RundownItem(
        time: '20:30',
        title: '回家 🏠', titleEn: 'Heading home 🏠',
        place: '教會', placeEn: 'Church',
        details: [
          '【生活】20:15 準備車導',
          '【輔導】20:30 小輔在副堂、兒童室陪伴等候家長接送；陪同組員確認家長領回',
          '【活動】私下討論頒獎名稱 → 寫進主持稿（投影片）；給主持頒獎詞＆頒獎人（宣＋企）',
        ],
        sideNotes: ['【生活】20:15–20:40 兩位在石小', '【輔導、活動、生活】20:45 聚集'],
      ),
    ],
  ),
  // ══════════ DAY 3 ══════════
  CampDay(
    label: 'Day 3',
    date: '08/09（日）',
    dateEn: 'Aug 9 (Sun)',
    shirt: '非輔導：前年大會 T ／ 輔導：去年大會 T',
    shirtEn: "Staff: camp tee from 2 years ago / Coaches: last year's tee",
    summary: '石小主日 → 小市集三 → 回教會 → 年級分組 → 惜別會',
    summaryEn: 'Sunday service at Shimen ES → Market 3 → back to church → grade-level groups → Closing Gathering',
    overview: [
      ('07:50', '同工集合、詩歌禱告＋讀經', 'Staff gathering & devotion'),
      ('08:30', '學員集合', 'Student assembly'),
      ('08:40', '主日', 'Sunday Service'),
      ('09:30', '小市集三', 'Market 3'),
      ('10:50', '小組時間 4', 'Group Time 4'),
      ('11:40', '走路回教會', 'Walk back to church'),
      ('12:00', '午餐午休', 'Lunch & rest'),
      ('13:00', '年級分組', 'Grade-level groups'),
      ('14:00', '惜別會', 'Closing Gathering'),
      ('15:50', '歡送／收尾', 'Farewell & cleanup'),
    ],
    maps: [
      ('assets/maps/market23.jpg', '小市集三（石門國小，同 Day 2 配置）', 'Market 3 (same layout as Day 2)'),
      ('assets/maps/market23_rain.jpg', '小市集三・雨備', 'Market 3 — rain backup'),
    ],
    rundown: [
      RundownItem(
        time: '07:50–08:20', duration: '30',
        title: '同工集合', titleEn: 'Staff Gathering',
        place: '石小禮堂', placeEn: 'Shimen ES auditorium',
        details: [
          '【同工】07:50 開始巡迴巴士；08:00 直接在石小禮堂集合',
          '【同工】08:05–08:15 詩歌禱告會＋一起讀經',
        ],
        sideNotes: ['【生活】教會留人；留意提早到的學員', '【多媒】08:00 準備'],
      ),
      RundownItem(
        time: '08:30–08:40', duration: '10',
        title: '學員集合', titleEn: 'Student Assembly',
        place: '石小川堂／禮堂', placeEn: 'Shimen ES hallway / auditorium',
        details: [
          '【生活】08:20 在大門口報到',
          '【輔導、活動】08:20 在門口迎接同隊學員',
          '【主持】08:40 整隊集合',
        ],
        sideNotes: ['【多媒、樂團】08:15 確認設備、試音'],
      ),
      RundownItem(
        time: '08:40–09:30', duration: '50',
        title: '主日 ✝️', titleEn: 'Sunday Service ✝️',
        place: '石小禮堂', placeEn: 'Shimen ES auditorium',
        details: [
          '【主持】08:40–08:45 (5)',
          '【樂團】08:45–09:05 (20)',
          '【主持】09:05 cue 講員',
          '【講員】09:05–09:30 (25)',
        ],
        sideNotes: ['【關主】09:00 小市集佈關'],
      ),
      RundownItem(
        time: '09:30–10:50', duration: '80',
        title: '小市集三 🏪', titleEn: 'Market 3 🏪',
        place: '石小各處', placeEn: 'Shimen ES campus',
        details: [
          '【主持】09:30 主持開場',
          '【輔導】管秩序',
        ],
        sideNotes: ['【生活】10:50 開始收禮堂'],
      ),
      RundownItem(
        time: '10:50–11:40', duration: '50',
        title: '小組時間 4', titleEn: 'Group Time 4',
        place: '石小各處', placeEn: 'Shimen ES campus',
        details: ['結束後穿堂集合回教會'],
        sideNotes: [
          '【多媒】11:00 撤器材，留拖拉 mic',
          '【生活1】11:30 備餐；備餐同工 11:50 前吃完',
        ],
      ),
      RundownItem(
        time: '11:40–12:00', duration: '20',
        title: '回教會 🚶', titleEn: 'Walk back to church 🚶',
        place: '馬路', placeEn: 'On the road',
        details: [
          '【主持】帶隊回教會',
          '【輔導】管秩序',
          '【生活】沿途車導、協助管秩序',
        ],
        sideNotes: ['【生活2】打掃教室、禮堂、廁所，確認收完！'],
      ),
      RundownItem(
        time: '12:00–13:00', duration: '60',
        title: '午餐午休 🍱', titleEn: 'Lunch & Rest 🍱',
        place: '教會地下室', placeEn: 'Church basement',
        details: ['【輔導】管秩序'],
        sideNotes: [
          '【關主】13:00 營本集合',
          '【年級輔導】12:30 年級小組場地集合',
          '【同工】副堂吃',
        ],
      ),
      RundownItem(
        time: '13:00–14:00', duration: '60',
        title: '年級分組', titleEn: 'Grade-Level Groups',
        place: '教會各場地', placeEn: 'Church venues',
        details: [
          '13:00–13:05 正堂集合；13:05–13:10 依年級分組後前往場地 (50)',
          '📍 小五、小六：活動中心 / G5–G6: Activity Center',
          '📍 國一：地下室（小） / G7: basement (small)',
          '📍 國二：兒童室 / G8: Kids Room',
          '📍 國三：副堂 / G9: Side Hall',
        ],
        sideNotes: ['【樂團、多媒、主持】12:30 試音'],
      ),
      RundownItem(
        time: '14:00–15:50', duration: '110',
        title: '惜別會 👋', titleEn: 'Closing Gathering 👋',
        place: '正堂', placeEn: 'Main Hall',
        details: [
          '【主持】14:00 開場 (5)',
          '【樂團】14:05–14:25 (20)',
          '【主持】14:25–14:45 小市集成果發表 (20)；14:45–15:05 頒獎 (20)',
          '【宣攝】15:05–15:15 回顧影片 (10)',
          '【主持】15:15–15:35 學員分享 (20)',
          '【輔導】15:35–15:40 輔導獻詩 (5)',
          '【營長】15:40–15:45 (5)',
          '【生活】15:40 車導協助家長接送',
        ],
        sideNotes: ['【活動】15:10 頒獎人預備', '【多媒、樂團、生活】14:40 協助音響設備 @門口'],
      ),
      RundownItem(
        time: '15:50–',
        title: '歡送／收尾 🏠', titleEn: 'Farewell & Cleanup 🏠',
        place: '教會', placeEn: 'Church',
        details: [
          '15:50 歡送學員',
          '16:10 同工大合照 @門口',
          '16:30 打掃',
          '感恩餐聚（慶功宴）',
        ],
      ),
    ],
  ),
];
