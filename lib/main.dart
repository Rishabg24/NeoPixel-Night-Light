import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'dart:async';
import 'dart:ui' as ui;

void main() {
  runApp(const NightlightApp());
}

class NightlightApp extends StatelessWidget {
  const NightlightApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nightlight Control',
      debugShowCheckedModeBanner: false, // Removes the 'Debug' banner
      theme: ThemeData(
        useMaterial3: true, // Enables the newer, smoother UI elements
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black, // Default background
        primaryColor: const Color(0xFF6C63FF), // Sleek Violet
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
  BluetoothDevice? savedDevice;
  bool isCheckingSavedDevice = true;
  String? savedDeviceId;

  // UART Service UUID (Nordic UART Service)
  static final Guid uartServiceUuid = Guid(
    "6e400001-b5a3-f393-e0a9-e50e24dcca9e",
  );

  @override
  void initState() {
    super.initState();
    _initializeBluetooth();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  // Initialize Bluetooth and wait for it to be ready
  Future<void> _initializeBluetooth() async {
    // Wait for Bluetooth adapter to be ready
    await Future.delayed(const Duration(milliseconds: 500));

    // Check Bluetooth state
    var adapterState = await FlutterBluePlus.adapterState.first;

    if (adapterState != BluetoothAdapterState.on) {
      print('Waiting for Bluetooth to turn on...');
      await FlutterBluePlus.adapterState
          .firstWhere((state) => state == BluetoothAdapterState.on)
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              print('Bluetooth not enabled after timeout');
              return BluetoothAdapterState.off;
            },
          );
    }

    // Now check for saved device
    await checkForSavedDevice();
  }

  // Check if there's a saved device on app startup
  Future<void> checkForSavedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    savedDeviceId = prefs.getString('saved_device_id');
    final savedDeviceName = prefs.getString('saved_device_name');

    if (savedDeviceId != null) {
      print('Found saved device: $savedDeviceName ($savedDeviceId)');
      // CHANGED: Start continuous monitoring instead of one-time check
      await startContinuousMonitoring();
    } else {
      setState(() {
        isCheckingSavedDevice = false;
      });
    }
  }

  // FIXED: Continuously monitor for saved device
  Future<void> startContinuousMonitoring() async {
    if (savedDeviceId == null || _isAutoReconnecting) return;

    _isAutoReconnecting = true;
    print('Starting continuous monitoring for saved device...');

    try {
      // First check if already connected
      final connectedDevices = await FlutterBluePlus.connectedSystemDevices;
      for (var device in connectedDevices) {
        if (device.remoteId.toString() == savedDeviceId) {
          print('Device already connected!');
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => ControlScreen(device: device),
              ),
            );
          }
          _isAutoReconnecting = false;
          return;
        }
      }

      // Start continuous scanning
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (var result in results) {
          if (result.device.remoteId.toString() == savedDeviceId) {
            print('🎯 Found saved device during monitoring!');
            FlutterBluePlus.stopScan();
            _scanSubscription?.cancel();
            connectToDevice(result.device);
            return;
          }
        }
      });

      // Wait for scan to complete
      await Future.delayed(const Duration(seconds: 10));

      // Device not found, show home screen and keep monitoring
      if (mounted && isCheckingSavedDevice) {
        setState(() {
          isCheckingSavedDevice = false;
        });
      }

      // Restart monitoring after delay if still no device
      await Future.delayed(const Duration(seconds: 5));
      _isAutoReconnecting = false;

      // If we're still on home screen and have a saved device, keep monitoring
      if (mounted && savedDeviceId != null) {
        startContinuousMonitoring();
      }
    } catch (e) {
      print('Monitoring error: $e');
      _isAutoReconnecting = false;
      if (mounted) {
        setState(() {
          isCheckingSavedDevice = false;
        });
      }
    }
  }

  // Start scanning for BLE devices with UART service
  Future<void> startScan() async {
    setState(() {
      isScanning = true;
      scanResults = [];
    });

    try {
      var adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        throw Exception('Bluetooth is not enabled');
      }

      // Start scanning WITHOUT service filter to see all devices
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 4),
        // Removed withServices filter - now shows ALL BLE devices
      );

      // Listen to scan results
      FlutterBluePlus.scanResults.listen((results) {
        setState(() {
          // Show all devices with names
          scanResults = results
              .where((r) => r.device.platformName.isNotEmpty)
              .toList();
        });
      });

      // Wait for scan to complete
      await Future.delayed(const Duration(seconds: 4));

      setState(() {
        isScanning = false;
      });
    } catch (e) {
      print('Error scanning: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Scan error: $e')));
      }
      setState(() {
        isScanning = false;
      });
    }
  }

  // Connect to a device and save it
  Future<void> connectToDevice(BluetoothDevice device) async {
    // In connectToDevice(), add at the very top:
    print('🔵 connectToDevice called for ${device.platformName}');
    print('🔵 mounted: $mounted');

    try {
      print('Connecting to ${device.platformName}...');

      // Show connecting dialog
      if (mounted) {
        // Close dialog if it was shown
        if (!isCheckingSavedDevice && Navigator.canPop(context)) {
          Navigator.pop(context);
        }

        // Navigate to control screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ControlScreen(device: device),
          ),
        );
      }

      await device.connect(timeout: const Duration(seconds: 10));

      // Discover services to verify UART service exists
      await device.discoverServices();

      // Save device info
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_device_id', device.remoteId.toString());
      await prefs.setString('saved_device_name', device.platformName);

      print('Connected and saved!');

      // Close connecting dialog and navigate to control screen
      if (mounted && !isCheckingSavedDevice) {
        // ADDED !isCheckingSavedDevice check
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
    } catch (e) {
      print('Error connecting: $e');
      if (mounted) {
        // Close dialog if it was shown
        if (!isCheckingSavedDevice && Navigator.canPop(context)) {
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
    // 1. Define the sophisticated gradient background
    // Deep Charcoal Blue (Top) -> Pure Black (Bottom)
    final backgroundGradient = BoxDecoration(
      gradient: LinearGradient(
        colors: [
          const Color(0xFF1A1F38), // Deep cool charcoal/blue
          const Color(0xFF000000), // Pure black
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
    );

    if (isCheckingSavedDevice) {
      return Scaffold(
        body: Container(
          decoration: backgroundGradient,
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Color(0xFF6C63FF)),
                SizedBox(height: 20),
                Text(
                  'Syncing...',
                  style: TextStyle(letterSpacing: 1.2, color: Colors.white54),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      // 2. THIS LINE fixes the ugly top banner. It lets the background go behind the header.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'NIGHTLIGHT', // All caps looks more "tech"
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w300, // Thinner font looks more elegant
            letterSpacing: 2.0, // Spacing out letters adds a "premium" feel
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent, // Make it invisible
        elevation: 0, // Remove the shadow line
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
                    color: const Color(
                      0xFF6C63FF,
                    ).withOpacity(0.2), // Glass effect
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
        decoration: backgroundGradient, // Apply the sleek gradient
        child: SafeArea(
          // Ensures content doesn't get stuck behind the notch
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 2),

                // 3. Hero Text
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
                    color: Colors.white.withOpacity(0.5), // Subtle text
                    height: 1.5,
                  ),
                ),

                const Spacer(flex: 2),

                // 4. The "Cool" Button
                // We wrap it in a container to give it a glowing shadow
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
                      backgroundColor: const Color(
                        0xFF6C63FF,
                      ), // Electric Violet
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 48,
                        vertical: 22,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0, // handled by container
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

                // 5. The Device List (Glassmorphism Style)
                if (scanResults.isNotEmpty)
                  Expanded(
                    flex: 4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(
                          0.05,
                        ), // Very transparent white
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                      child: ClipRRect(
                        // Clips the list to the rounded corners
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          // Adds the "Blur" effect
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
  double previousBrightness = 0.3; // Track previous value for calculating steps
  Color selectedColor = Colors.white;
  bool showSettings = false;

  // UART characteristics UUIDs
  static final Guid uartServiceUuid = Guid(
    "6e400001-b5a3-f393-e0a9-e50e24dcca9e",
  );
  static final Guid txCharacteristicUuid = Guid(
    "6e400002-b5a3-f393-e0a9-e50e24dcca9e",
  ); // Write
  static final Guid rxCharacteristicUuid = Guid(
    "6e400003-b5a3-f393-e0a9-e50e24dcca9e",
  ); // Notify

  BluetoothCharacteristic? txCharacteristic;
  BluetoothCharacteristic? rxCharacteristic;

  @override
  void initState() {
    super.initState();
    setupBLE();

    // Listen for disconnection
    widget.device.connectionState.listen((state) {
      setState(() {
        isConnected = state == BluetoothConnectionState.connected;
      });

      if (state == BluetoothConnectionState.disconnected) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Device disconnected')));
          // NEW: Use pushAndRemoveUntil instead of pop
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
            (route) => false,
          );
        }
      }
    });
  }

  // Setup BLE characteristics
  Future<void> setupBLE() async {
    try {
      List<BluetoothService> services = await widget.device.discoverServices();

      for (var service in services) {
        if (service.uuid == uartServiceUuid) {
          print('Found UART service!');

          for (var characteristic in service.characteristics) {
            if (characteristic.uuid == txCharacteristicUuid) {
              txCharacteristic = characteristic;
              print('Found TX characteristic');
            } else if (characteristic.uuid == rxCharacteristicUuid) {
              rxCharacteristic = characteristic;
              print('Found RX characteristic');

              // Subscribe to notifications
              await rxCharacteristic!.setNotifyValue(true);
              rxCharacteristic!.lastValueStream.listen((value) {
                print('Received from device: $value');
              });
            }
          }
        }
      }

      if (txCharacteristic == null) {
        print('Warning: TX characteristic not found');
      }
    } catch (e) {
      print('Error setting up BLE: $e');
    }
  }

  @override
  void dispose() {
    // Disconnect when leaving screen
    widget.device.disconnect();
    super.dispose();
  }

  // Send data via UART
  Future<void> sendUartData(List<int> data) async {
    if (txCharacteristic == null) {
      print('TX characteristic not available');
      return;
    }

    try {
      await txCharacteristic!.write(data, withoutResponse: false);
      print('Sent data: $data');
    } catch (e) {
      print('Error sending data: $e');
    }
  }

  // Send color packet (Bluefruit format: '!C' + R + G + B + checksum)
  Future<void> sendColor(Color color) async {
    // Bluefruit Color Packet format
    final packet = [
      0x21, // '!'
      0x43, // 'C' for Color
      color.red,
      color.green,
      color.blue,
      // Checksum: XOR of all bytes except '!'
      0x43 ^ color.red ^ color.green ^ color.blue,
    ];

    await sendUartData(packet);

    setState(() {
      selectedColor = color;
    });

    print('Sending color: R=${color.red} G=${color.green} B=${color.blue}');
  }

  // Send button packet (Bluefruit format: '!B' + button_id + pressed + checksum)
  Future<void> sendButtonPress(String buttonId) async {
    int buttonCode;

    switch (buttonId) {
      case '1': // Toggle smooth mode
        buttonCode = 0x31; // '1'
        break;
      case 'UP': // Increase brightness
        buttonCode = 0x35; // '5' (UP button)
        break;
      case 'DOWN': // Decrease brightness
        buttonCode = 0x36; // '6' (DOWN button)
        break;
      default:
        return;
    }

    // Bluefruit Button Packet format
    final packet = [
      0x21, // '!'
      0x42, // 'B' for Button
      buttonCode,
      0x01, // 1 = pressed
      // Checksum: XOR of all bytes except '!'
      0x42 ^ buttonCode ^ 0x01,
    ];

    await sendUartData(packet);
    print('Sent button: $buttonId');
  }

  // FIXED: Send brightness change with proper step calculation
  Future<void> sendBrightnessSteps(double newValue) async {
    int steps = ((newValue - previousBrightness) * 10).round();

    print('Brightness change: $previousBrightness -> $newValue ($steps steps)');

    // Send multiple button presses based on difference
    for (int i = 0; i < steps.abs(); i++) {
      await sendButtonPress(steps > 0 ? 'UP' : 'DOWN');
      // Small delay between button presses to avoid overwhelming the device
      await Future.delayed(const Duration(milliseconds: 50));
    }

    previousBrightness = newValue;
  }

  // Toggle smooth mode
  Future<void> toggleSmoothMode() async {
    await sendButtonPress('1'); // Button 1 toggles smooth mode

    setState(() {
      smoothMode = !smoothMode;
    });

    print('Toggling smooth mode: $smoothMode');
  }

  // Forget device
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
          // Settings icon
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
          // Main control area
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
                    // Connection status
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

                    // Color picker section
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
                              // FIXED: Removed null check
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

                              // Use directly, no null check
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

                    // Brightness slider
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
                                    // Update UI immediately
                                    setState(() {
                                      brightness = value;
                                    });
                                  }
                                : null,
                            onChangeEnd: isConnected
                                ? (value) {
                                    // Send button presses when user finishes dragging
                                    sendBrightnessSteps(value);
                                  }
                                : null,
                          ),
                        ),
                        const Icon(Icons.brightness_high),
                      ],
                    ),

                    const SizedBox(height: 30),

                    // Smooth mode toggle
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

          // Settings dropdown
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
