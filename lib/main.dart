import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

// --- BLE CONSTANTS (Matching ESP32 Firmware) ---
const String kBleServiceName = "AutoNap_Sensor";
const String kBleServiceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
const String kBleCharacteristicUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

// --- GLOBAL STATE NOTIFIERS ---
final ValueNotifier<double> globalBPM = ValueNotifier<double>(0.0);
final ValueNotifier<List<FlSpot>> bpmHistory = ValueNotifier<List<FlSpot>>([
  const FlSpot(0, 0),
]);
final ValueNotifier<bool> globalIsSleeping = ValueNotifier<bool>(false);
final ValueNotifier<ThemeMode> globalThemeMode = ValueNotifier<ThemeMode>(
  ThemeMode.dark,
);
final ValueNotifier<List<SleepSession>> globalHistoryList =
    ValueNotifier<List<SleepSession>>([]);
final ValueNotifier<int> globalNapDuration = ValueNotifier<int>(20);
final ValueNotifier<String> globalAutoStatus = ValueNotifier<String>(
  "Waiting for ESP32 Sensor...",
);
final ValueNotifier<bool> globalIsBleConnected = ValueNotifier<bool>(false);
final ValueNotifier<bool> globalDemoMode = ValueNotifier<bool>(false);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AutoNapApp());
}

// --- DATA MODELS ---
class SleepSession {
  final String id;
  final DateTime date;
  final int durationMinutes;
  final int spikeCount;
  final double baselineBpm;
  final double avgSleepBpm;

  SleepSession({
    required this.id,
    required this.date,
    required this.durationMinutes,
    required this.spikeCount,
    required this.baselineBpm,
    required this.avgSleepBpm,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'date': date.toIso8601String(),
    'duration': durationMinutes,
    'spikes': spikeCount,
    'baseline': baselineBpm,
    'avgSleepBpm': avgSleepBpm,
  };

  factory SleepSession.fromMap(Map<String, dynamic> map) => SleepSession(
    id: map['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
    date: DateTime.parse(map['date']),
    durationMinutes: map['duration'] ?? 20,
    spikeCount: map['spikes'] ?? 0,
    baselineBpm: (map['baseline'] as num?)?.toDouble() ?? 72.0,
    avgSleepBpm: (map['avgSleepBpm'] as num?)?.toDouble() ?? 64.0,
  );
}

class ContactModel {
  final String id;
  final String name;
  final String phone;
  final String priority; // High, Medium, Low
  final String relation;

  ContactModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.priority,
    required this.relation,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'phone': phone,
    'priority': priority,
    'relation': relation,
  };

  factory ContactModel.fromMap(Map<String, dynamic> map) => ContactModel(
    id: map['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
    name: map['name'] ?? '',
    phone: map['phone'] ?? '',
    priority: map['priority'] ?? 'Medium',
    relation: map['relation'] ?? 'Caregiver',
  );
}

// --- MAIN APPLICATION ENTRY ---
class AutoNapApp extends StatefulWidget {
  const AutoNapApp({super.key});

  @override
  State<AutoNapApp> createState() => _AutoNapAppState();
}

class _AutoNapAppState extends State<AutoNapApp> {
  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('is_dark') ?? true;
    globalThemeMode.value = isDark ? ThemeMode.dark : ThemeMode.light;

    final savedNapDur = prefs.getInt('nap_duration') ?? 20;
    globalNapDuration.value = savedNapDur;

    final String? historyJson = prefs.getString('sleep_history_json');
    if (historyJson != null && historyJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(historyJson);
        globalHistoryList.value = decoded
            .map((m) => SleepSession.fromMap(m))
            .toList();
      } catch (e) {
        debugPrint("Error loading history: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: globalThemeMode,
      builder: (context, mode, child) {
        return MaterialApp(
          title: 'AutoNap',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorSchemeSeed: Colors.deepOrange,
            scaffoldBackgroundColor: const Color(0xFFF8F9FA),
            cardTheme: CardThemeData(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorSchemeSeed: Colors.redAccent,
            scaffoldBackgroundColor: const Color(0xFF0F172A),
            cardTheme: CardThemeData(
              color: const Color(0xFF1E293B),
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          home: const MainNavigationScreen(),
        );
      },
    );
  }
}

// --- MAIN NAVIGATION CONTAINER ---
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    DashboardView(),
    PulseWaveformView(),
    AnalyticsView(),
    EmergencyContactsView(),
    SettingsView(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _pages[_currentIndex],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart),
            selectedIcon: Icon(Icons.show_chart_rounded),
            label: 'Pulse Wave',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: 'Analytics',
          ),
          NavigationDestination(
            icon: Icon(Icons.health_and_safety_outlined),
            selectedIcon: Icon(Icons.health_and_safety),
            label: 'Emergency',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// --- 1. DASHBOARD VIEW (CENTRAL HUB) ---
class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView>
    with SingleTickerProviderStateMixin {
  // Logic variables
  double _baselineBPM = 0.0;
  final List<double> _initialReadings = [];
  int _lowBpmStreakCount = 0;
  int _currentSpikesCount = 0;

  Timer? _napCountdownTimer;
  Timer? _demoTimer;
  int _remainingNapSeconds = 0;
  double _xGraphValue = 0.0;

  late AnimationController _pulseAnimController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseAnimController, curve: Curves.easeInOut),
    );

    _initPermissionsAndBLE();
    _listenToBpmStream();
  }

  @override
  void dispose() {
    _pulseAnimController.dispose();
    _napCountdownTimer?.cancel();
    _demoTimer?.cancel();
    _scanSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _connectedDevice?.disconnect();
    super.dispose();
  }

  void _initPermissionsAndBLE() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    _startBleScan();
  }

  // BLE Scan matching ESP32 firmware
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  BluetoothDevice? _connectedDevice;

  void _startBleScan() {
    if (globalDemoMode.value) return;

    print("Starting BLE Scan for '$kBleServiceName'...");
    globalAutoStatus.value = "Scanning for ESP32 Sensor...";

    // Cancel any previous scan subscription to avoid duplicates
    _scanSubscription?.cancel();

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        final advName = r.advertisementData.advName;
        final platName = r.device.platformName;
        print("Scanned device — advName: '$advName', platformName: '$platName'");

        if (advName == kBleServiceName || platName == kBleServiceName) {
          print("Found target device! Stopping scan and connecting...");
          globalAutoStatus.value = "Found ESP32! Connecting...";
          FlutterBluePlus.stopScan();
          _scanSubscription?.cancel();
          _connectToDevice(r.device);
          return;
        }
      }
    });

    // If scan times out without finding the device, retry
    Future.delayed(const Duration(seconds: 16), () {
      if (!globalIsBleConnected.value && !globalDemoMode.value) {
        print("Scan timed out. Retrying...");
        globalAutoStatus.value = "ESP32 not found. Retrying scan...";
        _startBleScan();
      }
    });
  }

  void _connectToDevice(BluetoothDevice device) async {
    try {
      // CRITICAL FIX: If already connected (e.g. from hot-reload),
      // disconnect first so ESP32's onConnect callback fires fresh.
      // This ensures ESP32 sets deviceConnected = true on its side.
      if ((await device.connectionState.first) ==
          BluetoothConnectionState.connected) {
        print("Device already connected — disconnecting first for clean reconnect...");
        globalAutoStatus.value = "Reconnecting to ESP32...";
        await device.disconnect();
        await Future.delayed(const Duration(seconds: 1));
      }

      print("Connecting to ESP32...");
      await device.connect(autoConnect: false).timeout(const Duration(seconds: 10));

      // Listen for connection state changes (auto-reconnect on drop)
      _connectionStateSubscription?.cancel();
      _connectionStateSubscription = device.connectionState.listen((state) {
        print("BLE Connection State: $state");
        if (state == BluetoothConnectionState.disconnected) {
          print("⚠ ESP32 disconnected! Will retry scan in 3 seconds...");
          globalIsBleConnected.value = false;
          globalAutoStatus.value = "ESP32 Disconnected. Reconnecting...";
          _connectedDevice = null;
          Future.delayed(const Duration(seconds: 3), () {
            if (!globalDemoMode.value) _startBleScan();
          });
        }
      });

      _connectedDevice = device;

      // Wait for connection to stabilise before discovering services
      await Future.delayed(const Duration(seconds: 2));

      print("Discovering Services...");
      globalAutoStatus.value = "Connected! Discovering services...";
      List<BluetoothService> services = await device.discoverServices();

      bool foundCharacteristic = false;
      for (var s in services) {
        print("Found Service: ${s.serviceUuid}");
        if (s.serviceUuid.toString().toLowerCase() ==
            kBleServiceUuid.toLowerCase()) {
          for (var c in s.characteristics) {
            print("  Found Characteristic: ${c.characteristicUuid}  "
                "notify=${c.properties.notify}  read=${c.properties.read}");
            if (c.characteristicUuid.toString().toLowerCase() ==
                    kBleCharacteristicUuid.toLowerCase() &&
                c.properties.notify) {
              await _subscribeToCharacteristic(c, device);
              foundCharacteristic = true;
              print("✅ Successfully subscribed to Pulse Data!");
              globalIsBleConnected.value = true;
              globalAutoStatus.value =
                  "ESP32 Connected & Subscribed! Waiting for heartbeat data...";
            }
          }
        }
      }

      if (!foundCharacteristic) {
        print("⚠ Connected but could NOT find the pulse characteristic!");
        print("  Expected service:        $kBleServiceUuid");
        print("  Expected characteristic: $kBleCharacteristicUuid");
        globalAutoStatus.value = "Error: Pulse characteristic not found on ESP32!";
      }
    } catch (e) {
      globalIsBleConnected.value = false;
      print("❌ Error during BLE connection: $e");
      globalAutoStatus.value = "Connection failed: $e. Retrying...";
      Future.delayed(const Duration(seconds: 3), () => _startBleScan());
    }
  }

  Future<void> _subscribeToCharacteristic(
      BluetoothCharacteristic char, BluetoothDevice device) async {
    // CRITICAL: Set up the listener BEFORE enabling notifications
    final subscription = char.onValueReceived.listen((value) {
      if (value.isNotEmpty) {
        print('Raw BLE bytes: $value');
        String strVal = String.fromCharCodes(value).trim();
        print('Decoded string: "$strVal"');
        double? parseBpm = double.tryParse(strVal);

        if (parseBpm == null && value.isNotEmpty) {
          parseBpm = value.first.toDouble();
          print('Fallback byte parse: $parseBpm');
        }

        if (parseBpm != null && parseBpm > 40 && parseBpm < 200) {
          globalBPM.value = parseBpm;
          print('✅ BPM updated: $parseBpm');
        }
      }
    });

    device.cancelWhenDisconnected(subscription);

    // Enable notifications
    await char.setNotifyValue(true);
    print("Notifications enabled on ${char.characteristicUuid}");

    // DIAGNOSTIC: Do a manual read right after subscribing to test data flow
    if (char.properties.read) {
      try {
        List<int> readVal = await char.read();
        print("📖 Manual read value: $readVal");
        if (readVal.isNotEmpty) {
          String readStr = String.fromCharCodes(readVal).trim();
          print("📖 Manual read decoded: \"$readStr\"");
          double? readBpm = double.tryParse(readStr);
          if (readBpm != null && readBpm > 40 && readBpm < 200) {
            globalBPM.value = readBpm;
            print("✅ BPM from manual read: $readBpm");
          }
        } else {
          print("📖 Manual read returned empty — ESP32 hasn't detected a heartbeat yet.");
          print("   Check: Is your finger placed firmly on the pulse sensor?");
          print("   Check: Does ESP32 Serial Monitor show '♥ Heartbeat!' messages?");
          globalAutoStatus.value =
              "ESP32 Connected ✓ — Place finger on sensor. Waiting for heartbeat...";
        }
      } catch (e) {
        print("📖 Manual read failed: $e");
      }
    }
  }

  // Listener for Sleep Detection Logic & Waveform Update
  void _listenToBpmStream() {
    globalBPM.addListener(() {
      double currentBpm = globalBPM.value;
      if (currentBpm <= 0) return;

      // Update graph dataset
      _xGraphValue += 1.0;
      List<FlSpot> currentSpots = List.from(bpmHistory.value);
      if (currentSpots.length > 40) currentSpots.removeAt(0);
      currentSpots.add(FlSpot(_xGraphValue, currentBpm));
      bpmHistory.value = currentSpots;

      // Step 1: Establish Resting Baseline BPM (First 10 valid readings)
      if (_baselineBPM == 0.0) {
        _initialReadings.add(currentBpm);
        globalAutoStatus.value =
            "Calibrating Resting Baseline (${_initialReadings.length}/10)...";
        if (_initialReadings.length >= 10) {
          double sum = _initialReadings.reduce((a, b) => a + b);
          _baselineBPM = sum / _initialReadings.length;
          globalAutoStatus.value =
              "Baseline Set: ${_baselineBPM.toStringAsFixed(1)} BPM. Awake & Monitoring...";
        }
        return;
      }

      // Step 2: Automatic Sleep Detection Algorithm
      // Detects 10-12% sustained drop in BPM below baseline
      double sleepThreshold = _baselineBPM * 0.89; // ~11% drop
      if (!globalIsSleeping.value) {
        if (currentBpm <= sleepThreshold) {
          _lowBpmStreakCount++;
          globalAutoStatus.value =
              "Sleep Tendency Detected! Sustained ($_lowBpmStreakCount/10)...";
          if (_lowBpmStreakCount >= 10) {
            _triggerSleepConfirmed();
          }
        } else {
          _lowBpmStreakCount = 0;
          globalAutoStatus.value =
              "Monitoring Awake Heart Rate (Baseline: ${_baselineBPM.round()} BPM)";
        }
      } else {
        // Step 3: Emergency Spike Detection while Sleeping (>120 BPM or sudden spike >25%)
        if (currentBpm > 120.0 || currentBpm > (_baselineBPM * 1.25)) {
          _currentSpikesCount++;
          _triggerEmergencySpikeAlert(currentBpm);
        }
      }
    });
  }

  void _triggerSleepConfirmed() {
    globalIsSleeping.value = true;
    globalAutoStatus.value =
        "Sleep Confirmed! Smart Nap Alarm Countdown Started.";

    _remainingNapSeconds = globalNapDuration.value * 60;
    _napCountdownTimer?.cancel();

    _napCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_remainingNapSeconds > 0) {
          _remainingNapSeconds--;
        } else {
          timer.cancel();
          _triggerWakeUpAlarm();
        }
      });
    });
  }

  void _triggerWakeUpAlarm() {
    globalAutoStatus.value = "ALARM: NAP COMPLETE! TIME TO WAKE UP!";

    // Save session log
    final newSession = SleepSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: DateTime.now(),
      durationMinutes: globalNapDuration.value,
      spikeCount: _currentSpikesCount,
      baselineBpm: _baselineBPM,
      avgSleepBpm: globalBPM.value,
    );

    List<SleepSession> updatedList = List.from(globalHistoryList.value)
      ..add(newSession);
    globalHistoryList.value = updatedList;
    _saveHistoryToPrefs(updatedList);

    // Periodic vibration alarm until dismissed
    Timer? alarmVibrationTimer;
    alarmVibrationTimer = Timer.periodic(const Duration(milliseconds: 600), (
      t,
    ) {
      HapticFeedback.vibrate();
    });

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.alarm_on, color: Colors.deepOrange, size: 32),
            SizedBox(width: 10),
            Text("⏰ WAKE UP ALARM"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Your Smart Nap has completed! You rested peacefully.",
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.deepOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Nap Duration:"),
                      Text(
                        "${globalNapDuration.value} mins",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Spikes Detected:"),
                      Text(
                        "$_currentSpikesCount",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _currentSpikesCount > 0
                              ? Colors.red
                              : Colors.green,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              alarmVibrationTimer?.cancel();
              Navigator.pop(ctx);
              setState(() {
                globalIsSleeping.value = false;
                _currentSpikesCount = 0;
                globalAutoStatus.value = "Awake. Resting baseline active.";
              });
            },
            child: const Text("Dismiss & Finish Nap"),
          ),
        ],
      ),
    ).then((_) {
      alarmVibrationTimer?.cancel();
    });
  }

  void _triggerEmergencySpikeAlert(double spikeBpm) async {
    if (!mounted) return;

    // Trigger haptic warning pattern
    HapticFeedback.vibrate();
    await Future.delayed(const Duration(milliseconds: 150));
    HapticFeedback.vibrate();

    // Load contacts dynamically to show the notified people
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('contacts_json');
    List<ContactModel> currentContacts = [];

    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final List decoded = jsonDecode(jsonStr);
        currentContacts = decoded.map((m) => ContactModel.fromMap(m)).toList();
      } catch (e) {
        debugPrint("Error loading contacts in spike: $e");
      }
    } else {
      // Default fallback
      currentContacts = [
        ContactModel(
          id: '1',
          name: 'Dr. Smith (Primary Physician)',
          phone: '+1 555 019 2831',
          priority: 'High',
          relation: 'Doctor',
        ),
        ContactModel(
          id: '2',
          name: 'Alex (Caregiver)',
          phone: '+1 555 014 9920',
          priority: 'Medium',
          relation: 'Family',
        ),
      ];
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF450A0A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.redAccent, width: 2),
        ),
        title: const Row(
          children: [
            Icon(Icons.gpp_bad, color: Colors.redAccent, size: 32),
            SizedBox(width: 10),
            Text(
              "🚨 SPIKE ALERT",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Abnormal Heart Rate: ${spikeBpm.round()} BPM detected while sleeping!",
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
            const SizedBox(height: 15),
            const Text(
              "NOTIFYING PRIORITY CONTACTS:",
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
                fontSize: 11,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 120),
              width: double.infinity,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: currentContacts.length,
                itemBuilder: (cCtx, index) {
                  final c = currentContacts[index];
                  return Card(
                    color: Colors.black26,
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.sms,
                        color: Colors.greenAccent,
                        size: 20,
                      ),
                      title: Text(
                        c.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      subtitle: Text(
                        "${c.phone} • ${c.priority} Priority",
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Dismiss Alert"),
          ),
        ],
      ),
    );
  }

  Future<void> _saveHistoryToPrefs(List<SleepSession> list) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(list.map((s) => s.toMap()).toList());
    await prefs.setString('sleep_history_json', jsonString);
  }

  void _toggleDemoSimulation() {
    setState(() {
      globalDemoMode.value = !globalDemoMode.value;
      if (globalDemoMode.value) {
        globalAutoStatus.value =
            "Demo Simulator Active. Generating test HR stream...";
        _startDemoStream();
      } else {
        _demoTimer?.cancel();
        globalAutoStatus.value =
            "Demo Mode Stopped. Waiting for BLE Hardware...";
      }
    });
  }

  void _startDemoStream() {
    _demoTimer?.cancel();
    double step = 0;
    _demoTimer = Timer.periodic(const Duration(milliseconds: 900), (t) {
      step += 1;
      double simulatedBpm;
      if (step < 12) {
        // Awake baseline (72-76 BPM)
        simulatedBpm = 74.0 + (Random().nextDouble() * 3 - 1.5);
      } else if (step < 25) {
        // Falling asleep (12% drop down to 63-65 BPM)
        simulatedBpm = 64.0 + (Random().nextDouble() * 2 - 1.0);
      } else if (step == 28) {
        // Simulated emergency HR spike (128 BPM)
        simulatedBpm = 128.0;
      } else {
        // Normal sleep HR
        simulatedBpm = 63.0 + (Random().nextDouble() * 2 - 1.0);
      }
      globalBPM.value = simulatedBpm;
    });
  }

  String _formatSeconds(int totalSecs) {
    final mins = totalSecs ~/ 60;
    final secs = totalSecs % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          children: [
            Text(
              "AutoNap",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            Text(
              "IoT Exam & Study Companion",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              globalDemoMode.value
                  ? Icons.play_circle_fill
                  : Icons.play_circle_outline,
              color: globalDemoMode.value ? Colors.amber : Colors.grey,
            ),
            tooltip: "Toggle Demo Simulator",
            onPressed: _toggleDemoSimulation,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Status Banner
            ValueListenableBuilder<String>(
              valueListenable: globalAutoStatus,
              builder: (context, statusMsg, _) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: globalIsSleeping.value
                        ? Colors.indigo.withValues(alpha: 0.2)
                        : Colors.deepOrange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: globalIsSleeping.value
                          ? Colors.indigoAccent
                          : Colors.deepOrange,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        globalIsSleeping.value ? Icons.bedtime : Icons.sensors,
                        color: globalIsSleeping.value
                            ? Colors.indigoAccent
                            : Colors.deepOrange,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          statusMsg,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 20),

            // Live BPM Circular Gauge Card
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 24,
                  horizontal: 16,
                ),
                child: Column(
                  children: [
                    ValueListenableBuilder<double>(
                      valueListenable: globalBPM,
                      builder: (context, bpmVal, _) {
                        return Column(
                          children: [
                            ScaleTransition(
                              scale: _pulseAnimation,
                              child: Icon(
                                Icons.favorite,
                                color: bpmVal > 120
                                    ? Colors.red
                                    : (bpmVal > 0
                                          ? Colors.redAccent
                                          : Colors.grey),
                                size: 54,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              bpmVal > 0 ? "${bpmVal.toInt()}" : "--",
                              style: TextStyle(
                                fontSize: 64,
                                fontWeight: FontWeight.bold,
                                color: bpmVal > 120
                                    ? Colors.red
                                    : (isDark ? Colors.white : Colors.black87),
                              ),
                            ),
                            const Text(
                              "BEATS PER MINUTE (BPM)",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 20),

                    // Metrics Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildMetricPill(
                          "Baseline",
                          _baselineBPM > 0
                              ? "${_baselineBPM.round()} BPM"
                              : "--",
                          Icons.bar_chart,
                        ),
                        ValueListenableBuilder<bool>(
                          valueListenable: globalIsSleeping,
                          builder: (context, sleeping, _) {
                            return _buildMetricPill(
                              "Status",
                              sleeping ? "Napping 😴" : "Awake 🧠",
                              sleeping
                                  ? Icons.nightlight_round
                                  : Icons.wb_sunny,
                            );
                          },
                        ),
                        _buildMetricPill(
                          "Spikes",
                          "$_currentSpikesCount",
                          Icons.warning_amber,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Nap Countdown Timer Card
            ValueListenableBuilder<bool>(
              valueListenable: globalIsSleeping,
              builder: (context, isSleeping, _) {
                return Card(
                  color: isSleeping
                      ? Colors.indigo.withValues(alpha: 0.3)
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.timer, color: Colors.deepOrange),
                                SizedBox(width: 8),
                                Text(
                                  "Smart Adaptive Alarm",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Chip(
                              label: Text(
                                isSleeping
                                    ? "COUNTDOWN ACTIVE"
                                    : "WAITING FOR SLEEP",
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              backgroundColor: isSleeping
                                  ? Colors.green
                                  : Colors.grey.shade700,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: Text(
                            isSleeping
                                ? _formatSeconds(_remainingNapSeconds)
                                : "${globalNapDuration.value}:00",
                            style: const TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              color: Colors.deepOrangeAccent,
                            ),
                          ),
                        ),
                        const Center(
                          child: Text(
                            "Timer countdown begins automatically upon sleep confirmation",
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 20),

            // Nap Duration Quick Selector Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Nap Target Duration",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ValueListenableBuilder<int>(
                      valueListenable: globalNapDuration,
                      builder: (context, currentDur, _) {
                        return Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [15, 20, 30, 60].map((mins) {
                            final isSelected = currentDur == mins;
                            return ChoiceChip(
                              label: Text("$mins Mins"),
                              selected: isSelected,
                              selectedColor: Colors.deepOrange,
                              labelStyle: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : (isDark ? Colors.white : Colors.black87),
                                fontWeight: FontWeight.bold,
                              ),
                              onSelected: (val) async {
                                if (val) {
                                  globalNapDuration.value = mins;
                                  final prefs =
                                      await SharedPreferences.getInstance();
                                  await prefs.setInt('nap_duration', mins);
                                }
                              },
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricPill(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.deepOrangeAccent),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}

// --- 2. PULSE WAVEFORM VIEW ---
class PulseWaveformView extends StatelessWidget {
  const PulseWaveformView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Pulse Analysis & Waveform"),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Real-time ESP32 Heart Rate Stream",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Text(
              "Continuous optical PPG pulse acquisition",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.only(
                    right: 16,
                    left: 6,
                    top: 24,
                    bottom: 12,
                  ),
                  child: ValueListenableBuilder<List<FlSpot>>(
                    valueListenable: bpmHistory,
                    builder: (context, spots, _) {
                      return LineChart(
                        LineChartData(
                          minY: 40,
                          maxY: 140,
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: true,
                            getDrawingHorizontalLine: (val) => FlLine(
                              color: isDark ? Colors.white10 : Colors.black12,
                              strokeWidth: 1,
                            ),
                            getDrawingVerticalLine: (val) => FlLine(
                              color: isDark ? Colors.white10 : Colors.black12,
                              strokeWidth: 1,
                            ),
                          ),
                          titlesData: FlTitlesData(
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            bottomTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 34,
                                getTitlesWidget: (value, meta) {
                                  return Text(
                                    "${value.toInt()}",
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: spots,
                              isCurved: true,
                              color: Colors.redAccent,
                              barWidth: 3,
                              isStrokeCapRound: true,
                              dotData: const FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                color: Colors.redAccent.withValues(alpha: 0.15),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.info_outline,
                  color: Colors.deepOrange,
                ),
                title: const Text(
                  "ESP32 BLE Pulse Telemetry",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: ValueListenableBuilder<double>(
                  valueListenable: globalBPM,
                  builder: (context, bpm, _) {
                    return Text(
                      "Current raw pulse input: ${bpm.toStringAsFixed(1)} BPM",
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- 3. SLEEP ANALYTICS VIEW ---
class AnalyticsView extends StatelessWidget {
  const AnalyticsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Monthly Sleep Analytics"),
        centerTitle: true,
      ),
      body: ValueListenableBuilder<List<SleepSession>>(
        valueListenable: globalHistoryList,
        builder: (context, history, _) {
          if (history.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  const Text(
                    "No sleep sessions recorded yet.",
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Complete your first AutoNap to see analytics!",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          int totalNaps = history.length;
          int totalMinutes = history.fold(
            0,
            (sum, s) => sum + s.durationMinutes,
          );
          int totalSpikes = history.fold(0, (sum, s) => sum + s.spikeCount);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary Cards Row
                Row(
                  children: [
                    Expanded(
                      child: _buildStatTile(
                        "Total Naps",
                        "$totalNaps",
                        Icons.bedtime,
                        Colors.indigo,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildStatTile(
                        "Total Rest",
                        "$totalMinutes m",
                        Icons.timer,
                        Colors.deepOrange,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildStatTile(
                        "Spikes Detected",
                        "$totalSpikes",
                        Icons.warning,
                        Colors.red,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Bar Chart Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Nap Duration History (Minutes)",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 180,
                          child: BarChart(
                            BarChartData(
                              barGroups: history.asMap().entries.map((entry) {
                                return BarChartGroupData(
                                  x: entry.key,
                                  barRods: [
                                    BarChartRodData(
                                      toY: entry.value.durationMinutes
                                          .toDouble(),
                                      color: Colors.deepOrange,
                                      width: 14,
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(4),
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                              titlesData: const FlTitlesData(show: false),
                              borderData: FlBorderData(show: false),
                              gridData: const FlGridData(show: false),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // History List
                const Text(
                  "Recent Nap Sessions Log",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),

                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: history.length,
                  itemBuilder: (context, i) {
                    final session = history[history.length - 1 - i];
                    final dateStr =
                        "${session.date.day}/${session.date.month}/${session.date.year} ${session.date.hour.toString().padLeft(2, '0')}:${session.date.minute.toString().padLeft(2, '0')}";
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.deepOrange.withValues(
                            alpha: 0.15,
                          ),
                          child: const Icon(
                            Icons.nightlight_round,
                            color: Colors.deepOrange,
                          ),
                        ),
                        title: Text(
                          "${session.durationMinutes} Minute Smart Nap",
                        ),
                        subtitle: Text(
                          "$dateStr • Baseline: ${session.baselineBpm.round()} BPM",
                        ),
                        trailing: Chip(
                          label: Text(
                            "${session.spikeCount} Spikes",
                            style: TextStyle(
                              fontSize: 11,
                              color: session.spikeCount > 0
                                  ? Colors.red
                                  : Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          backgroundColor: session.spikeCount > 0
                              ? Colors.red.withValues(alpha: 0.1)
                              : Colors.green.withValues(alpha: 0.1),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatTile(String label, String val, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(
              val,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

// --- 4. EMERGENCY CONTACTS VIEW ---
class EmergencyContactsView extends StatefulWidget {
  const EmergencyContactsView({super.key});

  @override
  State<EmergencyContactsView> createState() => _EmergencyContactsViewState();
}

class _EmergencyContactsViewState extends State<EmergencyContactsView> {
  List<ContactModel> _contacts = [];

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('contacts_json');
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final List decoded = jsonDecode(jsonStr);
        setState(() {
          _contacts = decoded.map((m) => ContactModel.fromMap(m)).toList();
        });
      } catch (e) {
        debugPrint("Error loading contacts: $e");
      }
    } else {
      // Default initial contact
      setState(() {
        _contacts = [
          ContactModel(
            id: '1',
            name: 'Dr. Smith (Primary Physician)',
            phone: '+1 555 019 2831',
            priority: 'High',
            relation: 'Doctor',
          ),
          ContactModel(
            id: '2',
            name: 'Alex (Caregiver)',
            phone: '+1 555 014 9920',
            priority: 'Medium',
            relation: 'Family',
          ),
        ];
      });
    }
  }

  Future<void> _saveContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(_contacts.map((c) => c.toMap()).toList());
    await prefs.setString('contacts_json', jsonStr);
  }

  void _showContactDialog({ContactModel? existing, int? index}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final relationCtrl = TextEditingController(
      text: existing?.relation ?? 'Caregiver',
    );
    String priority = existing?.priority ?? 'High';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              existing == null ? "Add Emergency Contact" : "Edit Contact",
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: "Contact Name"),
                ),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: "Phone Number"),
                ),
                TextField(
                  controller: relationCtrl,
                  decoration: const InputDecoration(
                    labelText: "Relationship (Doctor/Parent/Friend)",
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: priority,
                  decoration: const InputDecoration(
                    labelText: "Priority Level",
                  ),
                  items: ['High', 'Medium', 'Low'].map((p) {
                    return DropdownMenuItem(
                      value: p,
                      child: Text("Priority: $p"),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => priority = val);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  if (nameCtrl.text.trim().isEmpty ||
                      phoneCtrl.text.trim().isEmpty)
                    return;
                  final newC = ContactModel(
                    id:
                        existing?.id ??
                        DateTime.now().millisecondsSinceEpoch.toString(),
                    name: nameCtrl.text.trim(),
                    phone: phoneCtrl.text.trim(),
                    priority: priority,
                    relation: relationCtrl.text.trim(),
                  );
                  setState(() {
                    if (index == null) {
                      _contacts.add(newC);
                    } else {
                      _contacts[index] = newC;
                    }
                  });
                  _saveContacts();
                  Navigator.pop(ctx);
                },
                child: const Text("Save"),
              ),
            ],
          );
        },
      ),
    );
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'High':
        return Colors.red;
      case 'Medium':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Emergency Contacts"),
        centerTitle: true,
      ),
      body: _contacts.isEmpty
          ? const Center(child: Text("No emergency contacts saved."))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _contacts.length,
              itemBuilder: (context, i) {
                final c = _contacts[i];
                final priorityColor = _getPriorityColor(c.priority);
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: priorityColor.withValues(alpha: 0.2),
                      child: Icon(Icons.person, color: priorityColor),
                    ),
                    title: Text(
                      c.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text("${c.phone} • ${c.relation}"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Chip(
                          label: Text(
                            c.priority,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          backgroundColor: priorityColor,
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                          ),
                          onPressed: () {
                            setState(() => _contacts.removeAt(i));
                            _saveContacts();
                          },
                        ),
                      ],
                    ),
                    onTap: () => _showContactDialog(existing: c, index: i),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        onPressed: () => _showContactDialog(),
        icon: const Icon(Icons.add),
        label: const Text("Add Contact"),
      ),
    );
  }
}

// --- 5. SETTINGS VIEW ---
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings & Connection"),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Dark Mode Toggle
          ValueListenableBuilder<ThemeMode>(
            valueListenable: globalThemeMode,
            builder: (context, mode, _) {
              final isDark = mode == ThemeMode.dark;
              return Card(
                child: SwitchListTile(
                  secondary: const Icon(
                    Icons.dark_mode,
                    color: Colors.deepOrange,
                  ),
                  title: const Text(
                    "Dark Theme",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    "Reduces eye strain during late-night study",
                  ),
                  value: isDark,
                  onChanged: (val) async {
                    globalThemeMode.value = val
                        ? ThemeMode.dark
                        : ThemeMode.light;
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('is_dark', val);
                  },
                ),
              );
            },
          ),

          const SizedBox(height: 12),

          // Demo Mode Toggle
          ValueListenableBuilder<bool>(
            valueListenable: globalDemoMode,
            builder: (context, demo, _) {
              return Card(
                child: SwitchListTile(
                  secondary: const Icon(Icons.extension, color: Colors.amber),
                  title: const Text(
                    "Demo / Simulator Mode",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    "Simulates pulse sensor & sleep detection without physical ESP32",
                  ),
                  value: demo,
                  onChanged: (val) {
                    globalDemoMode.value = val;
                    if (val) {
                      globalAutoStatus.value =
                          "Demo Simulator Active. Generating test HR stream...";
                    } else {
                      globalAutoStatus.value = "Waiting for ESP32 Sensor...";
                    }
                  },
                ),
              );
            },
          ),

          const SizedBox(height: 12),

          // BLE Device Status Card
          Card(
            child: ListTile(
              leading: const Icon(Icons.bluetooth, color: Colors.blue),
              title: const Text("Hardware BLE Connection"),
              subtitle: Text("Target: $kBleServiceName ($kBleServiceUuid)"),
              trailing: ValueListenableBuilder<bool>(
                valueListenable: globalIsBleConnected,
                builder: (context, connected, _) {
                  return Icon(
                    connected ? Icons.check_circle : Icons.offline_bolt,
                    color: connected ? Colors.green : Colors.grey,
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Reset History
          Card(
            child: ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text(
                "Clear All Sleep Records",
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text("Confirm Reset"),
                    content: const Text(
                      "Are you sure you want to delete all saved sleep logs?",
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text("Cancel"),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text("Delete All"),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  globalHistoryList.value = [];
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('sleep_history_json');
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
