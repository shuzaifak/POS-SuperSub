package com.example.epos;

import android.content.Context;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbManager;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.nio.charset.Charset;
import java.io.UnsupportedEncodingException;

import net.posprinter.IDeviceConnection;
import net.posprinter.POSConnect;
import net.posprinter.POSPrinter;

/**
 * XprinterPlugin handles communication between Flutter and Xprinter SDK
 */
public class XprinterPlugin implements FlutterPlugin, MethodCallHandler {
    private static final String TAG = "XprinterPlugin";
    private static final String CHANNEL = "xprinter_sdk";

    private MethodChannel channel;
    private Context context;
    private ExecutorService executor;
    private Handler mainHandler;

    // Xprinter SDK objects
    private IDeviceConnection usbConnection;
    private POSPrinter posPrinter;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this);
        context = flutterPluginBinding.getApplicationContext();
        executor = Executors.newSingleThreadExecutor();
        mainHandler = new Handler(Looper.getMainLooper());

        // Initialize POSConnect SDK
        POSConnect.init(context);
        Log.d(TAG, "Xprinter SDK initialized");
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        switch (call.method) {
            case "getUsbDevices":
                getUsbDevices(result);
                break;
            case "connectUsb":
                String devicePath = call.argument("devicePath");
                connectUsb(devicePath, result);
                break;
            case "disconnect":
                disconnect(result);
                break;
            case "printReceipt":
                String receiptData = call.argument("receiptData");
                printReceipt(receiptData, result);
                break;
            case "openCashBox":
                Integer pinNum = call.argument("pinNum");
                Integer onTime = call.argument("onTime");
                Integer offTime = call.argument("offTime");
                openCashBox(pinNum, onTime, offTime, result);
                break;
            case "printerStatus":
                printerStatus(result);
                break;
            default:
                result.notImplemented();
                break;
        }
    }

    private void getUsbDevices(Result result) {
        executor.execute(() -> {
            try {
                List<String> devicePaths = POSConnect.getUsbDevices(context);
                
                List<Map<String, Object>> devices = new ArrayList<>();
                UsbManager usbManager = (UsbManager) context.getSystemService(Context.USB_SERVICE);
                
                if (usbManager != null) {
                    for (UsbDevice device : usbManager.getDeviceList().values()) {
                        Map<String, Object> deviceInfo = new HashMap<>();
                        deviceInfo.put("deviceName", device.getDeviceName());
                        deviceInfo.put("vendorId", device.getVendorId());
                        deviceInfo.put("productId", device.getProductId());
                        deviceInfo.put("manufacturerName", device.getManufacturerName());
                        deviceInfo.put("productName", device.getProductName());
                        devices.add(deviceInfo);
                    }
                }

                mainHandler.post(() -> result.success(devices));
            } catch (Exception e) {
                Log.e(TAG, "Error getting USB devices", e);
                mainHandler.post(() -> result.error("GET_USB_DEVICES_ERROR", e.getMessage(), null));
            }
        });
    }

    private void connectUsb(String devicePath, Result result) {
        executor.execute(() -> {
            try {
                // Disconnect any existing connection
                if (usbConnection != null) {
                    usbConnection.close();
                    usbConnection = null;
                    posPrinter = null;
                }

                // Create USB connection
                usbConnection = POSConnect.createDevice(POSConnect.DEVICE_TYPE_USB);
                
                // Connect synchronously
                boolean connected = usbConnection.connectSync(devicePath, (code, connectInfo, message) -> {
                    Log.d(TAG, "USB Connection callback - Code: " + code + ", Info: " + connectInfo + ", Message: " + message);
                });

                if (connected) {
                    posPrinter = new POSPrinter(usbConnection);
                    Log.d(TAG, "USB printer connected successfully");
                    mainHandler.post(() -> result.success(true));
                } else {
                    Log.e(TAG, "Failed to connect USB printer");
                    mainHandler.post(() -> result.success(false));
                }
            } catch (Exception e) {
                Log.e(TAG, "Error connecting USB printer", e);
                mainHandler.post(() -> result.error("USB_CONNECT_ERROR", e.getMessage(), null));
            }
        });
    }

    private void disconnect(Result result) {
        executor.execute(() -> {
            try {
                if (usbConnection != null) {
                    usbConnection.closeSync();
                    usbConnection = null;
                    posPrinter = null;
                    Log.d(TAG, "USB printer disconnected");
                }
                mainHandler.post(() -> result.success(true));
            } catch (Exception e) {
                Log.e(TAG, "Error disconnecting printer", e);
                mainHandler.post(() -> result.error("DISCONNECT_ERROR", e.getMessage(), null));
            }
        });
    }

    private void printReceipt(String receiptData, Result result) {
        executor.execute(() -> {
            try {
                if (posPrinter == null) {
                    mainHandler.post(() -> result.error("NOT_CONNECTED", "Printer not connected", null));
                    return;
                }

                Log.d(TAG, "Starting receipt print with proper CP437 encoding for pound signs");

                // Initialize printer with CP437 character set
                posPrinter.initializePrinter();
                
                // CRITICAL FIX: Proper pound sign handling for Xprinter
                String processedReceipt = fixPoundSignEncoding(receiptData);
                
                // Initialize printer for CP437 character set (critical for pound sign)
                String initCommands = "";
                initCommands += (char) 0x1B + (char) 0x40; // ESC @ (Initialize/Reset printer)
                initCommands += (char) 0x1B + (char) 0x74 + (char) 0x00; // ESC t 0 (Select CP437 - Page 0)
                initCommands += (char) 0x1C + (char) 0x2E; // FS . (Cancel Chinese mode)
                initCommands += (char) 0x1B + (char) 0x52 + (char) 0x00; // ESC R 0 (International charset)

                // CRITICAL: Clear any stored header/business info that might be auto-printing
                initCommands += (char) 0x1B + (char) 0x45 + (char) 0x00; // ESC E 0 (Cancel emphasized mode)
                initCommands += (char) 0x1B + (char) 0x21 + (char) 0x00; // ESC ! 0 (Reset all text attributes)
                initCommands += (char) 0x1D + (char) 0x49 + (char) 0x00; // GS I 0 (Clear stored graphics)
                initCommands += (char) 0x1D + (char) 0x42 + (char) 0x00; // GS B 0 (Cancel white/black reverse)

                // Force clear any auto-header settings
                initCommands += (char) 0x1B + (char) 0x25 + (char) 0x00; // ESC % 0 (Cancel user-defined chars)
                initCommands += (char) 0x1F + (char) 0x11; // US DC1 (Cancel stored settings)
                
                // Print initialization commands first
                posPrinter.printString(initCommands);
                
                // Print the receipt content with fixed pound signs
                posPrinter.printString(processedReceipt);
                
                // Feed and cut
                posPrinter.feedLine(3).cutPaper();

                Log.d(TAG, "Receipt printed successfully with CP437 pound sign encoding");
                mainHandler.post(() -> result.success(true));
                
            } catch (Exception e) {
                Log.e(TAG, "Error printing receipt", e);
                
                // Fallback: Try without encoding fixes
                try {
                    Log.d(TAG, "Attempting fallback print without encoding fixes...");
                    posPrinter.initializePrinter()
                             .printString(receiptData)
                             .feedLine(3)
                             .cutPaper();
                    Log.d(TAG, "Fallback print successful");
                    mainHandler.post(() -> result.success(true));
                } catch (Exception fallbackException) {
                    Log.e(TAG, "Both main and fallback print methods failed", fallbackException);
                    mainHandler.post(() -> result.error("PRINT_ERROR", e.getMessage(), null));
                }
            }
        });
    }

    /**
     * Fix pound sign encoding for proper display on Xprinter thermal printers
     * Converts Unicode £ to CP437 character code 156 (0x9C)
     */
    private String fixPoundSignEncoding(String input) {
        if (input == null || !input.contains("£")) {
            return input;
        }

        Log.d(TAG, "POUND SIGN FIX: Processing " + countPoundSigns(input) + " pound signs");
        
        try {
            // Method 1: Direct character replacement with CP437 code
            // In CP437, pound sign is at position 156 (0x9C)
            String result = input.replace("£", String.valueOf((char) 0x9C));
            
            Log.d(TAG, "POUND SIGN FIX: Applied direct CP437 character code replacement");
            return result;
            
        } catch (Exception e) {
            Log.w(TAG, "POUND SIGN FIX: Direct replacement failed, trying byte-level fix", e);
            
            try {
                // Method 2: Byte-level replacement for UTF-8 encoded pound signs
                byte[] bytes = input.getBytes("UTF-8");
                List<Byte> fixedBytes = new ArrayList<>();
                
                for (int i = 0; i < bytes.length; i++) {
                    // Check for UTF-8 pound sign sequence (0xC2 0xA3)
                    if (i < bytes.length - 1 && 
                        (bytes[i] & 0xFF) == 0xC2 && 
                        (bytes[i + 1] & 0xFF) == 0xA3) {
                        
                        // Replace UTF-8 pound sign with CP437 pound sign
                        fixedBytes.add((byte) 0x9C);
                        i++; // Skip the next byte as we've processed the pair
                        Log.d(TAG, "POUND SIGN FIX: Replaced UTF-8 sequence (C2 A3) with CP437 (9C)");
                        
                    } else if ((bytes[i] & 0xFF) == 0xA3) {
                        // Handle Latin-1 pound sign (0xA3) -> CP437 (0x9C)
                        fixedBytes.add((byte) 0x9C);
                        Log.d(TAG, "POUND SIGN FIX: Replaced Latin-1 (A3) with CP437 (9C)");
                        
                    } else {
                        fixedBytes.add(bytes[i]);
                    }
                }
                
                // Convert back to string using Latin-1 to preserve byte values
                byte[] resultBytes = new byte[fixedBytes.size()];
                for (int i = 0; i < fixedBytes.size(); i++) {
                    resultBytes[i] = fixedBytes.get(i);
                }
                
                String result = new String(resultBytes, "ISO-8859-1");
                Log.d(TAG, "POUND SIGN FIX: Applied byte-level replacement successfully");
                return result;
                
            } catch (Exception byteException) {
                Log.e(TAG, "POUND SIGN FIX: All methods failed, using original string", byteException);
                return input;
            }
        }
    }
    
    /**
     * Count pound signs in string for debugging
     */
    private int countPoundSigns(String input) {
        int count = 0;
        for (char c : input.toCharArray()) {
            if (c == '£') count++;
        }
        return count;
    }

    private void openCashBox(Integer pinNum, Integer onTime, Integer offTime, Result result) {
        executor.execute(() -> {
            try {
                if (posPrinter == null) {
                    mainHandler.post(() -> result.error("NOT_CONNECTED", "Printer not connected", null));
                    return;
                }

                int pin = pinNum != null ? pinNum : 0;    // PIN_TWO by default
                int on = onTime != null ? onTime : 30;    // Default onTime
                int off = offTime != null ? offTime : 255; // Default offTime

                posPrinter.openCashBox(pin, on, off);
                Log.d(TAG, "Cash box opened");
                mainHandler.post(() -> result.success(true));
            } catch (Exception e) {
                Log.e(TAG, "Error opening cash box", e);
                mainHandler.post(() -> result.error("CASH_BOX_ERROR", e.getMessage(), null));
            }
        });
    }

    private void printerStatus(Result result) {
        executor.execute(() -> {
            try {
                if (usbConnection == null) {
                    mainHandler.post(() -> result.error("NOT_CONNECTED", "Printer not connected", null));
                    return;
                }

                // Use a simpler approach - just check if connection object exists and is not null
                Map<String, Object> statusInfo = new HashMap<>();
                statusInfo.put("connected", usbConnection != null);
                statusInfo.put("statusCode", usbConnection != null ? 1 : 0);
                mainHandler.post(() -> result.success(statusInfo));
            } catch (Exception e) {
                Log.e(TAG, "Error checking printer status", e);
                mainHandler.post(() -> result.error("STATUS_ERROR", e.getMessage(), null));
            }
        });
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        
        // Clean up resources
        if (executor != null) {
            executor.shutdown();
        }
        
        if (usbConnection != null) {
            try {
                usbConnection.close();
            } catch (Exception e) {
                Log.e(TAG, "Error closing connection on detach", e);
            }
        }
        
        POSConnect.exit();
        Log.d(TAG, "Xprinter SDK plugin detached");
    }
}