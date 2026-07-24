import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:confetti/confetti.dart';
import 'dart:convert';

void main() {
  runApp(const LavkaHelperApp());
}

class LavkaHelperApp extends StatelessWidget {
  const LavkaHelperApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lavka Helper',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.green,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        cardTheme: CardThemeData(
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class Shift {
  final DateTime date;
  final Duration duration;
  final int orders;
  final double hourlyEarnings;
  final double orderEarnings;
  double tips;
  double bonuses;
  double receivedTomorrow;
  double receivedWednesday;

  Shift({
    required this.date,
    required this.duration,
    required this.orders,
    required this.hourlyEarnings,
    required this.orderEarnings,
    this.tips = 0,
    this.bonuses = 0,
    this.receivedTomorrow = 0,
    this.receivedWednesday = 0,
  });

  double get totalCalculated => hourlyEarnings + orderEarnings + tips + bonuses;
  double get pendingWednesday => totalCalculated - receivedTomorrow - receivedWednesday;

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'duration': duration.inSeconds,
        'orders': orders,
        'hourlyEarnings': hourlyEarnings,
        'orderEarnings': orderEarnings,
        'tips': tips,
        'bonuses': bonuses,
        'receivedTomorrow': receivedTomorrow,
        'receivedWednesday': receivedWednesday,
      };

  factory Shift.fromJson(Map<String, dynamic> json) => Shift(
        date: DateTime.parse(json['date']),
        duration: Duration(seconds: json['duration']),
        orders: json['orders'],
        hourlyEarnings: json['hourlyEarnings'].toDouble(),
        orderEarnings: json['orderEarnings'].toDouble(),
        tips: json['tips']?.toDouble() ?? 0,
        bonuses: json['bonuses']?.toDouble() ?? 0,
        receivedTomorrow: json['receivedTomorrow']?.toDouble() ?? 0,
        receivedWednesday: json['receivedWednesday']?.toDouble() ?? 0,
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _isWorking = false;
  double _hourRate = 250;
  double _orderRate = 80;
  List<Order> _orders = [];
  List<Shift> _shiftHistory = [];

  late ConfettiController _confettiController;
  late AnimationController _counterController;

  double _displayedEarnings = 0;

  @override
  void initState() {
    super.initState();
    _loadData();

    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    _counterController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _counterController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hourRate = prefs.getDouble('hourRate') ?? 250;
      _orderRate = prefs.getDouble('orderRate') ?? 80;
      final historyJson = prefs.getStringList('shiftHistory') ?? [];
      _shiftHistory = historyJson.map((e) => Shift.fromJson(jsonDecode(e))).toList();
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('hourRate', _hourRate);
    await prefs.setDouble('orderRate', _orderRate);
    final historyJson = _shiftHistory.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList('shiftHistory', historyJson);
  }

  double get todayEarnings {
    final today = DateTime.now();
    return _shiftHistory
        .where((s) => s.date.year == today.year && s.date.month == today.month && s.date.day == today.day)
        .fold(0.0, (sum, s) => sum + s.totalCalculated);
  }

  double get pendingWednesdayTotal {
    return _shiftHistory.fold(0.0, (sum, s) => sum + s.pendingWednesday);
  }

  void _startShift() {
    setState(() {
      _isWorking = true;
      _elapsed = Duration.zero;
      _orders.clear();
      _displayedEarnings = 0;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  void _endShift() {
    _timer?.cancel();
    final shift = Shift(
      date: DateTime.now(),
      duration: _elapsed,
      orders: _orders.length,
      hourlyEarnings: _hourRate * _elapsed.inMinutes / 60,
      orderEarnings: _orders.length * _orderRate,
    );

    setState(() {
      _shiftHistory.insert(0, shift);
      _isWorking = false;
      _orders.clear();
      _elapsed = Duration.zero;
    });

    _saveData();
    _showConfettiAndSummary(shift);
  }

  void _showConfettiAndSummary(Shift shift) {
    _confettiController.play();
    _counterController.forward(from: 0);
    _displayedEarnings = shift.totalCalculated;

    showDialog(
      context: context,
      builder: (context) => Stack(
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              emissionFrequency: 0.06,
              numberOfParticles: 100,
              colors: const [Colors.green, Colors.yellow, Colors.blue, Colors.pink, Colors.orange],
            ),
          ),
          AlertDialog(
            title: const Text('Смена успешно завершена!'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Заработано', style: TextStyle(fontSize: 18)),
                AnimatedBuilder(
                  animation: _counterController,
                  builder: (context, child) {
                    return Text(
                      '${(_displayedEarnings * _counterController.value).toStringAsFixed(0)} ₽',
                      style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.green),
                    );
                  },
                ),
              ],
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отлично'))],
          ),
        ],
      ),
    );
  }

  void _addOrder() {
    String address = '';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Новый заказ'),
        content: TextField(
          decoration: const InputDecoration(labelText: 'Адрес или № заказа'),
          onChanged: (value) => address = value,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          TextButton(
            onPressed: () {
              if (address.isNotEmpty) {
                setState(() => _orders.add(Order(address: address, time: DateTime.now())));
              }
              Navigator.pop(context);
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }

  void _pasteFromClipboard() async {
    ClipboardData? data = await Clipboard.getData('text/plain');
    if (data?.text != null && data!.text!.isNotEmpty) {
      final lines = data.text!.split('\n');
      int added = 0;
      setState(() {
        for (var line in lines) {
          String trimmed = line.trim();
          if (trimmed.isNotEmpty) {
            _orders.add(Order(address: trimmed, time: DateTime.now()));
            added++;
          }
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Добавлено $added заказов')));
    }
  }

  void _removeOrder(int index) {
    setState(() => _orders.removeAt(index));
  }

  void _openSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Настройки ставок'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(labelText: 'Почасовка (₽)'),
              keyboardType: TextInputType.number,
              controller: TextEditingController(text: _hourRate.toString()),
              onChanged: (v) => _hourRate = double.tryParse(v) ?? _hourRate,
            ),
            TextField(
              decoration: const InputDecoration(labelText: 'За заказ (₽)'),
              keyboardType: TextInputType.number,
              controller: TextEditingController(text: _orderRate.toString()),
              onChanged: (v) => _orderRate = double.tryParse(v) ?? _orderRate,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          TextButton(onPressed: () { _saveData(); Navigator.pop(context); }, child: const Text('Сохранить')),
        ],
      ),
    );
  }

  void _openHistory() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => HistoryScreen(shiftHistory: _shiftHistory, onUpdate: _updateShift)));
  }

  void _updateShift(Shift updated) {
    setState(() {
      final index = _shiftHistory.indexWhere((s) => s.date == updated.date);
      if (index != -1) _shiftHistory[index] = updated;
    });
    _saveData();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _isWorking ? (_elapsed.inMinutes / 480).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lavka Helper'),
        centerTitle: true,
        backgroundColor: Colors.green[900],
        actions: [
          IconButton(icon: const Icon(Icons.history), onPressed: _openHistory),
          IconButton(icon: const Icon(Icons.settings), onPressed: _openSettings),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_isWorking)
              Column(
                children: [
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey[800],
                    color: Colors.greenAccent,
                    minHeight: 12,
                  ),
                  const SizedBox(height: 4),
                  Text('${(progress * 100).toStringAsFixed(0)}% от 8-часовой смены', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            const SizedBox(height: 16),
            Card(
              color: Colors.green[800],
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text('Время в смене', style: TextStyle(fontSize: 18, color: Colors.white70)),
                    Text(
                      '${_elapsed.inHours.toString().padLeft(2, '0')}:${(_elapsed.inMinutes % 60).toString().padLeft(2, '0')}:${(_elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 52, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildStatCard('${_orders.length}', 'Заказов')),
                Expanded(child: _buildStatCard('${todayEarnings.toStringAsFixed(0)} ₽', 'За сегодня', color: Colors.green)),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              color: Colors.orange[800],
              child: ListTile(
                title: const Text('Ожидается в среду', style: TextStyle(color: Colors.white)),
                trailing: Text('${pendingWednesdayTotal.toStringAsFixed(0)} ₽', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _isWorking ? _pasteFromClipboard : null, style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, minimumSize: const Size(double.infinity, 50)), child: const Text('ВСТАВИТЬ ИЗ БУФЕРА')),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _isWorking ? _addOrder : null, style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, minimumSize: const Size(double.infinity, 50)), child: const Text('+ НОВЫЙ ЗАКАЗ')),
            const SizedBox(height: 16),
            Expanded(
              child: _orders.isEmpty
                  ? const Center(child: Text('Заказов пока нет\nСкопируй адрес и вставь', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: _orders.length,
                      itemBuilder: (context, index) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.delivery_dining, color: Colors.green),
                          title: Text(_orders[index].address),
                          trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _removeOrder(index)),
                        ),
                      ),
                    ),
            ),
            ElevatedButton(onPressed: _isWorking ? null : _startShift, style: ElevatedButton.styleFrom(backgroundColor: Colors.green, minimumSize: const Size(double.infinity, 60)), child: const Text('НАЧАТЬ СМЕНУ', style: TextStyle(fontSize: 18))),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _isWorking ? _endShift : null, style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], minimumSize: const Size(double.infinity, 55)), child: const Text('ЗАВЕРШИТЬ СМЕНУ', style: TextStyle(fontSize: 18))),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String value, String label, {Color? color}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class Order {
  final String address;
  final DateTime time;
  Order({required this.address, required this.time});
}

class HistoryScreen extends StatelessWidget {
  final List<Shift> shiftHistory;
  final Function(Shift) onUpdate;

  const HistoryScreen({super.key, required this.shiftHistory, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    if (shiftHistory.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('История смен')),
        body: const Center(child: Text('Пока нет завершённых смен', style: TextStyle(fontSize: 18, color: Colors.grey))),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('История смен')),
      body: ListView.builder(
        itemCount: shiftHistory.length,
        itemBuilder: (context, index) {
          final s = shiftHistory[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ListTile(
              leading: const Icon(Icons.calendar_today, color: Colors.green),
              title: Text('${s.date.day}.${s.date.month}.${s.date.year}  ${s.date.hour}:${s.date.minute.toString().padLeft(2, '0')}'),
              subtitle: Text('${s.orders} заказов • ${_formatDuration(s.duration)}'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${s.totalCalculated.toStringAsFixed(0)} ₽', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  if (s.pendingWednesday > 0)
                    Text('${s.pendingWednesday.toStringAsFixed(0)} ₽', style: const TextStyle(color: Colors.orange, fontSize: 14)),
                ],
              ),
              onTap: () => _editShift(context, s),
            ),
          );
        },
      ),
    );
  }

  String _formatDuration(Duration d) {
    return '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}';
  }

  void _editShift(BuildContext context, Shift shift) {
    double tips = shift.tips;
    double bonuses = shift.bonuses;
    double tomorrow = shift.receivedTomorrow;
    double wednesday = shift.receivedWednesday;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Смена от ${shift.date.day}.${shift.date.month}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Расчёт: ${shift.totalCalculated.toStringAsFixed(0)} ₽', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(labelText: 'Чаевые (₽)'),
                keyboardType: TextInputType.number,
                controller: TextEditingController(text: tips.toStringAsFixed(0)),
                onChanged: (v) => tips = double.tryParse(v) ?? 0,
              ),
              TextField(
                decoration: const InputDecoration(labelText: 'Бонусы (₽)'),
                keyboardType: TextInputType.number,
                controller: TextEditingController(text: bonuses.toStringAsFixed(0)),
                onChanged: (v) => bonuses = double.tryParse(v) ?? 0,
              ),
              TextField(
                decoration: const InputDecoration(labelText: 'Пришло завтра (₽)'),
                keyboardType: TextInputType.number,
                controller: TextEditingController(text: tomorrow.toStringAsFixed(0)),
                onChanged: (v) => tomorrow = double.tryParse(v) ?? 0,
              ),
              TextField(
                decoration: const InputDecoration(labelText: 'Пришло в среду (₽)'),
                keyboardType: TextInputType.number,
                controller: TextEditingController(text: wednesday.toStringAsFixed(0)),
                onChanged: (v) => wednesday = double.tryParse(v) ?? 0,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          TextButton(
            onPressed: () {
              final updatedShift = Shift(
                date: shift.date,
                duration: shift.duration,
                orders: shift.orders,
                hourlyEarnings: shift.hourlyEarnings,
                orderEarnings: shift.orderEarnings,
                tips: tips,
                bonuses: bonuses,
                receivedTomorrow: tomorrow,
                receivedWednesday: wednesday,
              );
              onUpdate(updatedShift);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Смена обновлена')));
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }
}