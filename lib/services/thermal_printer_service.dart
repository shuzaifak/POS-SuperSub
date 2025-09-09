// lib/services/thermal_printer_service.dart
import 'package:flutter/services.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:epos/models/cart_item.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:epos/services/uk_time_service.dart';

class ThermalPrinterService {
  static final ThermalPrinterService _instance =
      ThermalPrinterService._internal();
  factory ThermalPrinterService() => _instance;

  ThermalPrinterService._internal();

  static const bool ENABLE_MOCK_MODE = false;
  static const bool SIMULATE_PRINTER_SUCCESS = false;
  static const bool ENABLE_DRAWER_TEST_MODE = false;
  UsbPort? _persistentUsbPort;
  String? _connectedBluetoothDevice;
  bool _isBluetoothConnected = false;

  // Cached devices for speed
  List<BluetoothInfo> _cachedThermalDevices = [];
  List<UsbDevice> _cachedUsbDevices = [];
  DateTime? _lastCacheUpdate;

  // Connection timeout settings
  static const Duration QUICK_TIMEOUT = Duration(seconds: 2);
  static const Duration NORMAL_TIMEOUT = Duration(seconds: 5);
  static const Duration CACHE_VALIDITY = Duration(minutes: 5);

  // Connection health monitoring
  Timer? _connectionHealthTimer;
  bool _isMonitoringConnection = false;

  // OPTIMIZED: Pre-generated receipt cache
  final Map<String, List<int>> _receiptCache = {};

  // Cash drawer settings
  bool _isDrawerOpeningEnabled = true;
  bool _autoOpenOnCashPayment = true;

  // Helper method to check if a field should be excluded from receipt
  bool _shouldExcludeField(String? value) {
    if (value == null || value.isEmpty) return true;
    return value.trim().toUpperCase() == 'N/A';
  }

  Future<Map<String, bool>> testAllConnections() async {
    print('🧪 Testing all printer connections...');

    // Skip web-specific checks
    if (kIsWeb) {
      print('📱 Web platform detected - skipping native printer checks');
      return {'usb': false, 'bluetooth': false};
    }

    List<Future<bool>> futures = [];
    List<String> methods = [];

    // Only test USB on mobile/desktop platforms
    if (Platform.isAndroid || Platform.isWindows || Platform.isLinux) {
      futures.add(_testUSBConnection());
      methods.add('usb');
    }

    // Only test Bluetooth on mobile platforms
    if (Platform.isAndroid || Platform.isIOS) {
      futures.add(_testThermalBluetoothConnection());
      methods.add('bluetooth');
    }

    if (futures.isEmpty) {
      return {'usb': false, 'bluetooth': false};
    }

    List<bool> results = await Future.wait(futures);

    Map<String, bool> testResults = {};
    for (int i = 0; i < methods.length; i++) {
      testResults[methods[i]] = results[i];
    }

    // Fill in missing methods
    if (!testResults.containsKey('usb')) testResults['usb'] = false;
    if (!testResults.containsKey('bluetooth')) testResults['bluetooth'] = false;

    print('📊 Test Results:');
    print(
      '   USB: ${testResults['usb'] == true ? "✅ Available" : "❌ Not Available"}',
    );
    print(
      '   Bluetooth: ${testResults['bluetooth'] == true ? "✅ Available" : "❌ Not Available"}',
    );

    return testResults;
  }

  // Add this method for lightweight status checking without sending printer commands
  Future<Map<String, bool>> checkConnectionStatusOnly() async {
    print('🔍 Checking printer connection status (lightweight)...');

    if (kIsWeb) {
      print('📱 Web platform detected - skipping native printer checks');
      return {'usb': false, 'bluetooth': false};
    }

    Map<String, bool> testResults = {'usb': false, 'bluetooth': false};

    // Check USB without sending commands
    if (Platform.isAndroid || Platform.isWindows || Platform.isLinux) {
      try {
        if (_persistentUsbPort != null) {
          testResults['usb'] = true;
        } else {
          List<UsbDevice> devices = await UsbSerial.listDevices();
          testResults['usb'] = devices.isNotEmpty;
        }
      } catch (e) {
        testResults['usb'] = false;
      }
    }

    // Check Bluetooth without sending commands
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        if (_isBluetoothConnected) {
          bool isConnected = await PrintBluetoothThermal.connectionStatus;
          testResults['bluetooth'] = isConnected;
        } else {
          List<BluetoothInfo> devices =
              await PrintBluetoothThermal.pairedBluetooths;
          testResults['bluetooth'] = devices.isNotEmpty;
        }
      } catch (e) {
        testResults['bluetooth'] = false;
      }
    }

    return testResults;
  }

  // OPTIMIZED: Fast USB connection test with improved caching
  Future<bool> _testUSBConnection() async {
    if (kIsWeb ||
        (!Platform.isAndroid && !Platform.isWindows && !Platform.isLinux)) {
      return false;
    }
    if (ENABLE_MOCK_MODE) {
      await Future.delayed(
        Duration(milliseconds: 500),
      ); // Simulate connection time
      print(
        '🧪 MOCK: USB printer simulated - ${SIMULATE_PRINTER_SUCCESS ? "Connected" : "Failed"}',
      );
      return SIMULATE_PRINTER_SUCCESS;
    }

    try {
      if (!await _isUSBSerialAvailable()) return false;

      // Use cached devices if available and recent
      if (_cachedUsbDevices.isEmpty || _isCacheExpired()) {
        _cachedUsbDevices = await UsbSerial.listDevices();
        _lastCacheUpdate = UKTimeService.now();
      }

      if (_cachedUsbDevices.isEmpty) return false;

      // If we already have a persistent connection, test it quickly
      if (_persistentUsbPort != null) {
        try {
          // Quick health check - send minimal data
          await _persistentUsbPort!.write(
            Uint8List.fromList([0x1B, 0x40]),
          ); // ESC @ (initialize)
          await Future.delayed(Duration(milliseconds: 100));
          return true;
        } catch (e) {
          print('🔧 USB connection health check failed: $e');
          await _closeUsbConnection();
        }
      }

      // Establish new connection with first available device
      UsbDevice device = _cachedUsbDevices.first;
      return await _establishUSBConnection(device);
    } catch (e) {
      print('❌ USB test error: $e');
      return false;
    }
  }

  // OPTIMIZED: Fast Bluetooth connection test with health monitoring
  Future<bool> _testThermalBluetoothConnection() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return false;
    }
    if (ENABLE_MOCK_MODE) {
      await Future.delayed(
        Duration(milliseconds: 800),
      ); // Simulate connection time
      print(
        '🧪 MOCK: Bluetooth thermal printer simulated - ${SIMULATE_PRINTER_SUCCESS ? "Connected" : "Failed"}',
      );
      return SIMULATE_PRINTER_SUCCESS;
    }

    try {
      if (!await _isBluetoothEnabled()) return false;

      // Use cached devices if available and recent
      if (_cachedThermalDevices.isEmpty || _isCacheExpired()) {
        _cachedThermalDevices = await PrintBluetoothThermal.pairedBluetooths;
        _lastCacheUpdate = UKTimeService.now();
      }

      if (_cachedThermalDevices.isEmpty) return false;

      // If already connected, test connection health
      if (_isBluetoothConnected && _connectedBluetoothDevice != null) {
        try {
          bool isConnected = await PrintBluetoothThermal.connectionStatus;
          if (isConnected) {
            // Send a quick test command
            await PrintBluetoothThermal.writeBytes([
              0x1B,
              0x40,
            ]); // ESC @ (initialize)
            await Future.delayed(Duration(milliseconds: 100));
            return true;
          }
        } catch (e) {
          print('🔧 Bluetooth connection health check failed: $e');
          await _closeBluetoothConnection();
        }
      }

      // Establish new connection
      return await _establishBluetoothConnection();
    } catch (e) {
      print('❌ Bluetooth test error: $e');
      return false;
    }
  }

  // SUPER OPTIMIZED: Ultra-fast printing with pre-generated receipts
  Future<bool> printReceiptWithUserInteraction({
    required String transactionId,
    required String orderType,
    required List<CartItem> cartItems,
    required double subtotal,
    required double totalCharge,
    String? extraNotes,
    required double changeDue,
    String? customerName,
    String? customerEmail,
    String? phoneNumber,
    String? streetAddress,
    String? city,
    String? postalCode,
    String? paymentType,
    bool? paidStatus,
    int? orderId,
    Function(List<String> availableMethods)? onShowMethodSelection,
  }) async {
    if (kIsWeb && !ENABLE_DRAWER_TEST_MODE) {
      print('🚫 Web platform - printer not supported');
      return false;
    }

    if (kIsWeb && ENABLE_DRAWER_TEST_MODE) {
      // Auto-open cash drawer disabled - drawer opens only via manual button press
      // if (_autoOpenOnCashPayment &&
      //     paymentType?.toLowerCase() == 'cash' &&
      //     _isDrawerOpeningEnabled) {
      //   print('💰 Auto-opening cash drawer for cash payment (WEB TEST MODE)');
      //   await openCashDrawer(reason: "Cash payment completed - WEB TEST");
      // }

      // Simulate successful printing in test mode
      await Future.delayed(Duration(seconds: 1));
      print('🧪 Web test mode: Receipt printing simulated successfully');
      return true;
    }

    print('🖨️ Starting super-fast print job...');

    // Pre-generate receipt data while testing connections
    String receiptKey = '$transactionId-$orderType-${cartItems.length}';

    // Generate receipt data in parallel with connection testing
    Future<List<int>> receiptDataFuture = _generateESCPOSReceipt(
      transactionId: transactionId,
      orderType: orderType,
      cartItems: cartItems,
      subtotal: subtotal,
      totalCharge: totalCharge,
      extraNotes: extraNotes,
      changeDue: changeDue,
      customerName: customerName,
      customerEmail: customerEmail,
      phoneNumber: phoneNumber,
      streetAddress: streetAddress,
      city: city,
      postalCode: postalCode,
      paymentType: paymentType,
      paidStatus: paidStatus,
      orderId: orderId,
    );

    Future<String> receiptContentFuture = Future.value(
      _generateReceiptContent(
        transactionId: transactionId,
        orderType: orderType,
        cartItems: cartItems,
        subtotal: subtotal,
        totalCharge: totalCharge,
        extraNotes: extraNotes,
        changeDue: changeDue,
        customerName: customerName,
        customerEmail: customerEmail,
        phoneNumber: phoneNumber,
        streetAddress: streetAddress,
        city: city,
        postalCode: postalCode,
        paymentType: paymentType,
        paidStatus: paidStatus,
        orderId: orderId,
      ),
    );

    // Test connections in parallel
    Future<Map<String, bool>> connectionTestFuture = testAllConnections();

    // Wait for all preparations to complete
    List<dynamic> results = await Future.wait([
      connectionTestFuture,
      receiptDataFuture,
      receiptContentFuture,
    ]);

    Map<String, bool> connectionStatus = results[0];
    List<int> receiptData = results[1];
    String receiptContent = results[2];

    // Cache the generated receipt data
    _receiptCache[receiptKey] = receiptData;

    List<String> availableMethods = [];
    if (connectionStatus['usb'] == true) availableMethods.add('USB');
    if (connectionStatus['bluetooth'] == true)
      availableMethods.add('Thermal Bluetooth');

    if (availableMethods.isEmpty) {
      print('❌ No printer connections available');
      if (onShowMethodSelection != null) {
        onShowMethodSelection(['USB', 'Thermal Bluetooth']);
      }
      return false;
    }

    // Start connection health monitoring
    _startConnectionHealthMonitoring();

    // Try available methods with pre-generated data
    for (String method in availableMethods) {
      print('🚀 Attempting super-fast $method printing...');

      bool success = await _printWithPreGeneratedData(
        method: method,
        receiptData: receiptData,
        receiptContent: receiptContent,
      );

      if (success) {
        print('✅ $method printing successful');

        // Auto-open cash drawer disabled - drawer opens only via manual button press
        // if (_autoOpenOnCashPayment &&
        //     paymentType?.toLowerCase() == 'cash' &&
        //     _isDrawerOpeningEnabled) {
        //   print('💰 Auto-opening cash drawer for cash payment');
        //   await openCashDrawer(reason: "Cash payment completed");
        // }

        return true;
      }
    }

    print('❌ All available methods failed');
    if (onShowMethodSelection != null) {
      onShowMethodSelection(availableMethods);
    }
    return false;
  }

  // SUPER OPTIMIZED: Direct printing with pre-generated data
  Future<bool> _printWithPreGeneratedData({
    required String method,
    required List<int> receiptData,
    required String receiptContent,
  }) async {
    switch (method) {
      case 'USB':
        return await _printUSBSuperFast(receiptData);
      case 'Thermal Bluetooth':
        return await _printBluetoothSuperFast(receiptContent);
      default:
        return false;
    }
  }

  // SUPER OPTIMIZED: Ultra-fast USB printing
  Future<bool> _printUSBSuperFast(List<int> receiptData) async {
    if (kIsWeb ||
        (!Platform.isAndroid && !Platform.isWindows && !Platform.isLinux)) {
      return false;
    }
    if (ENABLE_MOCK_MODE) {
      await Future.delayed(Duration(milliseconds: 1000)); // Simulate print time
      debugPrint('🧪 MOCK: USB printing simulated');
      debugPrint('📄 Receipt data length: ${receiptData.length} bytes');
      debugPrint(
        '📄 Receipt preview: ${String.fromCharCodes(receiptData.take(100))}...',
      );
      return SIMULATE_PRINTER_SUCCESS;
    }

    try {
      // Ensure we have a persistent connection
      if (_persistentUsbPort == null) {
        if (_cachedUsbDevices.isEmpty) {
          _cachedUsbDevices = await UsbSerial.listDevices();
        }
        if (_cachedUsbDevices.isEmpty) return false;

        if (!await _establishUSBConnection(_cachedUsbDevices.first)) {
          return false;
        }
      }

      // Ultra-fast printing with minimal delays
      await _persistentUsbPort!.write(Uint8List.fromList(receiptData));
      await Future.delayed(Duration(milliseconds: 50)); // Minimal delay

      print('✅ USB super-fast print successful');
      return true;
    } catch (e) {
      print('❌ USB super-fast print error: $e');
      await _closeUsbConnection();
      return false;
    }
  }

  Future<bool> _printBluetoothSuperFast(String receiptContent) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return false;
    }
    if (ENABLE_MOCK_MODE) {
      await Future.delayed(Duration(milliseconds: 1200)); // Simulate print time
      print('🧪 MOCK: Bluetooth printing simulated');
      print('📄 Receipt content preview:');
      print(
        receiptContent.substring(0, math.min(200, receiptContent.length)) +
            '...',
      );
      return SIMULATE_PRINTER_SUCCESS;
    }

    try {
      // Ensure we have a persistent connection
      if (!_isBluetoothConnected) {
        if (!await _establishBluetoothConnection()) {
          return false;
        }
      }

      // Use the ESC/POS formatted data instead of plain text
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      List<int> ticket = await _convertReceiptContentToESCPOS(
        receiptContent,
        generator,
      );

      await PrintBluetoothThermal.writeBytes(ticket);

      print('✅ Bluetooth super-fast print successful');
      return true;
    } catch (e) {
      print('❌ Bluetooth super-fast print error: $e');
      await _closeBluetoothConnection();
      return false;
    }
  }

  Future<List<int>> _convertReceiptContentToESCPOS(
    String content,
    Generator generator,
  ) async {
    List<int> bytes = [];
    bytes += generator.setGlobalCodeTable('CP1252');

    List<String> lines = content.split('\n');

    for (String line in lines) {
      if (line.contains('**') && line.contains('**')) {
        // Handle ONLY the specific bold elements we want
        if (line.contains('TVP') && line.trim() == '**TVP**') {
          // Restaurant name - large and bold
          bytes += generator.text(
            'TVP',
            styles: const PosStyles(
              align: PosAlign.center,
              height: PosTextSize.size3,
              width: PosTextSize.size2,
              bold: true,
            ),
          );
        } else if (line.contains('Order #:')) {
          // Order number - bold
          String orderText = line.replaceAll('**', '');
          bytes += generator.text(
            orderText,
            styles: const PosStyles(
              height: PosTextSize.size2,
              width: PosTextSize.size1,
              bold: true,
            ),
          );
        } else if (line.contains('Order Type:')) {
          // Order type - bold
          String orderTypeText = line.replaceAll('**', '');
          bytes += generator.text(
            orderTypeText,
            styles: const PosStyles(bold: true),
          );
        } else if (line.contains('Payment Method:')) {
          // Payment method - bold
          String paymentText = line.replaceAll('**', '');
          bytes += generator.text(
            paymentText,
            styles: const PosStyles(height: PosTextSize.size1, bold: true),
          );
        } else if (line.contains('TOTAL:')) {
          // Total amount - bold
          String totalText = line.replaceAll('**', '');
          if (totalText.contains('£')) {
            // Split the total line for proper alignment
            List<String> parts = totalText.split('£');
            if (parts.length == 2) {
              bytes += generator.row([
                PosColumn(
                  text: parts[0],
                  width: 9,
                  styles: const PosStyles(bold: true),
                ),
                PosColumn(
                  text: '£${parts[1].trim()}',
                  width: 3,
                  styles: const PosStyles(align: PosAlign.right, bold: true),
                ),
              ]);
            } else {
              bytes += generator.text(
                totalText,
                styles: const PosStyles(bold: true),
              );
            }
          } else {
            bytes += generator.text(
              totalText,
              styles: const PosStyles(bold: true),
            );
          }
        } else if (line.trim().contains('x **') && line.contains('**')) {
          // Item names - bold (only the item name part)
          String itemText = line.replaceAll('**', '');
          bytes += generator.text(
            itemText,
            styles: const PosStyles(
              height: PosTextSize.size1,
              width: PosTextSize.size1,
              bold: true,
            ),
          );
        } else if (line.contains('Status: **') &&
            (line.contains('PAID') || line.contains('UNPAID'))) {
          // Payment status (PAID/UNPAID) - bold
          String statusText = line.replaceAll('**', '');
          bytes += generator.text(
            statusText,
            styles: const PosStyles(
              bold: true,
              height: PosTextSize.size2,
              width: PosTextSize.size1,
            ),
          );
        } else {
          // Remove ** markers but don't make bold (fallback for any other ** text)
          String plainText = line.replaceAll('**', '');
          bytes += generator.text(plainText);
        }
      } else {
        // Regular text - no bold formatting
        if (line.contains('================================================')) {
          bytes += generator.text(
            line,
            styles: const PosStyles(align: PosAlign.center),
          );
        } else if (line.contains('Thank you for your order!')) {
          bytes += generator.text(
            line,
            styles: const PosStyles(
              align: PosAlign.center,
              height: PosTextSize.size2,
              width: PosTextSize.size1,
            ),
          );
        } else if (line.trim().isEmpty) {
          bytes += generator.emptyLines(1);
        } else {
          bytes += generator.text(line);
        }
      }
    }

    bytes += generator.emptyLines(2);
    bytes += generator.cut();
    return bytes;
  }

  Future<bool> validateReceiptGeneration({
    required String transactionId,
    required String orderType,
    required List<CartItem> cartItems,
    required double subtotal,
    required double totalCharge,
    String? extraNotes,
    required double changeDue,
    String? customerName,
    String? customerEmail,
    String? phoneNumber,
    String? streetAddress,
    String? city,
    String? postalCode,
    String? paymentType,
    bool? paidStatus,
    int? orderId,
  }) async {
    try {
      // Test receipt content generation
      String receiptContent = _generateReceiptContent(
        transactionId: transactionId,
        orderType: orderType,
        cartItems: cartItems,
        subtotal: subtotal,
        totalCharge: totalCharge,
        extraNotes: extraNotes,
        changeDue: changeDue,
        customerName: customerName,
        customerEmail: customerEmail,
        phoneNumber: phoneNumber,
        streetAddress: streetAddress,
        city: city,
        postalCode: postalCode,
        paymentType: paymentType,
        paidStatus: paidStatus,
        orderId: orderId,
      );

      // Test ESC/POS receipt generation
      List<int> receiptData = await _generateESCPOSReceipt(
        transactionId: transactionId,
        orderType: orderType,
        cartItems: cartItems,
        subtotal: subtotal,
        totalCharge: totalCharge,
        extraNotes: extraNotes,
        changeDue: changeDue,
        customerName: customerName,
        customerEmail: customerEmail,
        phoneNumber: phoneNumber,
        streetAddress: streetAddress,
        city: city,
        postalCode: postalCode,
        paymentType: paymentType,
        paidStatus: paidStatus,
        orderId: orderId,
      );

      print('✅ Receipt generation validation successful');
      print('📄 Content length: ${receiptContent.length} characters');
      print('📄 ESC/POS data length: ${receiptData.length} bytes');

      return true;
    } catch (e) {
      print('❌ Receipt generation validation failed: $e');
      return false;
    }
  }

  // IMPROVED: Robust USB connection establishment
  Future<bool> _establishUSBConnection(UsbDevice device) async {
    print('🔗 USB DEBUGGING: Starting connection establishment...');
    print('📄 USB DEBUGGING: Target Device Details:');
    print('   - Name: ${device.deviceName}');
    print(
      '   - VID: 0x${device.vid?.toRadixString(16).padLeft(4, '0').toUpperCase()}',
    );
    print(
      '   - PID: 0x${device.pid?.toRadixString(16).padLeft(4, '0').toUpperCase()}',
    );
    print('   - Manufacturer: ${device.manufacturerName ?? "Unknown"}');
    print('   - Product: ${device.productName ?? "Unknown"}');

    try {
      print('🔧 USB DEBUGGING: Step 1 - Creating USB port...');
      _persistentUsbPort = await device.create();

      if (_persistentUsbPort == null) {
        print('❌ USB DEBUGGING: Failed to create USB port!');
        print('   - This usually means:');
        print('     • Device is not available');
        print('     • USB permissions not granted');
        print('     • Device is being used by another process');
        print('   - Try: Disconnect and reconnect the USB cable');
        return false;
      }
      print('✅ USB DEBUGGING: USB port created successfully');

      print('🔧 USB DEBUGGING: Step 2 - Opening USB port...');
      bool opened = await _persistentUsbPort!.open();

      if (!opened) {
        print('❌ USB DEBUGGING: Failed to open USB port!');
        print('   - This usually means:');
        print('     • Device driver not installed');
        print('     • USB port is locked by system');
        print('     • Hardware communication failure');
        print('   - Try: Installing USB-to-Serial drivers');
        _persistentUsbPort = null;
        return false;
      }
      print('✅ USB DEBUGGING: USB port opened successfully');

      print('🔧 USB DEBUGGING: Step 3 - Testing baud rates...');
      // Try different baud rates for better compatibility
      List<int> baudRates = [9600, 19200, 38400, 57600, 115200];
      bool connectionSuccessful = false;

      for (int baudRate in baudRates) {
        try {
          print('⚡ USB DEBUGGING: Testing baud rate: $baudRate');

          await _persistentUsbPort!.setPortParameters(
            baudRate,
            8, // Data bits
            1, // Stop bits
            0, // Parity (none)
          );
          print('   ✓ Port parameters set successfully');

          print('📤 USB DEBUGGING: Sending initialization command (ESC @)...');
          // Send initialization command and wait for response
          await _persistentUsbPort!.write(
            Uint8List.fromList([0x1B, 0x40]), // ESC @ (initialize)
          );
          await Future.delayed(Duration(milliseconds: 200));
          print('   ✓ Initialization command sent');

          print('📤 USB DEBUGGING: Sending test command (line feed)...');
          // Try sending a simple command to test connection
          await _persistentUsbPort!.write(
            Uint8List.fromList([0x1B, 0x4A, 0x02]), // ESC J n (feed 2 lines)
          );
          await Future.delayed(Duration(milliseconds: 100));
          print('   ✓ Test command sent successfully');

          connectionSuccessful = true;
          print('✅ USB DEBUGGING: Connection established successfully!');
          print('   - Working baud rate: $baudRate');
          print('   - Printer should have responded (check for paper feed)');
          break;
        } catch (e) {
          debugPrint('Baud rate $baudRate failed: $e');
          continue;
        }
      }

      if (!connectionSuccessful) {
        debugPrint('❌ All baud rates failed, closing connection');
        await _persistentUsbPort!.close();
        _persistentUsbPort = null;
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('❌ Failed to establish USB connection: $e');
      if (_persistentUsbPort != null) {
        try {
          await _persistentUsbPort!.close();
        } catch (closeError) {
          debugPrint('Error closing failed USB connection: $closeError');
        }
      }
      _persistentUsbPort = null;
      return false;
    }
  }

  // IMPROVED: Robust Bluetooth connection establishment
  Future<bool> _establishBluetoothConnection() async {
    try {
      if (_cachedThermalDevices.isEmpty) return false;

      BluetoothInfo? printer = _findThermalPrinterDevice(_cachedThermalDevices);
      printer ??= _cachedThermalDevices.first;

      // Disconnect any existing connection first
      if (_isBluetoothConnected) {
        await PrintBluetoothThermal.disconnect;
        await Future.delayed(Duration(milliseconds: 200));
      }

      bool connected = await PrintBluetoothThermal.connect(
        macPrinterAddress: printer.macAdress,
      );

      if (connected) {
        _isBluetoothConnected = true;
        _connectedBluetoothDevice = printer.macAdress;

        // Send initialization command
        await PrintBluetoothThermal.writeBytes([0x1B, 0x40]); // ESC @
        await Future.delayed(Duration(milliseconds: 100));

        print('✅ Bluetooth persistent connection established');
        return true;
      }

      return false;
    } catch (e) {
      print('❌ Failed to establish Bluetooth connection: $e');
      _isBluetoothConnected = false;
      _connectedBluetoothDevice = null;
      return false;
    }
  }

  // NEW: Connection health monitoring
  void _startConnectionHealthMonitoring() {
    if (_isMonitoringConnection) return;

    _isMonitoringConnection = true;
    _connectionHealthTimer = Timer.periodic(Duration(seconds: 30), (
      timer,
    ) async {
      if (!_isMonitoringConnection) {
        timer.cancel();
        return;
      }

      // Check USB connection health
      if (_persistentUsbPort != null) {
        try {
          await _persistentUsbPort!.write(Uint8List.fromList([0x1B, 0x40]));
        } catch (e) {
          print('🔧 USB connection lost, attempting reconnection...');
          await _closeUsbConnection();
        }
      }

      // Check Bluetooth connection health
      if (_isBluetoothConnected) {
        try {
          bool isConnected = await PrintBluetoothThermal.connectionStatus;
          if (!isConnected) {
            print('🔧 Bluetooth connection lost, attempting reconnection...');
            await _closeBluetoothConnection();
          }
        } catch (e) {
          print('🔧 Bluetooth health check failed: $e');
          await _closeBluetoothConnection();
        }
      }
    });
  }

  void _stopConnectionHealthMonitoring() {
    _isMonitoringConnection = false;
    _connectionHealthTimer?.cancel();
    _connectionHealthTimer = null;
  }

  // OPTIMIZED: Retry with connection reset
  Future<bool> retryPrintingMethod({
    required String method,
    required String transactionId,
    required String orderType,
    required List<CartItem> cartItems,
    required double subtotal,
    required double totalCharge,
    String? extraNotes,
    required double changeDue,
    String? customerName,
    String? customerEmail,
    String? phoneNumber,
    String? streetAddress,
    String? city,
    String? postalCode,
    String? paymentType,
    bool? paidStatus,
    int? orderId,
  }) async {
    if (kIsWeb) return false;

    print('🔄 Retrying $method printing with connection reset...');

    // Clean up existing connections
    await _closeAllConnections();
    _clearCache();

    // Generate receipt data
    List<int> receiptData = await _generateESCPOSReceipt(
      transactionId: transactionId,
      orderType: orderType,
      cartItems: cartItems,
      subtotal: subtotal,
      totalCharge: totalCharge,
      extraNotes: extraNotes,
      changeDue: changeDue,
      customerName: customerName,
      customerEmail: customerEmail,
      phoneNumber: phoneNumber,
      streetAddress: streetAddress,
      city: city,
      postalCode: postalCode,
      paymentType: paymentType,
      paidStatus: paidStatus,
      orderId: orderId,
    );

    String receiptContent = _generateReceiptContent(
      transactionId: transactionId,
      orderType: orderType,
      cartItems: cartItems,
      subtotal: subtotal,
      totalCharge: totalCharge,
      extraNotes: extraNotes,
      changeDue: changeDue,
      customerName: customerName,
      customerEmail: customerEmail,
      phoneNumber: phoneNumber,
      streetAddress: streetAddress,
      city: city,
      postalCode: postalCode,
      paymentType: paymentType,
      paidStatus: paidStatus,
      orderId: orderId,
    );

    return await _printWithPreGeneratedData(
      method: method,
      receiptData: receiptData,
      receiptContent: receiptContent,
    );
  }

  // Helper methods
  bool _isCacheExpired() {
    if (_lastCacheUpdate == null) return true;
    return UKTimeService.now().difference(_lastCacheUpdate!) > CACHE_VALIDITY;
  }

  Future<void> _closeUsbConnection() async {
    try {
      await _persistentUsbPort?.close();
    } catch (e) {
      print('Error closing USB connection: $e');
    } finally {
      _persistentUsbPort = null;
    }
  }

  Future<void> _closeBluetoothConnection() async {
    try {
      if (_isBluetoothConnected) {
        await PrintBluetoothThermal.disconnect;
      }
    } catch (e) {
      print('Error closing Bluetooth connection: $e');
    } finally {
      _isBluetoothConnected = false;
      _connectedBluetoothDevice = null;
    }
  }

  Future<void> _closeAllConnections() async {
    await _closeUsbConnection();
    await _closeBluetoothConnection();
  }

  void _clearCache() {
    _cachedThermalDevices.clear();
    _cachedUsbDevices.clear();
    _receiptCache.clear();
    _lastCacheUpdate = null;
  }

  // ===== CASH DRAWER FUNCTIONALITY =====

  /// Opens the cash drawer using ESC/POS commands
  /// Returns true if the command was sent successfully
  Future<bool> openCashDrawer({String reason = "Manual open"}) async {
    if (!_isDrawerOpeningEnabled) {
      print('💰 Cash drawer opening is disabled');
      return false;
    }

    if (kIsWeb && !ENABLE_DRAWER_TEST_MODE) {
      print('💰 Cash drawer not supported on web platform');
      return false;
    }

    if (kIsWeb && ENABLE_DRAWER_TEST_MODE) {
      print('💰 Cash drawer opened (TEST MODE) - Reason: $reason');
      await Future.delayed(Duration(seconds: 1));
      return true;
    }

    print('💰 Opening cash drawer: $reason');

    // TEST MODE: Simulate cash drawer opening for development
    if (ENABLE_DRAWER_TEST_MODE) {
      print('🧪 TEST MODE: Simulating cash drawer opening...');
      await Future.delayed(
        Duration(milliseconds: 500),
      ); // Simulate operation time
      print('✅ TEST MODE: Cash drawer opened successfully (simulated)');
      return true;
    }

    // Standard ESC/POS cash drawer command
    // ESC p m t1 t2 - where m=0 (drawer 1), t1=pulse duration, t2=pulse interval
    List<int> drawerCommand = [
      0x1B, 0x70, // ESC p
      0x00, // m (drawer connector pin 2)
      0x19, // t1 (pulse ON time: 25ms)
      0xFA, // t2 (pulse OFF time: 250ms)
    ];

    // Try to send command via available connection
    bool success = false;

    // First try USB connection
    if (_persistentUsbPort != null) {
      success = await _sendDrawerCommandUSB(drawerCommand);
      if (success) {
        print('✅ Cash drawer opened via USB');
        return true;
      }
    }

    // Then try Bluetooth connection
    if (_isBluetoothConnected) {
      success = await _sendDrawerCommandBluetooth(drawerCommand);
      if (success) {
        print('✅ Cash drawer opened via Bluetooth');
        return true;
      }
    }

    // If no existing connection, try to establish one and send command
    success = await _openDrawerWithNewConnection(drawerCommand);

    if (success) {
      print('✅ Cash drawer opened successfully');
    } else {
      print('❌ Failed to open cash drawer - no printer connection available');
    }

    return success;
  }

  /// Send drawer command via USB
  Future<bool> _sendDrawerCommandUSB(List<int> command) async {
    try {
      if (_persistentUsbPort == null) return false;

      await _persistentUsbPort!.write(Uint8List.fromList(command));
      await Future.delayed(
        Duration(milliseconds: 100),
      ); // Wait for command execution
      return true;
    } catch (e) {
      print('❌ USB drawer command error: $e');
      return false;
    }
  }

  /// Send drawer command via Bluetooth
  Future<bool> _sendDrawerCommandBluetooth(List<int> command) async {
    try {
      if (!_isBluetoothConnected) return false;

      await PrintBluetoothThermal.writeBytes(command);
      await Future.delayed(
        Duration(milliseconds: 100),
      ); // Wait for command execution
      return true;
    } catch (e) {
      print('❌ Bluetooth drawer command error: $e');
      return false;
    }
  }

  /// Try to establish a new connection and send drawer command
  Future<bool> _openDrawerWithNewConnection(List<int> command) async {
    // Test available connections
    Map<String, bool> connections = await testAllConnections();

    // Try USB first
    if (connections['usb'] == true) {
      try {
        if (_cachedUsbDevices.isEmpty) {
          _cachedUsbDevices = await UsbSerial.listDevices();
        }
        if (_cachedUsbDevices.isNotEmpty) {
          bool connected = await _establishUSBConnection(
            _cachedUsbDevices.first,
          );
          if (connected) {
            return await _sendDrawerCommandUSB(command);
          }
        }
      } catch (e) {
        print('❌ USB connection for drawer failed: $e');
      }
    }

    // Try Bluetooth
    if (connections['bluetooth'] == true) {
      try {
        bool connected = await _establishBluetoothConnection();
        if (connected) {
          return await _sendDrawerCommandBluetooth(command);
        }
      } catch (e) {
        print('❌ Bluetooth connection for drawer failed: $e');
      }
    }

    return false;
  }

  /// Test if cash drawer can be opened (check printer connections)
  Future<bool> canOpenDrawer() async {
    if (!_isDrawerOpeningEnabled) return false;
    if (kIsWeb) return false;

    // TEST MODE: Always return true for development testing
    if (ENABLE_DRAWER_TEST_MODE) {
      print('🧪 TEST MODE: Cash drawer is available (simulated)');
      return true;
    }

    // Quick check for existing connections
    if (_persistentUsbPort != null || _isBluetoothConnected) {
      return true;
    }

    // Check if any printers are available
    Map<String, bool> connections = await testAllConnections();
    return connections['usb'] == true || connections['bluetooth'] == true;
  }

  /// Configure cash drawer settings
  void setCashDrawerSettings({
    bool? enableDrawerOpening,
    bool? autoOpenOnCashPayment,
  }) {
    if (enableDrawerOpening != null) {
      _isDrawerOpeningEnabled = enableDrawerOpening;
      print(
        '💰 Drawer opening ${enableDrawerOpening ? "enabled" : "disabled"}',
      );
    }

    if (autoOpenOnCashPayment != null) {
      _autoOpenOnCashPayment = autoOpenOnCashPayment;
      print(
        '💰 Auto-open on cash payment ${autoOpenOnCashPayment ? "enabled" : "disabled"}',
      );
    }
  }

  /// Get current cash drawer settings
  Map<String, bool> getCashDrawerSettings() {
    return {
      'enabled': _isDrawerOpeningEnabled,
      'autoOpenOnCashPayment': _autoOpenOnCashPayment,
    };
  }

  // Cleanup method
  Future<void> dispose() async {
    _stopConnectionHealthMonitoring();
    await _closeAllConnections();
    _clearCache();
  }

  // Platform-specific helper methods
  Future<bool> _isUSBSerialAvailable() async {
    print('🔍 USB DEBUGGING: Checking USB Serial availability...');

    if (kIsWeb ||
        (!Platform.isAndroid && !Platform.isWindows && !Platform.isLinux)) {
      print(
        '❌ USB DEBUGGING: Platform not supported (${Platform.operatingSystem})',
      );
      return false;
    }

    try {
      // Request USB permissions for Android
      if (Platform.isAndroid) {
        print('📱 USB DEBUGGING: Requesting Android USB permissions...');
        await _requestUSBPermissions();
      }

      print('🔍 USB DEBUGGING: Listing USB devices...');
      List<UsbDevice> devices = await UsbSerial.listDevices();
      print('✅ USB DEBUGGING: Found ${devices.length} USB devices');

      if (devices.isEmpty) {
        print('⚠️ USB DEBUGGING: No USB devices detected!');
        print('   - Make sure USB printer is connected');
        print('   - Check USB cable integrity');
        print('   - Verify printer is powered on');
        print('   - Try different USB port');
        return false;
      }

      // Debug print device details
      for (int i = 0; i < devices.length; i++) {
        var device = devices[i];
        print('📄 USB DEBUGGING: Device $i Details:');
        print('   - Device Name: ${device.deviceName}');
        print(
          '   - VID: 0x${device.vid?.toRadixString(16).padLeft(4, '0').toUpperCase()}',
        );
        print(
          '   - PID: 0x${device.pid?.toRadixString(16).padLeft(4, '0').toUpperCase()}',
        );
        print('   - Manufacturer: ${device.manufacturerName ?? "Unknown"}');
        print('   - Product Name: ${device.productName ?? "Unknown"}');
        print('   - Serial: ${device.serial ?? "Unknown"}');

        // Check for common thermal printer VID/PIDs
        _analyzePrinterCompatibility(device);
      }

      return devices.isNotEmpty;
    } on MissingPluginException catch (e) {
      print('❌ USB DEBUGGING: USB Serial plugin not available: $e');
      return false;
    } catch (e) {
      print('❌ USB DEBUGGING: USB Serial availability check error: $e');
      return false;
    }
  }

  // Helper method to analyze if device is likely a thermal printer
  void _analyzePrinterCompatibility(UsbDevice device) {
    // Common thermal printer VID/PIDs
    final Map<int, List<int>> knownPrinters = {
      0x04b8: [0x0202, 0x0203, 0x0208], // Epson
      0x04f9: [0x2040, 0x2041, 0x2042], // Brother
      0x0456: [0x0808, 0x0809], // Star Micronics
      0x1FC9: [0x2016], // Citizen
      0x0483: [0x5740], // Various thermal printers
    };

    bool isKnownPrinter =
        knownPrinters[device.vid]?.contains(device.pid) ?? false;

    if (isKnownPrinter) {
      print('✅ USB DEBUGGING: Device appears to be a known thermal printer!');
    } else {
      print('⚠️ USB DEBUGGING: Device may not be a thermal printer');
      print('   - VID/PID not in known thermal printer database');
      print('   - May still work if it supports ESC/POS commands');
    }
  }

  Future<void> _requestUSBPermissions() async {
    if (kIsWeb || !Platform.isAndroid) return; // Only needed on Android

    try {
      // For USB OTG access on Android
      List<Permission> usbPermissions = [
        Permission.storage,
        Permission.manageExternalStorage,
      ];

      Map<Permission, PermissionStatus> statuses =
          await usbPermissions.request();

      for (var entry in statuses.entries) {
        if (entry.value != PermissionStatus.granted) {
          debugPrint('USB Permission ${entry.key} not granted: ${entry.value}');
        }
      }
    } catch (e) {
      debugPrint('Error requesting USB permissions: $e');
    }
  }

  Future<bool> _isBluetoothEnabled() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return false;
    }

    try {
      await _requestBluetoothPermissions();
      return await PrintBluetoothThermal.bluetoothEnabled;
    } catch (e) {
      return false;
    }
  }

  Future<void> _requestBluetoothPermissions() async {
    if (kIsWeb) return; // Skip permissions on web

    try {
      List<Permission> permissions = [
        Permission.bluetooth,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.location,
      ];

      Map<Permission, PermissionStatus> statuses = await permissions.request();

      for (var entry in statuses.entries) {
        if (entry.value != PermissionStatus.granted) {
          print('Permission ${entry.key} not granted: ${entry.value}');
        }
      }
    } catch (e) {
      print('Error requesting Bluetooth permissions: $e');
    }
  }

  BluetoothInfo? _findThermalPrinterDevice(List<BluetoothInfo> devices) {
    for (BluetoothInfo device in devices) {
      String deviceName = device.name.toLowerCase();
      if (deviceName.contains('printer') ||
          deviceName.contains('thermal') ||
          deviceName.contains('pos') ||
          deviceName.contains('receipt') ||
          deviceName.contains('rp')) {
        return device;
      }
    }
    return null;
  }

  String _generateReceiptContent({
    required String transactionId,
    required String orderType,
    required List<CartItem> cartItems,
    required double subtotal,
    required double totalCharge,
    String? extraNotes,
    required double changeDue,
    String? customerName,
    String? customerEmail,
    String? phoneNumber,
    String? streetAddress,
    String? city,
    String? postalCode,
    String? paymentType,
    bool? paidStatus,
    int? orderId,
  }) {
    StringBuffer receipt = StringBuffer();

    // Use full 80mm paper width (48 characters)
    receipt.writeln('================================================');
    receipt.writeln('                    **TVP**'); // Bold restaurant name
    receipt.writeln('================================================');
    receipt.writeln(
      'Date: ${DateFormat('dd/MM/yyyy HH:mm').format(UKTimeService.now())}',
    );
    if (orderId != null) {
      receipt.writeln('**Order #: $orderId**'); // Bold order number
    }
    receipt.writeln(
      '**Order Type: ${orderType.toUpperCase()}**',
    ); // Bold order type
    receipt.writeln('================================================');
    receipt.writeln();

    // Customer Details Section
    if (!_shouldExcludeField(customerName)) {
      receipt.writeln('CUSTOMER DETAILS:');
      receipt.writeln('------------------------------------------------');
      receipt.writeln('Name: $customerName');

      if (!_shouldExcludeField(phoneNumber)) {
        receipt.writeln('Phone: $phoneNumber');
      }

      // Address details for delivery orders
      if (orderType.toLowerCase() == 'delivery') {
        if (!_shouldExcludeField(streetAddress)) {
          receipt.writeln('Address: $streetAddress');
        }
        if (!_shouldExcludeField(city)) {
          receipt.writeln('City: $city');
        }
        if (!_shouldExcludeField(postalCode)) {
          receipt.writeln('Postcode: $postalCode');
        }
      }

      receipt.writeln('================================================');
      receipt.writeln();
    }

    receipt.writeln('ITEMS:');
    receipt.writeln('------------------------------------------------');

    for (CartItem item in cartItems) {
      double itemPricePerUnit = 0.0;
      if (item.foodItem.price.isNotEmpty) {
        var firstKey = item.foodItem.price.keys.first;
        itemPricePerUnit = item.foodItem.price[firstKey] ?? 0.0;
      }
      double itemTotal = itemPricePerUnit * item.quantity;

      receipt.writeln(
        '${item.quantity}x **${item.foodItem.name}**',
      ); // Bold item name only

      if (item.selectedOptions != null && item.selectedOptions!.isNotEmpty) {
        for (String option in item.selectedOptions!) {
          if (!_shouldExcludeField(option)) {
            receipt.writeln('  + $option');
          }
        }
      }

      if (!_shouldExcludeField(item.comment)) {
        receipt.writeln('  Note: ${item.comment}');
      }

      receipt.writeln('  £${itemTotal.toStringAsFixed(2)}');
      receipt.writeln();
    }

    receipt.writeln('------------------------------------------------');
    receipt.writeln(
      'Subtotal:                     £${subtotal.toStringAsFixed(2)}',
    );
    receipt.writeln('================================================');
    receipt.writeln(
      '**TOTAL:                      £${totalCharge.toStringAsFixed(2)}**', // Bold total
    );
    receipt.writeln('================================================');

    // Payment Status Section
    receipt.writeln();
    receipt.writeln('PAYMENT STATUS:');
    receipt.writeln('------------------------------------------------');
    if (!_shouldExcludeField(paymentType)) {
      receipt.writeln('**Payment Method: $paymentType**'); // Bold payment type
    }

    // Use the actual paid status from payment details
    String paymentStatus = (paidStatus == true) ? 'PAID' : 'UNPAID';

    // Show payment details based on payment type and status
    if (paidStatus == true) {
      if (paymentType != null &&
          paymentType.toLowerCase() == 'cash' &&
          changeDue > 0) {
        receipt.writeln(
          'Amount Received:  £${(totalCharge + changeDue).toStringAsFixed(2)}',
        );
        receipt.writeln('Change Due:       £${changeDue.toStringAsFixed(2)}');
      }
    }

    receipt.writeln(
      'Status: **$paymentStatus**',
    ); // Bold payment status (PAID/UNPAID)
    receipt.writeln('================================================');

    receipt.writeln();
    receipt.writeln('Thank you for your order!');
    receipt.writeln('================================================');

    return receipt.toString();
  }

  Future<List<int>> _generateESCPOSReceipt({
    required String transactionId,
    required String orderType,
    required List<CartItem> cartItems,
    required double subtotal,
    required double totalCharge,
    String? extraNotes,
    required double changeDue,
    String? customerName,
    String? customerEmail,
    String? phoneNumber,
    String? streetAddress,
    String? city,
    String? postalCode,
    String? paymentType,
    bool? paidStatus,
    int? orderId,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm80, profile); // 80mm paper width
    List<int> bytes = [];

    bytes += generator.setGlobalCodeTable('CP1252');

    // Bold restaurant name
    bytes += generator.text(
      'TVP',
      styles: const PosStyles(
        align: PosAlign.center,
        height: PosTextSize.size3,
        width: PosTextSize.size2,
        bold: true,
      ),
    );
    bytes += generator.text(
      '================================================',
      styles: const PosStyles(align: PosAlign.center),
    );
    bytes += generator.text(
      'Date: ${DateFormat('dd/MM/yyyy HH:mm').format(UKTimeService.now())}',
    );

    // Bold order number
    if (orderId != null) {
      bytes += generator.text(
        'Order #: $orderId',
        styles: const PosStyles(
          height: PosTextSize.size2,
          width: PosTextSize.size1,
          bold: true,
        ),
      );
    }

    // Bold order type
    bytes += generator.text(
      'Order Type: ${orderType.toUpperCase()}',
      styles: const PosStyles(bold: true),
    );
    bytes += generator.text(
      '================================================',
      styles: const PosStyles(align: PosAlign.center),
    );
    bytes += generator.emptyLines(1);

    // Customer Details Section - NOT BOLD
    if (!_shouldExcludeField(customerName)) {
      bytes += generator.text(
        'CUSTOMER DETAILS:',
        styles: const PosStyles(
          height: PosTextSize.size3,
          width: PosTextSize.size2,
        ),
      );
      bytes += generator.text(
        '------------------------------------------------',
      );
      bytes += generator.text(
        'Name: $customerName',
        styles: const PosStyles(
          height: PosTextSize.size2,
          width: PosTextSize.size1,
        ),
      );

      if (!_shouldExcludeField(phoneNumber)) {
        bytes += generator.text(
          'Phone: $phoneNumber',
          styles: const PosStyles(
            height: PosTextSize.size2,
            width: PosTextSize.size1,
          ),
        );
      }

      // Address details for delivery orders
      if (orderType.toLowerCase() == 'delivery') {
        if (!_shouldExcludeField(streetAddress)) {
          bytes += generator.text(
            'Address: $streetAddress',
            styles: const PosStyles(
              height: PosTextSize.size2,
              width: PosTextSize.size1,
            ),
          );
        }
        if (!_shouldExcludeField(city)) {
          bytes += generator.text(
            'City: $city',
            styles: const PosStyles(
              height: PosTextSize.size2,
              width: PosTextSize.size1,
            ),
          );
        }
        if (!_shouldExcludeField(postalCode)) {
          bytes += generator.text(
            'Postcode: $postalCode',
            styles: const PosStyles(
              height: PosTextSize.size2,
              width: PosTextSize.size1,
            ),
          );
        }
      }

      bytes += generator.text(
        '================================================',
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.emptyLines(1);
    }

    // ITEMS section - NOT BOLD
    bytes += generator.text(
      'ITEMS:',
      styles: const PosStyles(
        height: PosTextSize.size2,
        width: PosTextSize.size1,
      ),
    );
    bytes += generator.text('------------------------------------------------');

    for (CartItem item in cartItems) {
      double itemPricePerUnit = 0.0;
      if (item.foodItem.price.isNotEmpty) {
        var firstKey = item.foodItem.price.keys.first;
        itemPricePerUnit = item.foodItem.price[firstKey] ?? 0.0;
      }
      double itemTotal = itemPricePerUnit * item.quantity;

      // Bold item name ONLY
      bytes += generator.text(
        '${item.quantity}x ${item.foodItem.name}',
        styles: const PosStyles(
          height: PosTextSize.size1,
          width: PosTextSize.size1,
          bold: true,
        ),
      );

      if (item.selectedOptions != null && item.selectedOptions!.isNotEmpty) {
        for (String option in item.selectedOptions!) {
          if (!_shouldExcludeField(option)) {
            bytes += generator.text('  + $option');
          }
        }
      }

      if (!_shouldExcludeField(item.comment)) {
        bytes += generator.text('  Note: ${item.comment}');
      }

      bytes += generator.text(
        '  £${itemTotal.toStringAsFixed(2)}',
        styles: const PosStyles(
          align: PosAlign.right,
          height: PosTextSize.size1,
          width: PosTextSize.size1,
        ),
      );
      bytes += generator.emptyLines(1);
    }

    bytes += generator.text('------------------------------------------------');
    bytes += generator.row([
      PosColumn(text: 'Subtotal:', width: 9),
      PosColumn(
        text: '£${subtotal.toStringAsFixed(2)}',
        width: 3,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);
    bytes += generator.text(
      '================================================',
      styles: const PosStyles(align: PosAlign.center),
    );

    // Bold total amount
    bytes += generator.row([
      PosColumn(text: 'TOTAL:', width: 9, styles: const PosStyles(bold: true)),
      PosColumn(
        text: '£${totalCharge.toStringAsFixed(2)}',
        width: 3,
        styles: const PosStyles(align: PosAlign.right, bold: true),
      ),
    ]);
    bytes += generator.text(
      '================================================',
      styles: const PosStyles(align: PosAlign.center),
    );

    // Payment Status Section - NOT BOLD except specific elements
    bytes += generator.emptyLines(1);
    bytes += generator.text(
      'PAYMENT STATUS:',
      styles: const PosStyles(
        height: PosTextSize.size2,
        width: PosTextSize.size1,
      ),
    );
    bytes += generator.text('------------------------------------------------');

    // Bold payment method
    if (!_shouldExcludeField(paymentType)) {
      bytes += generator.text(
        'Payment Method: $paymentType',
        styles: const PosStyles(height: PosTextSize.size1, bold: true),
      );
    }

    // Determine payment status based on payment method
    String paymentStatus = 'UNPAID';

    if (paymentType != null) {
      final paymentTypeLower = paymentType.toLowerCase();

      // For website orders: Card = PAID, COD/Cash = UNPAID
      // For EPOS orders: Use existing logic
      if (paymentTypeLower.contains('card') ||
          paymentTypeLower.contains('online') ||
          paymentTypeLower.contains('paypal')) {
        paymentStatus = 'PAID';
      } else if (paymentTypeLower == 'cash' ||
          paymentTypeLower.contains('cod')) {
        // Cash/COD orders are UNPAID unless it's EPOS cash with change due
        if (paymentTypeLower == 'cash' && changeDue > 0) {
          // EPOS cash order with change due - it's been paid
          paymentStatus = 'PAID';
        } else {
          // Website COD or EPOS cash without change - unpaid
          paymentStatus = 'UNPAID';
        }
      } else {
        // Default to PAID for other payment methods
        paymentStatus = 'PAID';
      }
    }

    // Show payment details for paid orders
    if (paymentStatus == 'PAID' &&
        paymentType != null &&
        paymentType.toLowerCase() == 'cash' &&
        changeDue > 0) {
      bytes += generator.row([
        PosColumn(text: 'Amount Received:', width: 9),
        PosColumn(
          text: '£${(totalCharge + changeDue).toStringAsFixed(2)}',
          width: 3,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      bytes += generator.row([
        PosColumn(text: 'Change Due:', width: 9),
        PosColumn(
          text: '£${changeDue.toStringAsFixed(2)}',
          width: 3,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    // Bold payment status (PAID/UNPAID)
    bytes += generator.text(
      'Status: $paymentStatus',
      styles: const PosStyles(
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size1,
      ),
    );
    bytes += generator.text(
      '================================================',
      styles: const PosStyles(align: PosAlign.center),
    );

    bytes += generator.emptyLines(1);
    bytes += generator.text(
      'Thank you for your order!',
      styles: const PosStyles(
        align: PosAlign.center,
        height: PosTextSize.size2,
        width: PosTextSize.size1,
      ),
    );
    bytes += generator.text(
      '================================================',
      styles: const PosStyles(align: PosAlign.center),
    );

    bytes += generator.emptyLines(2);
    bytes += generator.cut();

    return bytes;
  }

  Future<List<int>> _generateThermalTicket(String content) async {
    List<int> bytes = [];
    bytes.addAll(content.codeUnits);
    bytes.addAll([10, 10, 10]); // 3 line feeds
    bytes.addAll([29, 86, 65, 0]); // Full cut
    return bytes;
  }

  Future<bool> printSalesReportWithUserInteraction({
    required String reportType,
    required Map<String, dynamic> reportData,
    required Map<String, String> filters,
    String? selectedDate,
    int? selectedYear,
    int? selectedWeek,
    int? selectedMonth,
    Function(List<String> availableMethods)? onShowMethodSelection,
  }) async {
    if (kIsWeb) {
      print('🚫 Web platform - printer not supported');
      throw Exception(
        'Printing is not supported on web platform. Please use a mobile or desktop app.',
      );
    }

    print('🖨️ Starting sales report print job...');

    try {
      // Test connections in parallel with report generation
      Future<Map<String, bool>> connectionTestFuture = testAllConnections();

      Future<List<int>> reportDataFuture = _generateSalesReportESCPOS(
        reportType: reportType,
        reportData: reportData,
        filters: filters,
        selectedDate: selectedDate,
        selectedYear: selectedYear,
        selectedWeek: selectedWeek,
        selectedMonth: selectedMonth,
      );

      Future<String> reportContentFuture = Future.value(
        _generateSalesReportContent(
          reportType: reportType,
          reportData: reportData,
          filters: filters,
          selectedDate: selectedDate,
          selectedYear: selectedYear,
          selectedWeek: selectedWeek,
          selectedMonth: selectedMonth,
        ),
      );

      // Wait for all preparations to complete
      List<dynamic> results = await Future.wait([
        connectionTestFuture,
        reportDataFuture,
        reportContentFuture,
      ]);

      Map<String, bool> connectionStatus = results[0];
      List<int> thermalReportData = results[1];
      String reportContent = results[2];

      List<String> availableMethods = [];
      if (connectionStatus['usb'] == true) availableMethods.add('USB');
      if (connectionStatus['bluetooth'] == true)
        availableMethods.add('Thermal Bluetooth');

      if (availableMethods.isEmpty) {
        print('❌ No printer connections available');
        String errorMessage = 'No thermal printers detected. Please ensure:\n';
        errorMessage +=
            '• A thermal printer is connected via USB or Bluetooth\n';
        errorMessage += '• The printer is powered on\n';
        errorMessage +=
            '• For Bluetooth: The printer is paired with this device\n';
        errorMessage += '• For USB: The printer is properly connected';

        if (onShowMethodSelection != null) {
          onShowMethodSelection(['No printers available']);
        }
        throw Exception(errorMessage);
      }

      // Start connection health monitoring
      _startConnectionHealthMonitoring();

      // Try available methods with pre-generated data
      bool printSuccess = false;
      String lastError = '';

      for (String method in availableMethods) {
        print('🚀 Attempting $method sales report printing...');

        try {
          bool success = await _printSalesReportWithPreGeneratedData(
            method: method,
            reportData: thermalReportData,
            reportContent: reportContent,
          );

          if (success) {
            print('✅ $method sales report printing successful');
            printSuccess = true;
            break;
          } else {
            lastError = '$method printing failed - printer may be offline';
          }
        } catch (e) {
          lastError = '$method printing failed: ${e.toString()}';
          print('❌ $method error: $e');
        }
      }

      if (!printSuccess) {
        print('❌ All available methods failed');
        if (onShowMethodSelection != null) {
          onShowMethodSelection(availableMethods);
        }
        throw Exception(
          'Printing failed on all available methods. Last error: $lastError',
        );
      }

      return true;
    } catch (e) {
      print('❌ Sales report printing error: $e');
      rethrow;
    }
  }

  // REPLACE the _printSalesReportWithPreGeneratedData method:
  Future<bool> _printSalesReportWithPreGeneratedData({
    required String method,
    required List<int> reportData,
    required String reportContent,
  }) async {
    try {
      switch (method) {
        case 'USB':
          return await _printUSBSalesReportSuperFast(reportData);
        case 'Thermal Bluetooth':
          return await _printBluetoothSalesReportSuperFast(reportContent);
        default:
          throw Exception('Unknown printing method: $method');
      }
    } catch (e) {
      print('❌ Error in $method printing: $e');
      return false;
    }
  }

  Future<bool> _printUSBSalesReportSuperFast(List<int> reportData) async {
    if (kIsWeb ||
        (!Platform.isAndroid && !Platform.isWindows && !Platform.isLinux)) {
      throw Exception('USB printing not supported on this platform');
    }

    if (ENABLE_MOCK_MODE) {
      await Future.delayed(Duration(milliseconds: 1000));
      print('🧪 MOCK: USB sales report printing simulated');
      print('📊 Report data length: ${reportData.length} bytes');
      if (SIMULATE_PRINTER_SUCCESS) {
        return true;
      } else {
        throw Exception('Mock printer simulation failed');
      }
    }

    try {
      // Ensure we have a persistent connection
      if (_persistentUsbPort == null) {
        if (_cachedUsbDevices.isEmpty) {
          _cachedUsbDevices = await UsbSerial.listDevices();
        }
        if (_cachedUsbDevices.isEmpty) {
          throw Exception(
            'No USB devices found. Please connect a USB thermal printer.',
          );
        }

        if (!await _establishUSBConnection(_cachedUsbDevices.first)) {
          throw Exception(
            'Failed to establish USB connection. Please check printer connection.',
          );
        }
      }

      // Print the sales report
      await _persistentUsbPort!.write(Uint8List.fromList(reportData));
      await Future.delayed(Duration(milliseconds: 100));

      print('✅ USB sales report print successful');
      return true;
    } catch (e) {
      print('❌ USB sales report print error: $e');
      await _closeUsbConnection();
      throw Exception('USB printing failed: ${e.toString()}');
    }
  }

  // REPLACE the Bluetooth printing method with better error handling:
  Future<bool> _printBluetoothSalesReportSuperFast(String reportContent) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      throw Exception('Bluetooth printing not supported on this platform');
    }

    if (ENABLE_MOCK_MODE) {
      await Future.delayed(Duration(milliseconds: 1200));
      print('🧪 MOCK: Bluetooth sales report printing simulated');
      print('📊 Report content preview:');
      print(
        reportContent.substring(0, math.min(300, reportContent.length)) + '...',
      );
      if (SIMULATE_PRINTER_SUCCESS) {
        return true;
      } else {
        throw Exception('Mock Bluetooth printer simulation failed');
      }
    }

    try {
      // Ensure we have a persistent connection
      if (!_isBluetoothConnected) {
        if (!await _establishBluetoothConnection()) {
          throw Exception(
            'Failed to establish Bluetooth connection. Please check if printer is paired and turned on.',
          );
        }
      }

      // Verify connection is still active
      bool isStillConnected = await PrintBluetoothThermal.connectionStatus;
      if (!isStillConnected) {
        throw Exception(
          'Bluetooth printer is not connected. Please check printer status.',
        );
      }

      // Generate thermal ticket and print immediately
      List<int> ticket = await _generateThermalTicket(reportContent);
      await PrintBluetoothThermal.writeBytes(ticket);

      print('✅ Bluetooth sales report print successful');
      return true;
    } catch (e) {
      print('❌ Bluetooth sales report print error: $e');
      await _closeBluetoothConnection();
      throw Exception('Bluetooth printing failed: ${e.toString()}');
    }
  }

  // Generate sales report content for thermal printing
  String _generateSalesReportContent({
    required String reportType,
    required Map<String, dynamic> reportData,
    required Map<String, String> filters,
    String? selectedDate,
    int? selectedYear,
    int? selectedWeek,
    int? selectedMonth,
  }) {
    StringBuffer report = StringBuffer();

    // Header
    report.writeln('================================');
    report.writeln('              TVP');
    report.writeln('================================');
    report.writeln();

    // Report Title and Date
    report.writeln(reportType.toUpperCase());
    report.writeln('--------------------------------');

    // Period information
    String periodText = _getPeriodText(
      reportData,
      reportType,
      selectedDate,
      selectedYear,
      selectedWeek,
      selectedMonth,
    );
    report.writeln('Period: $periodText');
    report.writeln(
      'Generated: ${DateFormat('dd/MM/yyyy HH:mm').format(UKTimeService.now())}',
    );
    report.writeln('================================');
    report.writeln();

    // Applied Filters
    if (filters['source'] != 'All' ||
        filters['payment'] != 'All' ||
        filters['orderType'] != 'All') {
      report.writeln('APPLIED FILTERS:');
      report.writeln('--------------------------------');
      if (filters['source'] != 'All')
        report.writeln('Source: ${filters['source']}');
      if (filters['payment'] != 'All')
        report.writeln('Payment: ${filters['payment']}');
      if (filters['orderType'] != 'All')
        report.writeln('Order Type: ${filters['orderType']}');
      report.writeln('================================');
      report.writeln();
    }

    // Summary Section
    report.writeln('SUMMARY:');
    report.writeln('--------------------------------');

    // Total Sales Amount
    final totalSales =
        reportData['total_sales'] ?? reportData['total_sales_amount'];
    report.writeln('Total Sales: ${_formatCurrency(totalSales)}');

    // Total Orders Placed
    if (reportData['total_orders_placed'] != null) {
      report.writeln('Total Orders: ${reportData['total_orders_placed']}');
    }

    // Sales Increase
    final salesIncrease = reportData['sales_increase'];
    if (salesIncrease != null) {
      final increase = double.tryParse(salesIncrease.toString()) ?? 0.0;
      final isPositive = increase >= 0;
      report.writeln(
        'Sales ${isPositive ? 'Increase' : 'Decrease'}: ${isPositive ? '+' : ''}${_formatCurrency(salesIncrease)}',
      );
    }

    // Most Sold Item
    final mostSoldItem =
        reportData['most_selling_item'] ?? reportData['most_sold_item'];
    if (mostSoldItem != null) {
      final itemName = mostSoldItem['item_name'] ?? 'Unknown';
      final quantity = mostSoldItem['quantity_sold'] ?? '0';
      report.writeln('Top Item: $itemName ($quantity sold)');
    }

    // Most Sold Type
    final mostSoldType = reportData['most_sold_type'];
    if (mostSoldType != null) {
      final typeName = mostSoldType['type'] ?? 'Unknown';
      final quantity = mostSoldType['quantity_sold'] ?? '0';
      report.writeln('Top Category: $typeName ($quantity sold)');
    }

    report.writeln('================================');
    report.writeln();

    // Sales by Payment Method
    final paymentTypes = reportData['sales_by_payment_type'] as List<dynamic>?;
    if (paymentTypes != null && paymentTypes.isNotEmpty) {
      report.writeln('SALES BY PAYMENT METHOD:');
      report.writeln('--------------------------------');
      for (var payment in paymentTypes) {
        if (payment is Map) {
          final type =
              payment['payment_type']?.toString().toUpperCase() ?? 'UNKNOWN';
          final count = payment['count']?.toString() ?? '0';
          final total = _formatCurrency(payment['total']);
          report.writeln('$type:');
          report.writeln('  Orders: $count');
          report.writeln('  Amount: $total');
          report.writeln();
        }
      }
      report.writeln('================================');
      report.writeln();
    }

    // Sales by Order Type
    final orderTypes = reportData['sales_by_order_type'] as List<dynamic>?;
    if (orderTypes != null && orderTypes.isNotEmpty) {
      report.writeln('SALES BY ORDER TYPE:');
      report.writeln('--------------------------------');
      for (var orderType in orderTypes) {
        if (orderType is Map) {
          final type =
              orderType['order_type']?.toString().toUpperCase() ?? 'UNKNOWN';
          final count = orderType['count']?.toString() ?? '0';
          final total = _formatCurrency(orderType['total']);
          report.writeln('$type:');
          report.writeln('  Orders: $count');
          report.writeln('  Amount: $total');
          report.writeln();
        }
      }
      report.writeln('================================');
      report.writeln();
    }

    // Sales by Order Source
    final orderSources = reportData['sales_by_order_source'] as List<dynamic>?;
    if (orderSources != null && orderSources.isNotEmpty) {
      report.writeln('SALES BY ORDER SOURCE:');
      report.writeln('--------------------------------');
      for (var source in orderSources) {
        if (source is Map) {
          final sourceName =
              source['source']?.toString().toUpperCase() ?? 'UNKNOWN';
          final count = source['count']?.toString() ?? '0';
          final total = _formatCurrency(source['total']);
          report.writeln('$sourceName:');
          report.writeln('  Orders: $count');
          report.writeln('  Amount: $total');
          report.writeln();
        }
      }
      report.writeln('================================');
      report.writeln();
    }

    // Footer
    report.writeln('End of Report');
    report.writeln('================================');

    return report.toString();
  }

  // Generate ESC/POS commands for sales report
  Future<List<int>> _generateSalesReportESCPOS({
    required String reportType,
    required Map<String, dynamic> reportData,
    required Map<String, String> filters,
    String? selectedDate,
    int? selectedYear,
    int? selectedWeek,
    int? selectedMonth,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(
      PaperSize.mm80,
      profile,
    ); // 80mm paper width // 80mm paper
    List<int> bytes = [];

    bytes += generator.setGlobalCodeTable('CP1252');

    // Header
    bytes += generator.text(
      'TVP',
      styles: const PosStyles(
        align: PosAlign.center,
        height: PosTextSize.size3,
        width: PosTextSize.size2,
        bold: true,
      ),
    );
    bytes += generator.text(
      '================================================',
      styles: const PosStyles(align: PosAlign.center),
    );
    bytes += generator.emptyLines(1);

    // Report Title and Date
    bytes += generator.text(
      reportType.toUpperCase(),
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size1,
      ),
    );
    bytes += generator.text('------------------------------------------------');

    // Period information
    String periodText = _getPeriodText(
      reportData,
      reportType,
      selectedDate,
      selectedYear,
      selectedWeek,
      selectedMonth,
    );
    bytes += generator.text('Period: $periodText');
    bytes += generator.text(
      'Generated: ${DateFormat('dd/MM/yyyy HH:mm').format(UKTimeService.now())}',
    );
    bytes += generator.text(
      '================================================',
      styles: const PosStyles(align: PosAlign.center),
    );
    bytes += generator.emptyLines(1);

    // Applied Filters
    if (filters['source'] != 'All' ||
        filters['payment'] != 'All' ||
        filters['orderType'] != 'All') {
      bytes += generator.text(
        'APPLIED FILTERS:',
        styles: const PosStyles(bold: true),
      );
      bytes += generator.text(
        '------------------------------------------------',
      );
      if (filters['source'] != 'All')
        bytes += generator.text('Source: ${filters['source']}');
      if (filters['payment'] != 'All')
        bytes += generator.text('Payment: ${filters['payment']}');
      if (filters['orderType'] != 'All')
        bytes += generator.text('Order Type: ${filters['orderType']}');
      bytes += generator.text(
        '================================================',
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.emptyLines(1);
    }

    // Summary Section
    bytes += generator.text(
      'SUMMARY:',
      styles: const PosStyles(
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size1,
      ),
    );
    bytes += generator.text('------------------------------------------------');

    // Total Sales Amount
    final totalSales =
        reportData['total_sales'] ?? reportData['total_sales_amount'];
    bytes += generator.row([
      PosColumn(text: 'Total Sales:', width: 9),
      PosColumn(
        text: _formatCurrency(totalSales),
        width: 3,
        styles: const PosStyles(align: PosAlign.right, bold: true),
      ),
    ]);

    // Total Orders Placed
    if (reportData['total_orders_placed'] != null) {
      bytes += generator.row([
        PosColumn(text: 'Total Orders:', width: 9),
        PosColumn(
          text: '${reportData['total_orders_placed']}',
          width: 3,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    // Sales Increase
    final salesIncrease = reportData['sales_increase'];
    if (salesIncrease != null) {
      final increase = double.tryParse(salesIncrease.toString()) ?? 0.0;
      final isPositive = increase >= 0;
      bytes += generator.row([
        PosColumn(
          text: 'Sales ${isPositive ? 'Increase' : 'Decrease'}:',
          width: 9,
        ),
        PosColumn(
          text: '${isPositive ? '+' : ''}${_formatCurrency(salesIncrease)}',
          width: 3,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    // Most Sold Item
    final mostSoldItem =
        reportData['most_selling_item'] ?? reportData['most_sold_item'];
    if (mostSoldItem != null) {
      final itemName = mostSoldItem['item_name'] ?? 'Unknown';
      final quantity = mostSoldItem['quantity_sold'] ?? '0';
      bytes += generator.text('Top Item: $itemName ($quantity sold)');
    }

    // Most Sold Type
    final mostSoldType = reportData['most_sold_type'];
    if (mostSoldType != null) {
      final typeName = mostSoldType['type'] ?? 'Unknown';
      final quantity = mostSoldType['quantity_sold'] ?? '0';
      bytes += generator.text('Top Category: $typeName ($quantity sold)');
    }

    bytes += generator.text(
      '================================================',
      styles: const PosStyles(align: PosAlign.center),
    );
    bytes += generator.emptyLines(1);

    // Sales by Payment Method
    final paymentTypes = reportData['sales_by_payment_type'] as List<dynamic>?;
    if (paymentTypes != null && paymentTypes.isNotEmpty) {
      bytes += generator.text(
        'SALES BY PAYMENT METHOD:',
        styles: const PosStyles(
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size1,
        ),
      );
      bytes += generator.text(
        '------------------------------------------------',
      );
      for (var payment in paymentTypes) {
        if (payment is Map) {
          final type =
              payment['payment_type']?.toString().toUpperCase() ?? 'UNKNOWN';
          final count = payment['count']?.toString() ?? '0';
          final total = _formatCurrency(payment['total']);
          bytes += generator.text(
            '$type:',
            styles: const PosStyles(bold: true),
          );
          bytes += generator.row([
            PosColumn(text: '  Orders:', width: 9),
            PosColumn(
              text: count,
              width: 3,
              styles: const PosStyles(align: PosAlign.right),
            ),
          ]);
          bytes += generator.row([
            PosColumn(text: '  Amount:', width: 9),
            PosColumn(
              text: total,
              width: 3,
              styles: const PosStyles(align: PosAlign.right),
            ),
          ]);
          bytes += generator.emptyLines(1);
        }
      }
      bytes += generator.text(
        '================================================',
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.emptyLines(1);
    }

    // Sales by Order Type
    final orderTypes = reportData['sales_by_order_type'] as List<dynamic>?;
    if (orderTypes != null && orderTypes.isNotEmpty) {
      bytes += generator.text(
        'SALES BY ORDER TYPE:',
        styles: const PosStyles(
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size1,
        ),
      );
      bytes += generator.text(
        '------------------------------------------------',
      );
      for (var orderType in orderTypes) {
        if (orderType is Map) {
          final type =
              orderType['order_type']?.toString().toUpperCase() ?? 'UNKNOWN';
          final count = orderType['count']?.toString() ?? '0';
          final total = _formatCurrency(orderType['total']);
          bytes += generator.text(
            '$type:',
            styles: const PosStyles(bold: true),
          );
          bytes += generator.row([
            PosColumn(text: '  Orders:', width: 9),
            PosColumn(
              text: count,
              width: 3,
              styles: const PosStyles(align: PosAlign.right),
            ),
          ]);
          bytes += generator.row([
            PosColumn(text: '  Amount:', width: 9),
            PosColumn(
              text: total,
              width: 3,
              styles: const PosStyles(align: PosAlign.right),
            ),
          ]);
          bytes += generator.emptyLines(1);
        }
      }
      bytes += generator.text(
        '================================================',
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.emptyLines(1);
    }

    // Sales by Order Source
    final orderSources = reportData['sales_by_order_source'] as List<dynamic>?;
    if (orderSources != null && orderSources.isNotEmpty) {
      bytes += generator.text(
        'SALES BY ORDER SOURCE:',
        styles: const PosStyles(
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size1,
        ),
      );
      bytes += generator.text(
        '------------------------------------------------',
      );
      for (var source in orderSources) {
        if (source is Map) {
          final sourceName =
              source['source']?.toString().toUpperCase() ?? 'UNKNOWN';
          final count = source['count']?.toString() ?? '0';
          final total = _formatCurrency(source['total']);
          bytes += generator.text(
            '$sourceName:',
            styles: const PosStyles(bold: true),
          );
          bytes += generator.row([
            PosColumn(text: '  Orders:', width: 9),
            PosColumn(
              text: count,
              width: 3,
              styles: const PosStyles(align: PosAlign.right),
            ),
          ]);
          bytes += generator.row([
            PosColumn(text: '  Amount:', width: 9),
            PosColumn(
              text: total,
              width: 3,
              styles: const PosStyles(align: PosAlign.right),
            ),
          ]);
          bytes += generator.emptyLines(1);
        }
      }
      bytes += generator.text(
        '================================================',
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.emptyLines(1);
    }

    // Footer
    bytes += generator.text(
      'End of Report',
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );
    bytes += generator.text(
      '================================================',
      styles: const PosStyles(align: PosAlign.center),
    );

    bytes += generator.emptyLines(3);
    bytes += generator.cut();

    return bytes;
  }

  // Helper method to get period text
  String _getPeriodText(
    Map<String, dynamic> reportData,
    String reportType,
    String? selectedDate,
    int? selectedYear,
    int? selectedWeek,
    int? selectedMonth,
  ) {
    switch (reportType) {
      case "Today's Report":
        return DateFormat('dd/MM/yyyy').format(UKTimeService.now());
      case 'Daily Report':
        return selectedDate ??
            DateFormat('dd/MM/yyyy').format(UKTimeService.now());
      case 'Weekly Report':
        return 'Year: ${selectedYear ?? DateTime.now().year}, Week: ${selectedWeek ?? _getWeekNumber(UKTimeService.now())}';
      case 'Monthly Report':
        final months = [
          'January',
          'February',
          'March',
          'April',
          'May',
          'June',
          'July',
          'August',
          'September',
          'October',
          'November',
          'December',
        ];
        final monthName = months[(selectedMonth ?? DateTime.now().month) - 1];
        return 'Year: ${selectedYear ?? DateTime.now().year}, Month: $monthName';
      case 'Drivers Report':
        return selectedDate ??
            DateFormat('dd/MM/yyyy').format(UKTimeService.now());
      default:
        final period = reportData['period'];
        if (period != null && period is Map) {
          return '${period['from']} ~ ${period['to']}';
        }
        return DateFormat('dd/MM/yyyy').format(UKTimeService.now());
    }
  }

  // Helper method to format currency
  String _formatCurrency(dynamic amount) {
    if (amount == null) return '£0.00';
    final value = double.tryParse(amount.toString()) ?? 0.0;
    return '£${value.toStringAsFixed(2)}';
  }

  // Helper method to get week number
  static int _getWeekNumber(DateTime date) {
    int dayOfYear =
        int.parse(
          date.difference(DateTime(date.year, 1, 1)).inDays.toString(),
        ) +
        1;
    return ((dayOfYear - date.weekday + 10) / 7).floor();
  }
}
