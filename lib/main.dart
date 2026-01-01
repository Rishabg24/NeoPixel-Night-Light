import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:convert';

void main() {
  runApp(const NightlightApp());
}

class NightlightApp extends StatelessWidget {
  const NightlightApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nightlight Control',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        primaryColor: const Color(0xFF6C63FF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C63FF),
          secondary: Color(0xFF03DAC6),
          surface: Color(0xFF1E1E1E),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool isScanning = false;
  List<ScanResult> scanResults = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  bool _isAutoReconnecting = false;
  String? savedDeviceId;

  static final Guid uartServiceUuid = Guid(
    "6e400001-b5a3-f393-e0a9-e50e24dcca9e",
  );

  @override
  void initState() {
    super.initState();
    _initializeBluetooth();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reloadSavedDeviceAndStartMonitoring();
  }

  Future<void> _reloadSavedDeviceAndStartMonitoring() async {
    final prefs = await SharedPreferences.getInstance();
    savedDeviceId = prefs.getString('saved_device_id');

    if (savedDeviceId != null && !_isAutoReconnecting) {
      startContinuousMonitoring();
    }
  }

  @override
  void dispose() {
    _isAutoReconnecting = false;
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _initializeBluetooth() async {
    await Future.delayed(const Duration(milliseconds: 500));
    var adapterState = await FlutterBluePlus.adapterState.first;

    if (adapterState != BluetoothAdapterState.on) {
      await FlutterBluePlus.adapterState
          .firstWhere((state) => state == BluetoothAdapterState.on)
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => BluetoothAdapterState.off,
          );
    }
    await checkForSavedDevice();
  }

  Future<void> checkForSavedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    savedDeviceId = prefs.getString('saved_device_id');
    if (savedDeviceId != null) {
      startContinuousMonitoring();
    }
  }

  Future<void> startContinuousMonitoring() async {
    if (_isAutoReconnecting) return;
    if (savedDeviceId == null) return;

    _isAutoReconnecting = true;
    int scanCount = 0;

    while (mounted && savedDeviceId != null && _isAutoReconnecting) {
      scanCount++;
      try {
        final connectedDevices = await FlutterBluePlus.connectedSystemDevices;
        for (var device in connectedDevices) {
          if (device.remoteId.toString() == savedDeviceId) {
            _isAutoReconnecting = false;
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => ControlScreen(device: device),
                ),
              );
            }
            return;
          }
        }

        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));

        bool deviceFound = false;
        _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
          if (!deviceFound && results.isNotEmpty) {
            for (var result in results) {
              if (result.device.remoteId.toString() == savedDeviceId) {
                deviceFound = true;
                FlutterBluePlus.stopScan();
                _scanSubscription?.cancel();
                _isAutoReconnecting = false;
                connectToDevice(result.device);
                return;
              }
            }
          }
        });

        await Future.delayed(const Duration(seconds: 4));
        _scanSubscription?.cancel();

        if (!deviceFound &&
            mounted &&
            savedDeviceId != null &&
            _isAutoReconnecting) {
          await Future.delayed(const Duration(seconds: 3));
        } else {
          break;
        }
      } catch (e) {
        await Future.delayed(const Duration(seconds: 3));
      }
    }
    _isAutoReconnecting = false;
  }

  Future<void> startScan() async {
    if (!mounted) return;
    setState(() {
      isScanning = true;
      scanResults = [];
    });

    try {
      var adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        throw Exception('Bluetooth is not enabled');
      }

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));

      FlutterBluePlus.scanResults.listen((results) {
        if (mounted) {
          setState(() {
            scanResults = results
                .where((r) => r.device.platformName.isNotEmpty)
                .toList();
          });
        }
      });

      await Future.delayed(const Duration(seconds: 4));

      if (mounted) {
        setState(() {
          isScanning = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Scan error: $e')));
        setState(() {
          isScanning = false;
        });
      }
    }
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    _isAutoReconnecting = false;
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();

    try {
      bool dialogShown = false;
      if (mounted) {
        dialogShown = true;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text('Connecting...'),
              ],
            ),
          ),
        );
      }

      await device.connect(timeout: const Duration(seconds: 6));
      await device.discoverServices();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_device_name', device.platformName);
      await prefs.setString('saved_device_id', device.remoteId.toString());

      if (mounted) {
        if (dialogShown && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ControlScreen(device: device),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to connect: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final backgroundGradient = BoxDecoration(
      gradient: LinearGradient(
        colors: [const Color(0xFF1A1F38), const Color(0xFF000000)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'NIGHTLIGHT',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w300,
            letterSpacing: 2.0,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (savedDeviceId != null)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C63FF).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF6C63FF).withOpacity(0.5),
                    ),
                  ),
                  child: const Icon(
                    Icons.bluetooth_searching,
                    size: 16,
                    color: Color(0xFF6C63FF),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Container(
        decoration: backgroundGradient,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 2),
                const Text(
                  'Control Center',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  savedDeviceId != null
                      ? 'Reconnecting to your device...'
                      : 'Connect to your Nightlight',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.5),
                    height: 1.5,
                  ),
                ),
                const Spacer(flex: 2),
                Container(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6C63FF).withOpacity(0.4),
                        blurRadius: 20,
                        spreadRadius: 0,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 48,
                        vertical: 22,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    onPressed: isScanning ? null : startScan,
                    child: isScanning
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'SCAN FOR DEVICES',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 40),
                if (scanResults.isNotEmpty)
                  Expanded(
                    flex: 4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: scanResults.length,
                            separatorBuilder: (c, i) =>
                                Divider(color: Colors.white.withOpacity(0.1)),
                            itemBuilder: (context, index) {
                              final result = scanResults[index];
                              final device = result.device;
                              final rssi = result.rssi;

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                leading: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.black26,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.bluetooth,
                                    color: rssi > -70
                                        ? const Color(0xFF03DAC6)
                                        : Colors.white54,
                                  ),
                                ),
                                title: Text(
                                  device.platformName.isEmpty
                                      ? 'Unknown Device'
                                      : device.platformName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                subtitle: Text(
                                  device.remoteId.toString(),
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.5),
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white.withOpacity(
                                      0.1,
                                    ),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: () => connectToDevice(device),
                                  child: const Text('Connect'),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  )
                else if (!isScanning)
                  const Spacer(flex: 3),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ControlScreen extends StatefulWidget {
  final BluetoothDevice device;

  const ControlScreen({super.key, required this.device});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  bool isConnected = true;
  bool smoothMode = false;
  double brightness = 0.3;
  double previousBrightness = 0.3;
  Color selectedColor = Colors.white;
  bool showSettings = false;

  // UART characteristics UUIDs
  static final Guid uartServiceUuid = Guid(
    "6e400001-b5a3-f393-e0a9-e50e24dcca9e",
  );
  static final Guid txCharacteristicUuid = Guid(
    "6e400002-b5a3-f393-e0a9-e50e24dcca9e",
  );
  static final Guid rxCharacteristicUuid = Guid(
    "6e400003-b5a3-f393-e0a9-e50e24dcca9e",
  );

  BluetoothCharacteristic? txCharacteristic;
  BluetoothCharacteristic? rxCharacteristic;

  @override
  void initState() {
    super.initState();
    setupBLE();

    widget.device.connectionState.listen((state) {
      setState(() {
        isConnected = state == BluetoothConnectionState.connected;
      });

      if (state == BluetoothConnectionState.disconnected) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Device disconnected')));
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
            (route) => false,
          );
        }
      }
    });
  }

  Future<void> setupBLE() async {
    try {
      await widget.device.discoverServices(); // force refresh
      final services = widget.device.servicesList;

      for (var service in services) {
        if (service.uuid == uartServiceUuid) {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid == txCharacteristicUuid) {
              txCharacteristic = characteristic;
            }

            if (characteristic.uuid == rxCharacteristicUuid) {
              rxCharacteristic = characteristic;
              print(
                'RX properties: '
                'write=${rxCharacteristic!.properties.write}, '
                'writeNoResp=${rxCharacteristic!.properties.writeWithoutResponse}',
              );
            }
          }
        }
      }
    } catch (e) {
      print('Error setting up BLE: $e');
    }
  }

  @override
  void dispose() {
    widget.device.disconnect();
    super.dispose();
  }

  Future<void> sendUartData(Uint8List data) async {
    // IMPORTANT: send to the peripheral's RX characteristic (central -> peripheral)
    if (txCharacteristic == null) {
      print('Error: txCharacteristic (6e400003) is null');
      return;
    }
    try {
      // Use write WITH response while debugging so the stack doesn't drop/coalesce frames.
      await txCharacteristic!.write(data, withoutResponse: true);
      // small debug print in hex
      print(
        'Wrote (${data.length}): ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
      );
    } catch (e) {
      print('Error sending data: $e');
    }
  }

  Timer? _brightnessDebounce;

  Future<void> sendColor(Color color) async {
    const int header = 0x21; // '!'
    const int type = 0x43; // 'C'

    final int r = color.red & 0xFF;
    final int g = color.green & 0xFF;
    final int b = color.blue & 0xFF;

    // CHECKSUM MUST INCLUDE header (0x21) + type + data
    final int sum = (header + type + r + g + b) & 0xFF;
    final int checksum = (~sum) & 0xFF;

    final packet = Uint8List.fromList([header, type, r, g, b, checksum]);

    await sendUartData(packet);
    setState(() => selectedColor = color);
    print(
      'Sent color packet: ${packet.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ')}',
    );
  }

  // Use ASCII '1'/'0' for pressed state (0x31/0x30), and include header in checksum.
  Future<void> sendButtonPressInt(
    int buttonCharCode, {
    bool pressed = true,
  }) async {
    const int header = 0x21; // '!'
    const int type = 0x42; // 'B'

    final int buttonByte = buttonCharCode & 0xFF;
    final int pressedByte = pressed
        ? '1'.codeUnitAt(0)
        : '0'.codeUnitAt(0); // ASCII '1'/'0'

    // INCLUDE header in checksum calculation
    final int sum = (header + type + buttonByte + pressedByte) & 0xFF;
    final int checksum = (~sum) & 0xFF;

    final packet = Uint8List.fromList([
      header,
      type,
      buttonByte,
      pressedByte,
      checksum,
    ]);

    await sendUartData(packet);
    print(
      'Sent button packet: ${packet.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ')}',
    );
  }

  // ---------------------------------------------------------

  Future<void> sendButtonPress(String id) async {
    int charCode;
    switch (id) {
      case '1':
        charCode = '1'.codeUnitAt(0); // 0x31 - Toggles Smooth Mode
        break;
      case 'UP':
        charCode = '5'.codeUnitAt(0); // 0x35 - Brightness UP
        break;
      case 'DOWN':
        charCode = '6'.codeUnitAt(0); // 0x36 - Brightness DOWN
        break;
      default:
        return;
    }
    await sendButtonPressInt(charCode);
  }

  Future<void> sendBrightnessSteps(double newValue) async {
    if (_brightnessDebounce?.isActive ?? false) _brightnessDebounce!.cancel();

    _brightnessDebounce = Timer(const Duration(milliseconds: 200), () async {
      final int steps = ((newValue - previousBrightness) * 10).round();
      if (steps == 0) return;

      final int count = steps.abs();
      final bool up = steps > 0;
      const int perStepDelayMs = 150;

      for (int i = 0; i < count; i++) {
        await sendButtonPress(up ? 'UP' : 'DOWN');
        await Future.delayed(Duration(milliseconds: perStepDelayMs));
      }
      previousBrightness = newValue;
    });
  }

  Future<void> toggleSmoothMode() async {
    await sendButtonPress('1');
    setState(() {
      smoothMode = !smoothMode;
    });
  }

  Future<void> forgetDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_device_id');
    await prefs.remove('saved_device_name');

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.platformName),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const HomeScreen()),
              (route) => false,
            );
          },
        ),
        actions: [
          IconButton(
            icon: Icon(showSettings ? Icons.close : Icons.settings),
            onPressed: () {
              setState(() {
                showSettings = !showSettings;
              });
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [const Color.fromARGB(255, 44, 44, 44), Colors.black],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: isConnected
                            ? Colors.green.withOpacity(0.2)
                            : Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isConnected ? Colors.green : Colors.red,
                          width: 2,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isConnected ? Icons.check_circle : Icons.error,
                            color: isConnected ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            isConnected ? 'Connected' : 'Disconnected',
                            style: TextStyle(
                              color: isConnected ? Colors.green : Colors.red,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    const Text(
                      'Color',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 15),
                    GestureDetector(
                      onTap: isConnected
                          ? () async {
                              final Color
                              pickedColor = await showColorPickerDialog(
                                context,
                                selectedColor,
                                title: Text(
                                  'Pick a color',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                pickersEnabled: {ColorPickerType.wheel: true},
                                actionButtons: const ColorPickerActionButtons(
                                  dialogActionButtons: true,
                                ),
                              );
                              sendColor(pickedColor);
                            }
                          : null,
                      child: Container(
                        height: 80,
                        decoration: BoxDecoration(
                          color: selectedColor,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.palette,
                                size: 30,
                                color: isConnected
                                    ? Colors.white70
                                    : Colors.white30,
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'Tap to pick color',
                                style: TextStyle(
                                  color: isConnected
                                      ? Colors.white70
                                      : Colors.white30,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    const Text(
                      'Brightness',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.brightness_low),
                        Expanded(
                          child: Slider(
                            value: brightness,
                            min: 0.0,
                            max: 1.0,
                            divisions: 10,
                            label: '${(brightness * 100).round()}%',
                            onChanged: isConnected
                                ? (value) {
                                    setState(() {
                                      brightness = value;
                                    });
                                  }
                                : null,
                            onChangeEnd: isConnected
                                ? (value) {
                                    sendBrightnessSteps(value);
                                  }
                                : null,
                          ),
                        ),
                        const Icon(Icons.brightness_high),
                      ],
                    ),
                    const SizedBox(height: 30),
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Smooth Mode',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Gradual color transitions',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          Switch(
                            value: smoothMode,
                            onChanged: isConnected
                                ? (value) {
                                    toggleSmoothMode();
                                  }
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (showSettings)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                margin: const EdgeInsets.all(10),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 10,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Device Settings',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 15),
                    Text('Device Name: ${widget.device.platformName}'),
                    const SizedBox(height: 5),
                    Text('Device ID: ${widget.device.remoteId}'),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Forget Device?'),
                            content: const Text(
                              'This will disconnect and remove the saved device. You\'ll need to scan again next time.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  forgetDevice();
                                },
                                child: const Text(
                                  'Forget',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      child: const Text('Forget Device'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
