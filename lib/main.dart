import 'dart:math'; // ใช้สุ่มตัวเลขตอนสู้
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// ==========================================
// 1. SYSTEM & MODELS
// ==========================================

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    tz.initializeTimeZones();
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings();
    const InitializationSettings settings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    await _notifications.initialize(settings);
  }

  static Future<void> scheduleNotification(int id, String title, DateTime scheduledTime) async {
    if (scheduledTime.isBefore(DateTime.now())) return;
    await _notifications.zonedSchedule(
      id,
      'QUEST REMINDER',
      'Mission "$title" is due now!',
      tz.TZDateTime.from(scheduledTime, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails('ogm_channel', 'OGM Quests', importance: Importance.max, priority: Priority.high),
        iOS: DarwinNotificationDetails(),
      ),
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  static Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }
}

enum QuestClass { warrior, mage, rogue, cleric }

class Quest {
  String id;
  String title;
  bool isCompleted;
  DateTime createdAt;
  DateTime? deadline;
  int priorityIndex; 
  int classIndex; 
  int notificationId;

  Quest({
    required this.id,
    required this.title,
    this.isCompleted = false,
    required this.createdAt,
    this.deadline,
    this.priorityIndex = 1,
    this.classIndex = 0,
    required this.notificationId,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'isCompleted': isCompleted,
        'createdAt': createdAt.toIso8601String(),
        'deadline': deadline?.toIso8601String(),
        'priorityIndex': priorityIndex,
        'classIndex': classIndex,
        'notificationId': notificationId,
      };

  factory Quest.fromMap(Map<dynamic, dynamic> map) => Quest(
        id: map['id'],
        title: map['title'],
        isCompleted: map['isCompleted'],
        createdAt: DateTime.parse(map['createdAt']),
        deadline: map['deadline'] != null ? DateTime.parse(map['deadline']) : null,
        priorityIndex: map['priorityIndex'] ?? 1,
        classIndex: map['classIndex'] ?? 0,
        notificationId: map['notificationId'] ?? 0,
      );
}

class UserGodStats {
  int level;
  int currentXp;
  int maxXp;
  int gold; // *** เงิน (Gold) เพิ่มมาใหม่
  // Attributes
  int str; 
  int intelligence; // แก้ชื่อตัวแปรแล้ว
  int agi; 
  int vit; 

  UserGodStats({
    this.level = 1,
    this.currentXp = 0,
    this.maxXp = 100,
    this.gold = 0, // เริ่มต้นจน
    this.str = 5,
    this.intelligence = 5,
    this.agi = 5,
    this.vit = 5,
  });

  // คำนวณพลังต่อสู้ (Combat Power)
  int get combatPower => (str * 2) + (intelligence * 2) + (agi * 2) + (vit * 3);

  Map<String, dynamic> toMap() => {
        'level': level,
        'currentXp': currentXp,
        'maxXp': maxXp,
        'gold': gold,
        'str': str,
        'intelligence': intelligence,
        'agi': agi,
        'vit': vit,
      };

  factory UserGodStats.fromMap(Map<dynamic, dynamic> map) => UserGodStats(
        level: map['level'] ?? 1,
        currentXp: map['currentXp'] ?? 0,
        maxXp: map['maxXp'] ?? 100,
        gold: map['gold'] ?? 0,
        str: map['str'] ?? 5,
        intelligence: map['intelligence'] ?? 5,
        agi: map['agi'] ?? 5,
        vit: map['vit'] ?? 5,
      );
}

// โมเดลสำหรับ Monster
class Monster {
  final String name;
  final String imageEmoji;
  final int requiredCp; // CP ที่แนะนำ
  final int rewardGold;
  final int rewardXp;
  final Color color;

  Monster({required this.name, required this.imageEmoji, required this.requiredCp, required this.rewardGold, required this.rewardXp, required this.color});
}

// โมเดลสำหรับ Voucher
class Voucher {
  final String title;
  final String description;
  final int price;
  final IconData icon;

  Voucher({required this.title, required this.description, required this.price, required this.icon});
}

// ==========================================
// 2. LOGIC PROVIDER
// ==========================================

class GodModeProvider extends ChangeNotifier {
  List<Quest> _quests = [];
  UserGodStats _stats = UserGodStats();
  late Box _questBox;
  late Box _statsBox;

  List<Quest> get quests => _quests;
  UserGodStats get stats => _stats;
  double get xpProgress => _stats.currentXp / _stats.maxXp;

  Future<void> initialize() async {
    await NotificationService.init();
    _questBox = await Hive.openBox('quests_box_v3');
    _statsBox = await Hive.openBox('stats_box_v3');

    if (_questBox.isNotEmpty) {
      _quests = _questBox.values.map((e) => Quest.fromMap(e)).toList();
      _sortQuests();
    }
    if (_statsBox.isNotEmpty) {
      _stats = UserGodStats.fromMap(_statsBox.get('user_stats'));
    }
    notifyListeners();
  }

  void _sortQuests() {
    _quests.sort((a, b) {
      if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
      if (a.deadline != null && b.deadline != null) return a.deadline!.compareTo(b.deadline!);
      return b.priorityIndex.compareTo(a.priorityIndex);
    });
  }

  Future<void> addQuest(String title, DateTime? deadline, int priorityIdx, int classIdx) async {
    int notifId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final newQuest = Quest(
      id: const Uuid().v4(),
      title: title,
      createdAt: DateTime.now(),
      deadline: deadline,
      priorityIndex: priorityIdx,
      classIndex: classIdx,
      notificationId: notifId,
    );

    if (deadline != null) {
      await NotificationService.scheduleNotification(notifId, title, deadline);
    }

    _quests.add(newQuest);
    _questBox.add(newQuest.toMap());
    _sortQuests();
    notifyListeners();
  }

  void deleteQuest(String id) {
    final index = _quests.indexWhere((q) => q.id == id);
    if (index != -1) {
      NotificationService.cancelNotification(_quests[index].notificationId);
      _quests.removeAt(index);
      _questBox.deleteAt(index);
      notifyListeners();
    }
  }

  void toggleQuestStatus(String id) {
    final index = _quests.indexWhere((q) => q.id == id);
    if (index != -1) {
      final quest = _quests[index];
      quest.isCompleted = !quest.isCompleted;
      
      if (quest.isCompleted) {
        _gainTaskRewards(quest);
        NotificationService.cancelNotification(quest.notificationId);
      }

      _questBox.putAt(index, quest.toMap());
      _sortQuests();
      notifyListeners();
    }
  }

  // รางวัลจากการทำงานบ้าน/งานการ (ได้ Gold เล็กน้อย + Stats)
  void _gainTaskRewards(Quest quest) {
    int baseXp = 10;
    int bonus = quest.priorityIndex * 10;
    _stats.currentXp += (baseXp + bonus);
    _stats.gold += 5 + (quest.priorityIndex * 5); // ทำงานเสร็จได้เงินนิดหน่อย

    switch (QuestClass.values[quest.classIndex]) {
      case QuestClass.warrior: _stats.str++; break;
      case QuestClass.mage: _stats.intelligence++; break;
      case QuestClass.rogue: _stats.agi++; break;
      case QuestClass.cleric: _stats.vit++; break;
    }
    _checkLevelUp();
    _saveStats();
  }

  // --- BATTLE SYSTEM LOGIC ---
  String fightMonster(Monster monster) {
    final random = Random();
    // โอกาสชนะ: พื้นฐาน 50% + (CP เรา / CP มอนสเตอร์ * 30%)
    double winChance = 0.5 + ((_stats.combatPower / monster.requiredCp) * 0.3);
    if (winChance > 0.9) winChance = 0.9; // สูงสุด 90% ต้องมีดวงบ้าง

    bool isWin = random.nextDouble() < winChance;

    if (isWin) {
      _stats.gold += monster.rewardGold;
      _stats.currentXp += monster.rewardXp;
      _checkLevelUp();
      _saveStats();
      return "VICTORY";
    } else {
      int goldLost = (monster.rewardGold * 0.2).toInt(); // แพ้เสียเงิน 20% ของรางวัล
      if (_stats.gold < goldLost) goldLost = _stats.gold;
      _stats.gold -= goldLost;
      _saveStats();
      return "DEFEAT";
    }
  }

  void _checkLevelUp() {
    if (_stats.currentXp >= _stats.maxXp) {
      _stats.level++;
      _stats.currentXp = _stats.currentXp - _stats.maxXp;
      _stats.maxXp = (_stats.maxXp * 1.2).toInt();
      // Bonus Stats
      _stats.str++; _stats.intelligence++; _stats.agi++; _stats.vit++;
    }
  }

  void _saveStats() {
    _statsBox.put('user_stats', _stats.toMap());
    notifyListeners();
  }
}

// ==========================================
// 3. UI IMPLEMENTATION
// ==========================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => GodModeProvider()..initialize()),
      ],
      child: const OGMApp(),
    ),
  );
}

class OGMApp extends StatelessWidget {
  const OGMApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFD700),
          secondary: Colors.redAccent,
        ),
        textTheme: GoogleFonts.cinzelTextTheme(Theme.of(context).textTheme.apply(bodyColor: const Color(0xFFE0E0E0))),
      ),
      home: const MainTabScreen(),
    );
  }
}

// หน้าจอหลัก จัดการ Tab (Task / Battle / Shop)
class MainTabScreen extends StatefulWidget {
  const MainTabScreen({super.key});

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> {
  int _selectedIndex = 0;
  final List<Widget> _pages = [
    const DashboardHUD(), // หน้า Task เดิม
    const BattleArenaScreen(), // หน้าใหม่ สู้มอน
    const ShopScreen(), // หน้าใหม่ ร้านค้า
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.black,
        selectedItemColor: const Color(0xFFFFD700),
        unselectedItemColor: Colors.grey,
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: "TASKS"),
          BottomNavigationBarItem(icon: Icon(Icons.flash_on), label: "BATTLE"),
          BottomNavigationBarItem(icon: Icon(Icons.store), label: "SHOP"),
        ],
      ),
    );
  }
}

// --- SCREEN 1: DASHBOARD (TASKS) ---
class DashboardHUD extends StatelessWidget {
  const DashboardHUD({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<GodModeProvider>(context);
    final stats = provider.stats;

    return Scaffold(
      appBar: AppBar(
        title: const Text("STATUS & TASKS"),
        centerTitle: true,
        backgroundColor: Colors.black,
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(color: Colors.amber.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
            child: Row(
              children: [
                const Icon(Icons.monetization_on, color: Color(0xFFFFD700), size: 16),
                const SizedBox(width: 5),
                Text("${stats.gold}", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFFD700))),
              ],
            ),
          )
        ],
      ),
      body: Column(
        children: [
          // STATS PANEL
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF1A1A1A), border: Border(bottom: BorderSide(color: const Color(0xFFFFD700).withOpacity(0.3)))),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("LVL ${stats.level}", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFFFD700))),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text("EXP ${stats.currentXp}/${stats.maxXp}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        SizedBox(
                          width: 120,
                          child: LinearProgressIndicator(value: provider.xpProgress, color: const Color(0xFFFFD700), backgroundColor: Colors.grey.shade800, minHeight: 6),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _buildStatBadge("STR", stats.str, Colors.red, Icons.fitness_center),
                  _buildStatBadge("INT", stats.intelligence, Colors.blue, Icons.auto_stories),
                  _buildStatBadge("AGI", stats.agi, Colors.green, Icons.speed),
                  _buildStatBadge("VIT", stats.vit, Colors.orange, Icons.favorite),
                ]),
                const SizedBox(height: 5),
                Text("COMBAT POWER: ${stats.combatPower}", style: const TextStyle(color: Colors.grey, fontSize: 12, letterSpacing: 2)),
              ],
            ),
          ),
          
          // QUEST LOG
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: provider.quests.length,
              itemBuilder: (ctx, index) => _buildQuestCard(context, provider.quests[index], provider),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFFFD700),
        child: const Icon(Icons.add, color: Colors.black, size: 30),
        onPressed: () => _showSummonDialog(context),
      ),
    );
  }
  
  // (Helper Widgets for Dashboard - ย่อไว้เพื่อความกระชับ)
  Widget _buildStatBadge(String label, int value, Color color, IconData icon) => Column(children: [Icon(icon, color: color, size: 18), Text("$label $value", style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12))]);

  Widget _buildQuestCard(BuildContext context, Quest quest, GodModeProvider provider) {
    IconData classIcon; Color classColor; String className;
    switch (QuestClass.values[quest.classIndex]) {
      case QuestClass.warrior: classIcon = Icons.fitness_center; classColor = Colors.redAccent; className = "Warrior"; break;
      case QuestClass.mage: classIcon = Icons.auto_stories; classColor = Colors.blueAccent; className = "Mage"; break;
      case QuestClass.rogue: classIcon = Icons.speed; classColor = Colors.greenAccent; className = "Rogue"; break;
      case QuestClass.cleric: classIcon = Icons.favorite; classColor = Colors.orangeAccent; className = "Cleric"; break;
    }
    String timeText = quest.deadline != null ? DateFormat("EEE, HH:mm").format(quest.deadline!) : "";
    return Card(
      color: const Color(0xFF252525), margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(side: BorderSide(color: quest.priorityIndex == 2 ? Colors.red : Colors.transparent), borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: classColor.withOpacity(0.2), shape: BoxShape.circle), child: Icon(classIcon, color: classColor)),
        title: Text(quest.title, style: TextStyle(decoration: quest.isCompleted ? TextDecoration.lineThrough : null, color: quest.isCompleted ? Colors.grey : Colors.white)),
        subtitle: quest.deadline == null ? Text(className, style: TextStyle(color: Colors.grey.shade600, fontSize: 10)) 
          : Row(children: [Text(className, style: TextStyle(color: Colors.grey.shade600, fontSize: 10)), const SizedBox(width: 10), Icon(Icons.alarm, size: 12, color: classColor), const SizedBox(width: 4), Text(timeText, style: TextStyle(color: classColor, fontSize: 12))]),
        trailing: Checkbox(value: quest.isCompleted, activeColor: const Color(0xFFFFD700), checkColor: Colors.black, onChanged: (_) => provider.toggleQuestStatus(quest.id)),
        onLongPress: () => provider.deleteQuest(quest.id),
      ),
    );
  }

  void _showSummonDialog(BuildContext context) {
    final titleController = TextEditingController();
    DateTime? selectedDate;
    TimeOfDay? selectedTime;
    int selectedPriority = 1;
    int selectedClass = 0;

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: const Color(0xFF1E1E1E),
      builder: (ctx) => StatefulBuilder(builder: (context, setState) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 20, top: 20, left: 20, right: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("NEW QUEST", style: TextStyle(color: Color(0xFFFFD700), fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextField(controller: titleController, autofocus: true, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: "Enter mission details...", hintStyle: TextStyle(color: Colors.grey))),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: List.generate(4, (index) {
                  final isSelected = selectedClass == index; final details = _getClassDetails(index);
                  return GestureDetector(onTap: () => setState(() => selectedClass = index), child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: isSelected ? details['color'].withOpacity(0.4) : Colors.grey.withOpacity(0.1), border: isSelected ? Border.all(color: details['color']) : null, borderRadius: BorderRadius.circular(10)), child: Icon(details['icon'], color: details['color'])));
                })),
              const SizedBox(height: 20),
              Row(children: [
                  Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.calendar_today, color: Color(0xFFFFD700)), label: Text(selectedDate == null ? "Date" : DateFormat('dd/MM').format(selectedDate!)), onPressed: () async { final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime(2030), builder: (c, w) => Theme(data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: Color(0xFFFFD700))), child: w!)); if(d!=null) setState(() => selectedDate = d); })),
                  const SizedBox(width: 10),
                  Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.access_time, color: Color(0xFFFFD700)), label: Text(selectedTime == null ? "Time" : selectedTime!.format(context)), onPressed: () async { final t = await showTimePicker(context: context, initialTime: TimeOfDay.now(), builder: (c, w) => Theme(data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: Color(0xFFFFD700))), child: w!)); if(t!=null) setState(() => selectedTime = t); })),
              ]),
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), foregroundColor: Colors.black), onPressed: () { if (titleController.text.isNotEmpty) { DateTime? finalDeadline; if (selectedDate != null) { finalDeadline = DateTime(selectedDate!.year, selectedDate!.month, selectedDate!.day, selectedTime?.hour ?? 9, selectedTime?.minute ?? 0); } Provider.of<GodModeProvider>(context, listen: false).addQuest(titleController.text, finalDeadline, selectedPriority, selectedClass); Navigator.pop(context); }}, child: const Text("ACCEPT QUEST", style: TextStyle(fontWeight: FontWeight.bold)))),
            ],
          ),
        );
      }),
    );
  }
  Map<String, dynamic> _getClassDetails(int index) {
    switch (index) {
      case 0: return {'icon': Icons.fitness_center, 'color': Colors.redAccent};
      case 1: return {'icon': Icons.auto_stories, 'color': Colors.blueAccent};
      case 2: return {'icon': Icons.speed, 'color': Colors.greenAccent};
      case 3: return {'icon': Icons.favorite, 'color': Colors.orangeAccent};
      default: return {};
    }
  }
}

// --- SCREEN 2: BATTLE ARENA (สู้มอนสเตอร์) ---
class BattleArenaScreen extends StatelessWidget {
  const BattleArenaScreen({super.key});

  final List<Monster> monsters = const [
    // รายชื่อมอนสเตอร์
  ];

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<GodModeProvider>(context);
    // รายชื่อ Monster (ต้องใส่ในนี้เพราะใช้ color)
    final monsters = [
      Monster(name: "Slime of Procrastination", imageEmoji: "💧", requiredCp: 50, rewardGold: 50, rewardXp: 20, color: Colors.blue),
      Monster(name: "Goblin of Distraction", imageEmoji: "👺", requiredCp: 150, rewardGold: 150, rewardXp: 50, color: Colors.green),
      Monster(name: "Orc of Laziness", imageEmoji: "👹", requiredCp: 300, rewardGold: 300, rewardXp: 100, color: Colors.orange),
      Monster(name: "Dragon of Burnout", imageEmoji: "🐉", requiredCp: 800, rewardGold: 1000, rewardXp: 500, color: Colors.red),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text("DUNGEON"), centerTitle: true, backgroundColor: Colors.black),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Text("YOUR COMBAT POWER: ${provider.stats.combatPower}", 
              style: const TextStyle(fontSize: 18, color: Color(0xFFFFD700), fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.8),
              itemCount: monsters.length,
              itemBuilder: (ctx, index) {
                final monster = monsters[index];
                return GestureDetector(
                  onTap: () => _startBattle(context, provider, monster),
                  child: Container(
                    decoration: BoxDecoration(color: const Color(0xFF252525), borderRadius: BorderRadius.circular(15), border: Border.all(color: monster.color.withOpacity(0.5))),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(monster.imageEmoji, style: const TextStyle(fontSize: 50)),
                        const SizedBox(height: 10),
                        Text(monster.name, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: monster.color)),
                        const SizedBox(height: 5),
                        Text("CP Required: ${monster.requiredCp}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        Text("Reward: ${monster.rewardGold} Gold", style: const TextStyle(fontSize: 12, color: Color(0xFFFFD700))),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _startBattle(BuildContext context, GodModeProvider provider, Monster monster) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFFFFD700)),
            const SizedBox(height: 20),
            Text("Fighting ${monster.name}...", style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );

    // Simulate delay
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.pop(context); // Close loading
      final result = provider.fightMonster(monster);
      
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text(result, style: TextStyle(color: result == "VICTORY" ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
          content: Text(
            result == "VICTORY" 
              ? "You defeated the monster!\nGained ${monster.rewardGold} Gold & ${monster.rewardXp} XP."
              : "You were defeated!\nLost ${(monster.rewardGold * 0.2).toInt()} Gold.\nGo complete more tasks to get stronger!",
            style: const TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK", style: TextStyle(color: Color(0xFFFFD700))))
          ],
        ),
      );
    });
  }
}

// --- SCREEN 3: SHOP (ร้านค้า) ---
class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<GodModeProvider>(context);
    final vouchers = [
      Voucher(title: "1-Hour Nap Permit", description: "บัตรนอนตื่นสาย อนุญาตให้งีบได้ 1 ชม.", price: 3000, icon: Icons.bed),
      Voucher(title: "Skip Chores Ticket", description: "บัตรข้ามงานบ้าน ใช้แม่ทำแทน 1 ครั้ง", price: 5000, icon: Icons.cleaning_services),
      Voucher(title: "Cheat Meal Pass", description: "บัตรกินตามใจปาก ชาบู/หมูกระทะ", price: 8000, icon: Icons.restaurant),
      Voucher(title: "New Game Fund", description: "กองทุนซื้อเกมใหม่", price: 20000, icon: Icons.videogame_asset),
      Voucher(title: "Day Off License", description: "วันหยุดแห่งชาติ (หยุดทำทุกอย่าง 1 วัน)", price: 50000, icon: Icons.weekend),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text("ITEM SHOP"), centerTitle: true, backgroundColor: Colors.black),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.monetization_on, color: Color(0xFFFFD700), size: 30),
                const SizedBox(width: 10),
                Text("${provider.stats.gold}", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFFFD700))),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: vouchers.length,
              itemBuilder: (ctx, index) {
                final item = vouchers[index];
                final canAfford = provider.stats.gold >= item.price;
                return Card(
                  color: const Color(0xFF252525),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Icon(item.icon, color: const Color(0xFFFFD700))),
                    title: Text(item.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item.description, style: const TextStyle(color: Colors.grey, fontSize: 12)), Text("Price: ${item.price} Gold", style: TextStyle(color: canAfford ? Colors.green : Colors.red, fontSize: 12))]),
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: canAfford ? const Color(0xFFFFD700) : Colors.grey, foregroundColor: Colors.black),
                      onPressed: () {
                        // Logic แลกของ (ยังปิดปรับปรุงตามที่ขอ)
                        showDialog(
                          context: context,
                          builder: (c) => AlertDialog(
                            backgroundColor: const Color(0xFF1E1E1E),
                            title: const Text("UNDER MAINTENANCE", style: TextStyle(color: Colors.red)),
                            content: const Text("ระบบร้านค้ากำลังปรับปรุงโดยเทพเจ้า...\nกรุณาสะสมเหรียญรอไปก่อน", style: TextStyle(color: Colors.white)),
                            actions: [TextButton(onPressed: ()=>Navigator.pop(c), child: const Text("OK"))],
                          ),
                        );
                      },
                      child: const Text("REDEEM"),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}