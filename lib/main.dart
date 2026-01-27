import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'; // ADDED
import 'package:permission_handler/permission_handler.dart'; // ADDED

// --- GLOBAL STATE ---
ValueNotifier<double> globalBPM = ValueNotifier(0.0);
ValueNotifier<List<FlSpot>> bpmHistory = ValueNotifier([const FlSpot(0, 0)]);
ValueNotifier<bool> globalIsSleeping = ValueNotifier(false);
ValueNotifier<ThemeMode> globalTheme = ValueNotifier(ThemeMode.dark);
ValueNotifier<List<SleepSession>> historyList = ValueNotifier([]);
ValueNotifier<int> selectedNapDuration = ValueNotifier(20);

void main() => runApp(const AutoNapApp());

// --- MODELS ---
class SleepSession {
  final DateTime date;
  final int durationMinutes;
  final int spikeCount;
  SleepSession({required this.date, required this.durationMinutes, required this.spikeCount});
  Map<String, dynamic> toMap() => {'date': date.toIso8601String(), 'duration': durationMinutes, 'spikes': spikeCount};
  factory SleepSession.fromMap(Map<String, dynamic> map) => SleepSession(date: DateTime.parse(map['date']), durationMinutes: map['duration'], spikeCount: map['spikes']);
}

class ContactModel {
  String name; String phone; String priority;
  ContactModel({required this.name, required this.phone, required this.priority});
  Map<String, dynamic> toMap() => {'name': name, 'phone': phone, 'priority': priority};
  factory ContactModel.fromMap(Map<String, dynamic> map) => ContactModel(name: map['name'], phone: map['phone'], priority: map['priority']);
}

// --- MAIN APP ---
class AutoNapApp extends StatelessWidget {
  const AutoNapApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: globalTheme,
      builder: (context, mode, child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        themeMode: mode,
        theme: ThemeData(brightness: Brightness.light, primarySwatch: Colors.red, useMaterial3: true),
        darkTheme: ThemeData(brightness: Brightness.dark, primaryColor: Colors.redAccent, useMaterial3: true),
        home: const DashboardPage(),
      ),
    );
  }
}

// --- 1. DASHBOARD ---
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  DateTime? sleepStartTime;
  int currentSessionSpikes = 0;
  double xValue = 0;

  @override
  void initState() {
    super.initState();
    _loadAllData();
    _requestPermissions();
  }

  void _requestPermissions() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    startBluetoothScan();
  }

  void _loadAllData() async {
    final prefs = await SharedPreferences.getInstance();
    String? histData = prefs.getString('sleep_history');
    if (histData != null) {
      List decoded = jsonDecode(histData);
      historyList.value = decoded.map((m) => SleepSession.fromMap(m)).toList();
    }
    selectedNapDuration.value = prefs.getInt('nap_dur') ?? 20;
    bool isDark = prefs.getBool('is_dark') ?? true;
    globalTheme.value = isDark ? ThemeMode.dark : ThemeMode.light;
  }

  // --- BLUETOOTH LOGIC ---
  void startBluetoothScan() async {
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (r.device.platformName == "AutoNap_Sensor") {
          FlutterBluePlus.stopScan();
          _connectToDevice(r.device);
        }
      }
    });
  }

  void _connectToDevice(BluetoothDevice device) async {
    await device.connect();
    List<BluetoothService> services = await device.discoverServices();
    for (var s in services) {
      for (var c in s.characteristics) {
        if (c.uuid.toString() == "beb5483e-36e1-4688-b7f5-ea07361b26a8") {
          _subscribeToSensor(c);
        }
      }
    }
  }

  void _subscribeToSensor(BluetoothCharacteristic char) async {
    await char.setNotifyValue(true);
    char.lastValueStream.listen((value) {
      if (value.isNotEmpty) {
        double? newBpm = double.tryParse(String.fromCharCodes(value));
        if (newBpm != null) {
          globalBPM.value = newBpm;
          xValue += 0.5;
          List<FlSpot> newHistory = List.from(bpmHistory.value);
          if (newHistory.length > 50) newHistory.removeAt(0);
          newHistory.add(FlSpot(xValue, newBpm));
          bpmHistory.value = newHistory;
          if (globalIsSleeping.value && newBpm > 100) currentSessionSpikes++;
        }
      }
    });
  }

  void toggleSleep() async {
    if (!globalIsSleeping.value) {
      sleepStartTime = DateTime.now();
      currentSessionSpikes = 0;
      globalIsSleeping.value = true;
    } else {
      globalIsSleeping.value = false;
      if (sleepStartTime != null) {
        int dur = DateTime.now().difference(sleepStartTime!).inMinutes;
        _saveSession(SleepSession(date: DateTime.now(), durationMinutes: dur == 0 ? 1 : dur, spikeCount: currentSessionSpikes));
      }
    }
  }

  void _saveSession(SleepSession s) async {
    final prefs = await SharedPreferences.getInstance();
    historyList.value = [...historyList.value, s];
    await prefs.setString('sleep_history', jsonEncode(historyList.value.map((e) => e.toMap()).toList()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("AutoNap Hub")),
      body: Column(
        children: [
          _buildLiveHeader(),
          Expanded(
            child: GridView.count(
              padding: const EdgeInsets.all(15), crossAxisCount: 2, crossAxisSpacing: 15, mainAxisSpacing: 15,
              children: [
                _navTile(context, "Nap Timer", Icons.timer, Colors.blue, const NapDurationPage()),
                _navTile(context, "Contacts", Icons.contact_emergency, Colors.green, const ContactsPage()),
                _navTile(context, "History", Icons.history, Colors.orange, const HistoryPage()),
                _navTile(context, "Analysis", Icons.analytics, Colors.purple, const SummaryPage()),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: ValueListenableBuilder(
              valueListenable: globalIsSleeping,
              builder: (context, sleeping, _) => ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: sleeping ? Colors.indigo : Colors.redAccent, minimumSize: const Size(double.infinity, 60)),
                onPressed: toggleSleep,
                child: Text(sleeping ? "WAKE UP" : "START NAP", style: const TextStyle(color: Colors.white)),
              ),
            ),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CommonSettingsPage())), child: const Icon(Icons.settings)),
    );
  }

  Widget _buildLiveHeader() {
    return Container(
      padding: const EdgeInsets.all(20), margin: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          ValueListenableBuilder(valueListenable: globalBPM, builder: (context, val, _) => Column(children: [const Text("PULSE"), Text("${val.toInt()}", style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.red))])),
          ValueListenableBuilder(valueListenable: globalIsSleeping, builder: (context, val, _) => Column(children: [Icon(val ? Icons.nightlight : Icons.wb_sunny, color: val ? Colors.blue : Colors.orange), Text(val ? "SLEEPING" : "AWAKE")])),
        ],
      ),
    );
  }

  Widget _navTile(context, title, icon, color, target) => InkWell(
    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => target)),
    child: Container(
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.3))),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 40, color: color), Text(title)]),
    ),
  );
}

// --- 2. NAP DURATION PAGE ---
class NapDurationPage extends StatefulWidget {
  const NapDurationPage({super.key});
  @override
  State<NapDurationPage> createState() => _NapDurationPageState();
}

class _NapDurationPageState extends State<NapDurationPage> {
  final TextEditingController _customController = TextEditingController();
  void _save(int val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('nap_dur', val);
    selectedNapDuration.value = val;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Saved: $val min")));
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Set Nap Duration")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          const Text("Quick Select"),
          ValueListenableBuilder(valueListenable: selectedNapDuration, builder: (context, current, _) => Wrap(spacing: 10, children: [15, 20, 30, 45, 60].map((m) => ChoiceChip(label: Text("$m min"), selected: current == m, onSelected: (_) => _save(m))).toList())),
          const SizedBox(height: 30),
          TextField(controller: _customController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Custom Minutes", border: OutlineInputBorder())),
          ElevatedButton(onPressed: () { int? v = int.tryParse(_customController.text); if(v!=null) _save(v); }, child: const Text("Apply")),
          const Spacer(),
          ValueListenableBuilder(valueListenable: selectedNapDuration, builder: (context, val, _) => Text("Current: $val Min", style: const TextStyle(fontSize: 20, color: Colors.blue))),
        ]),
      ),
    );
  }
}

// --- 3. CONTACTS PAGE ---
class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});
  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  List<ContactModel> _contacts = [];
  @override
  void initState() { super.initState(); _load(); }
  _load() async {
    final prefs = await SharedPreferences.getInstance();
    String? encoded = prefs.getString('contacts_list');
    if (encoded != null) {
      List decoded = jsonDecode(encoded);
      setState(() => _contacts = decoded.map((m) => ContactModel.fromMap(m)).toList());
    }
  }
  _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('contacts_list', jsonEncode(_contacts.map((c) => c.toMap()).toList()));
  }
  void _showContactDialog({int? index}) {
    String name = index != null ? _contacts[index].name : "";
    String phone = index != null ? _contacts[index].phone : "";
    String priority = index != null ? _contacts[index].priority : "Medium";
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: Text(index == null ? "Add Contact" : "Edit Contact"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(onChanged: (v) => name = v, decoration: const InputDecoration(labelText: "Name"), controller: TextEditingController(text: name)),
        TextField(onChanged: (v) => phone = v, decoration: const InputDecoration(labelText: "Phone"), controller: TextEditingController(text: phone)),
        DropdownButton<String>(isExpanded: true, value: priority, items: ["High", "Medium", "Low"].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: (v) => setDialogState(() => priority = v!)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")), ElevatedButton(onPressed: () { setState(() { if (index == null) { _contacts.add(ContactModel(name: name, phone: phone, priority: priority)); } else { _contacts[index] = ContactModel(name: name, phone: phone, priority: priority); } }); _save(); Navigator.pop(ctx); }, child: const Text("Save"))],
    )));
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Emergency Contacts")),
      body: ListView.builder(itemCount: _contacts.length, itemBuilder: (ctx, i) => ListTile(title: Text(_contacts[i].name), subtitle: Text("${_contacts[i].phone} (${_contacts[i].priority})"), trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () { setState(() => _contacts.removeAt(i)); _save(); }), onTap: () => _showContactDialog(index: i))),
      floatingActionButton: FloatingActionButton(onPressed: () => _showContactDialog(), child: const Icon(Icons.add)),
    );
  }
}

// --- 4. HISTORY PAGE ---
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Sleep History")),
      body: ValueListenableBuilder(
        valueListenable: historyList,
        builder: (context, List<SleepSession> list, _) {
          if (list.isEmpty) return const Center(child: Text("No records."));
          int spikes = list.fold(0, (sum, item) => sum + item.spikeCount);
          return Column(children: [
            Padding(padding: const EdgeInsets.all(15), child: Row(children: [Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(15), child: Column(children: [const Text("Total Spikes"), Text("$spikes", style: const TextStyle(fontSize: 20, color: Colors.red))]))))])),
            SizedBox(height: 150, child: Padding(padding: const EdgeInsets.all(20), child: BarChart(BarChartData(barGroups: list.asMap().entries.map((e) => BarChartGroupData(x: e.key, barRods: [BarChartRodData(toY: e.value.durationMinutes.toDouble(), color: Colors.orange)])).toList(), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false))))),
            Expanded(child: ListView.builder(itemCount: list.length, itemBuilder: (context, i) { final s = list[list.length - 1 - i]; return ListTile(title: Text("${s.durationMinutes} min nap"), subtitle: Text("${s.date.day}/${s.date.month} • ${s.spikeCount} spikes")); })),
          ]);
        },
      ),
    );
  }
}

// --- 5. ANALYSIS PAGE ---
class SummaryPage extends StatelessWidget {
  const SummaryPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Pulse Analysis")),
      body: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
        const Text("Live Pulse Waveform"),
        const SizedBox(height: 30),
        SizedBox(height: 300, child: ValueListenableBuilder(valueListenable: bpmHistory, builder: (context, List<FlSpot> spots, _) => LineChart(LineChartData(minY: 40, maxY: 120, lineBarsData: [LineChartBarData(spots: spots, isCurved: true, color: Colors.redAccent, dotData: const FlDotData(show: false))])))),
      ])),
    );
  }
}

// --- 6. SETTINGS PAGE ---
class CommonSettingsPage extends StatelessWidget {
  const CommonSettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(children: [
        ValueListenableBuilder(valueListenable: globalTheme, builder: (context, mode, _) => SwitchListTile(title: const Text("Dark Mode"), value: mode == ThemeMode.dark, onChanged: (v) async { globalTheme.value = v ? ThemeMode.dark : ThemeMode.light; (await SharedPreferences.getInstance()).setBool('is_dark', v); })),
        ListTile(title: const Text("Clear History"), textColor: Colors.red, onTap: () async { (await SharedPreferences.getInstance()).remove('sleep_history'); historyList.value = []; }),
      ]),
    );
  }
}