import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

/// Service class for Xprinter SDK integration
class XprinterService {
  static const MethodChannel _channel = MethodChannel('xprinter_sdk');

  static final XprinterService _instance = XprinterService._internal();
  factory XprinterService() => _instance;
  XprinterService._internal();

  bool _isConnected = false;
  String? _connectedDevice;

  /// Get list of available USB devices
  Future<List<Map<String, dynamic>>> getUsbDevices() async {
    try {
      if (kDebugMode) {
        print('🔍 XprinterService: Getting USB devices...');
      }

      final List<dynamic> devices = await _channel.invokeMethod(
        'getUsbDevices',
      );
      final List<Map<String, dynamic>> usbDevices =
          devices.map((device) => Map<String, dynamic>.from(device)).toList();

      if (kDebugMode) {
        print('📱 XprinterService: Found ${usbDevices.length} USB devices');
        for (var device in usbDevices) {
          print(
            '   - ${device['deviceName']} (VID: ${device['vendorId']}, PID: ${device['productId']})',
          );
        }
      }

      return usbDevices;
    } catch (e) {
      if (kDebugMode) {
        print('❌ XprinterService: Error getting USB devices: $e');
      }
      rethrow;
    }
  }

  /// Connect to USB printer
  Future<bool> connectUsb(String devicePath) async {
    try {
      if (kDebugMode) {
        print('🔗 XprinterService: Connecting to USB device: $devicePath');
      }

      final bool connected = await _channel.invokeMethod('connectUsb', {
        'devicePath': devicePath,
      });

      if (connected) {
        _isConnected = true;
        _connectedDevice = devicePath;
        if (kDebugMode) {
          print('✅ XprinterService: Successfully connected to USB printer');
        }
      } else {
        if (kDebugMode) {
          print('❌ XprinterService: Failed to connect to USB printer');
        }
      }

      return connected;
    } catch (e) {
      if (kDebugMode) {
        print('❌ XprinterService: Error connecting USB printer: $e');
      }
      return false;
    }
  }

  /// Disconnect from printer
  Future<bool> disconnect() async {
    try {
      if (kDebugMode) {
        print('🔌 XprinterService: Disconnecting from printer...');
      }

      final bool disconnected = await _channel.invokeMethod('disconnect');

      if (disconnected) {
        _isConnected = false;
        _connectedDevice = null;
        if (kDebugMode) {
          print('✅ XprinterService: Successfully disconnected');
        }
      }

      return disconnected;
    } catch (e) {
      if (kDebugMode) {
        print('❌ XprinterService: Error disconnecting: $e');
      }
      return false;
    }
  }

  /// Print receipt data
  Future<bool> printReceipt(String receiptData) async {
    try {
      if (!_isConnected) {
        throw Exception('Printer not connected');
      }

      if (kDebugMode) {
        print('🖨️ XprinterService: Printing receipt...');
      }

      // Apply encoding fixes to properly display pound sign and other special characters
      String encodedReceiptData = _applyXprinterEncodingFixes(receiptData);

      final bool printed = await _channel.invokeMethod('printReceipt', {
        'receiptData': encodedReceiptData,
      });

      if (kDebugMode) {
        if (printed) {
          print(
            '✅ XprinterService: Receipt printed successfully with encoding fixes',
          );
        } else {
          print('❌ XprinterService: Failed to print receipt');
        }
      }

      return printed;
    } catch (e) {
      if (kDebugMode) {
        print('❌ XprinterService: Error printing receipt: $e');
      }
      return false;
    }
  }

  /// Open cash drawer
  Future<bool> openCashBox({
    int pinNum = 0, // 0=PIN_TWO, 1=PIN_FIVE
    int onTime = 30,
    int offTime = 255,
  }) async {
    try {
      if (!_isConnected) {
        throw Exception('Printer not connected');
      }

      final bool opened = await _channel.invokeMethod('openCashBox', {
        'pinNum': pinNum,
        'onTime': onTime,
        'offTime': offTime,
      });

      if (kDebugMode) {
        if (opened) {
          print('💰 XprinterService: Cash box opened successfully');
        } else {
          print('❌ XprinterService: Failed to open cash box');
        }
      }

      return opened;
    } catch (e) {
      if (kDebugMode) {
        print('❌ XprinterService: Error opening cash box: $e');
      }
      return false;
    }
  }

  /// Get printer status
  Future<Map<String, dynamic>?> getPrinterStatus() async {
    try {
      if (!_isConnected) {
        return {'connected': false, 'statusCode': -1};
      }

      final Map<dynamic, dynamic> status = await _channel.invokeMethod(
        'printerStatus',
      );
      return Map<String, dynamic>.from(status);
    } catch (e) {
      if (kDebugMode) {
        print('❌ XprinterService: Error getting printer status: $e');
      }
      return null;
    }
  }

  // Getters
  bool get isConnected => _isConnected;
  String? get connectedDevice => _connectedDevice;

  /// Apply Xprinter-specific character encoding fixes for proper display
  /// This ensures pound signs and other special characters display correctly
  String _applyXprinterEncodingFixes(String content) {
    if (kDebugMode) {
      print('🔧 XprinterService: Applying character encoding fixes...');
    }

    String fixedContent = content;

    // Based on Xprinter manual - using CP437 (Code Page 0) as default
    // Critical encoding fixes for special characters
    final Map<String, String> encodingFixes = {
      // Currency symbols - CRITICAL for pound sign issue
      '£': String.fromCharCode(
        0x9C,
      ), // Code 156 in CP437 - Pound sign (KEY FIX)
      '€': String.fromCharCode(0xEE), // Code 238 in CP437 - Euro sign
      // Common special characters that may cause issues
      '\u2018': String.fromCharCode(
        0x27,
      ), // Left single quotation mark (U+2018) -> apostrophe
      '\u2019': String.fromCharCode(
        0x27,
      ), // Right single quotation mark (U+2019) -> apostrophe
      '\u201C': String.fromCharCode(
        0x22,
      ), // Left double quotation mark (U+201C) -> regular quote
      '\u201D': String.fromCharCode(
        0x22,
      ), // Right double quotation mark (U+201D) -> regular quote
      '\u2013': String.fromCharCode(0x2D), // En dash (U+2013) -> hyphen
      '\u2014': String.fromCharCode(0x2D), // Em dash (U+2014) -> hyphen
    };

    // Apply all encoding fixes
    encodingFixes.forEach((unicode, encoded) {
      if (fixedContent.contains(unicode)) {
        if (kDebugMode) {
          print('   Fixing character: $unicode -> CP437 equivalent');
        }
        fixedContent = fixedContent.replaceAll(unicode, encoded);
      }
    });

    if (kDebugMode) {
      print('✅ XprinterService: Character encoding fixes applied');
    }

    return fixedContent;
  }
}
