// lib/main_app_wrapper.dart

import 'package:flutter/material.dart';
import 'package:epos/services/order_api_service.dart';
import 'package:epos/services/thermal_printer_service.dart';
import 'package:epos/models/order.dart';
import 'package:epos/models/cart_item.dart';
import 'package:epos/models/food_item.dart';
import 'package:epos/new_order_notification_widget.dart';
import 'package:epos/cancelled_order_notification_widget.dart';
import 'package:epos/providers/website_orders_provider.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:ui';
import 'package:epos/services/custom_popup_service.dart';
import 'package:epos/main.dart';

class MainAppWrapper extends StatefulWidget {
  final Widget child;

  const MainAppWrapper({super.key, required this.child});

  @override
  State<MainAppWrapper> createState() => _MainAppWrapperState();
}

class _MainAppWrapperState extends State<MainAppWrapper> {
  late OrderApiService _orderApiService;
  StreamSubscription<Order>? _newOrderSubscription;

  final List<Order> _activeNewOrderNotifications = [];
  final List<Order> _activeCancelledOrderNotifications = [];

  // Change this line:
  final Set<int> _processingOrderIds =
      {}; // Changed from Set<String> to Set<int>

  // Track previous order statuses to detect cancellations
  Map<int, String> _previousOrderStatuses = {};

  @override
  void initState() {
    super.initState();
    _orderApiService = OrderApiService();

    _newOrderSubscription = _orderApiService.newOrderStream.listen((newOrder) {
      print(
        "MainAppWrapper: New order received from socket: ${newOrder.orderId}",
      );

      // Brand filtering is now handled at the socket level in OrderApiService

      if ((newOrder.status.toLowerCase() == 'pending' ||
              newOrder.status.toLowerCase() == 'yellow') &&
          !_processingOrderIds.contains(newOrder.orderId)) {
        print(
          "MainAppWrapper: Adding new order notification for current brand order ${newOrder.orderId}",
        );
        _addNewOrderNotification(newOrder);
      }
    });

    _orderApiService.connectionStatusStream.listen((isConnected) {
      print("MainAppWrapper: Socket connection status: $isConnected");
    });

    // Initialize previous order statuses after frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializePreviousOrderStatuses();
    });
  }

  void _initializePreviousOrderStatuses() {
    if (!mounted) return;

    try {
      final orderProvider = Provider.of<OrderProvider>(context, listen: false);

      for (var order in orderProvider.websiteOrders) {
        final status = order.status.toLowerCase();
        _previousOrderStatuses[order.orderId] = status;
        print(
          "MainAppWrapper: Initialized order ${order.orderId} with status '$status'",
        );
      }
      print(
        "MainAppWrapper: Initialized ${_previousOrderStatuses.length} order statuses",
      );
    } catch (e) {
      print("MainAppWrapper: Error initializing order statuses: $e");
    }
  }

  void _addNewOrderNotification(Order order) {
    setState(() {
      _activeNewOrderNotifications.add(order);
      _processingOrderIds.add(order.orderId); // This line will now work
      print(
        "MainAppWrapper: New order notification added for order ${order.orderId}. Total active notifications: ${_activeNewOrderNotifications.length}",
      );
    });
  }

  void _removeNewOrderNotification(Order order) {
    setState(() {
      _activeNewOrderNotifications.removeWhere(
        (o) => o.orderId == order.orderId,
      );
      _processingOrderIds.remove(order.orderId); // This line will now work
      print(
        "MainAppWrapper: Notification for order ${order.orderId} removed. Remaining active notifications: ${_activeNewOrderNotifications.length}",
      );
    });
  }

  void _addCancelledOrderNotification(Order order) {
    setState(() {
      _activeCancelledOrderNotifications.add(order);
      print(
        "MainAppWrapper: Cancelled order notification added for order ${order.orderId}. Total cancelled notifications: ${_activeCancelledOrderNotifications.length}",
      );
    });
  }

  void _removeCancelledOrderNotification(Order order) {
    setState(() {
      _activeCancelledOrderNotifications.removeWhere(
        (o) => o.orderId == order.orderId,
      );
      print(
        "MainAppWrapper: Cancelled notification for order ${order.orderId} removed. Remaining cancelled notifications: ${_activeCancelledOrderNotifications.length}",
      );
    });
  }

  void _checkForCancelledOrders(List<Order> currentOrders) {
    // Brand filtering is now handled at the API/socket level, so all orders should be for current brand
    print(
      "MainAppWrapper: Checking ${currentOrders.length} orders for cancellations (brand filtering done at socket level)",
    );

    for (var order in currentOrders) {
      final currentStatus = order.status.toLowerCase();
      final previousStatus = _previousOrderStatuses[order.orderId];

      print(
        "MainAppWrapper: Order ${order.orderId} - Current: '$currentStatus', Previous: '$previousStatus'",
      );

      // Check if order status changed to cancelled
      if ((currentStatus == 'cancelled' || currentStatus == 'red') &&
          previousStatus != null &&
          previousStatus != 'cancelled' &&
          previousStatus != 'red') {
        print(
          "MainAppWrapper: Order ${order.orderId} detected as newly cancelled!",
        );

        // Add to cancelled notifications if not already present
        if (!_activeCancelledOrderNotifications.any(
          (o) => o.orderId == order.orderId,
        )) {
          print(
            "MainAppWrapper: Adding cancelled notification for order ${order.orderId}",
          );
          _addCancelledOrderNotification(order);
        } else {
          print(
            "MainAppWrapper: Cancelled notification for order ${order.orderId} already exists",
          );
        }
      }

      // Update previous status
      _previousOrderStatuses[order.orderId] = currentStatus;
    }

    print(
      "MainAppWrapper: Active cancelled notifications: ${_activeCancelledOrderNotifications.length}",
    );
  }

  void _showMainWrapperPopup(
    String message, {
    PopupType type = PopupType.failure,
  }) {
    try {
      final scaffoldMessenger = scaffoldMessengerKey.currentState;
      if (scaffoldMessenger == null) {
        print('MainAppWrapper: ScaffoldMessenger not available - $message');
        return;
      }

      // Clear any existing snackbars
      scaffoldMessenger.clearSnackBars();

      Color backgroundColor;
      IconData iconData;

      if (type == PopupType.success) {
        backgroundColor = Colors.green[700]!;
        iconData = Icons.check_circle_outline;
      } else {
        backgroundColor = Colors.red[700]!;
        iconData = Icons.error_outline;
      }

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(iconData, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: backgroundColor,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );

      print('MainAppWrapper: Popup shown via SnackBar - $message');
    } catch (e) {
      print('MainAppWrapper: Error showing popup - $message: $e');
    }
  }

  // Convert Order items to CartItem format for the printer service
  List<CartItem> _convertOrderToCartItems(Order order) {
    return order.items.map((orderItem) {
      // Calculate price per unit from total price and quantity
      double pricePerUnit =
          orderItem.quantity > 0
              ? (orderItem.totalPrice / orderItem.quantity)
              : 0.0;

      // Extract options from description for proper printing
      Map<String, dynamic> itemOptions = _extractAllOptionsFromDescription(
        orderItem.description,
        defaultFoodItemToppings: orderItem.foodItem?.defaultToppings,
        defaultFoodItemCheese: orderItem.foodItem?.defaultCheese,
      );

      // Build selectedOptions list for receipt printing
      List<String> selectedOptions = [];

      if (itemOptions['hasOptions'] == true) {
        if (itemOptions['size'] != null) {
          selectedOptions.add('Size: ${itemOptions['size']}');
        }
        if (itemOptions['crust'] != null) {
          selectedOptions.add('Crust: ${itemOptions['crust']}');
        }
        if (itemOptions['base'] != null) {
          selectedOptions.add('Base: ${itemOptions['base']}');
        }
        if (itemOptions['toppings'] != null &&
            (itemOptions['toppings'] as List).isNotEmpty) {
          selectedOptions.add(
            'Extra Toppings: ${(itemOptions['toppings'] as List<String>).join(', ')}',
          );
        }
        if (itemOptions['sauceDips'] != null &&
            (itemOptions['sauceDips'] as List).isNotEmpty) {
          selectedOptions.add(
            'Sauce Dips: ${(itemOptions['sauceDips'] as List<String>).join(', ')}',
          );
        }
        if (itemOptions['isMeal'] == true) {
          selectedOptions.add('MEAL');
        }
        if (itemOptions['drink'] != null) {
          selectedOptions.add('Drink: ${itemOptions['drink']}');
        }
      }

      // Get comment from either regular comment field or extracted from description
      String? finalComment = orderItem.comment;
      if (finalComment == null || finalComment.isEmpty) {
        finalComment = itemOptions['extractedComment'] as String?;
      }

      return CartItem(
        foodItem:
            orderItem.foodItem ??
            FoodItem(
              id: orderItem.itemId ?? 0,
              name: orderItem.itemName,
              category: orderItem.itemType,
              price: {'default': pricePerUnit},
              image: orderItem.imageUrl ?? '',
              availability: true,
            ),
        quantity: orderItem.quantity,
        selectedOptions: selectedOptions.isNotEmpty ? selectedOptions : null,
        comment: finalComment,
        pricePerUnit: pricePerUnit,
      );
    }).toList();
  }

  // Extract options from item description for detailed receipt printing
  Map<String, dynamic> _extractAllOptionsFromDescription(
    String description, {
    List<String>? defaultFoodItemToppings,
    List<String>? defaultFoodItemCheese,
  }) {
    Map<String, dynamic> options = {
      'size': null,
      'crust': null,
      'base': null,
      'drink': null,
      'isMeal': false,
      'toppings': <String>[],
      'sauceDips': <String>[],
      'baseItemName': description,
      'hasOptions': false,
      'extractedComment': null,
    };

    List<String> optionsList = [];
    bool foundOptionsSyntax = false;
    bool anyNonDefaultOptionFound = false;

    // Check if it's parentheses format (EPOS): "Item Name (Size: Large, Crust: Thin)"
    final optionMatch = RegExp(r'\((.*?)\)').firstMatch(description);
    if (optionMatch != null && optionMatch.group(1) != null) {
      // EPOS format with parentheses
      String optionsString = optionMatch.group(1)!;
      foundOptionsSyntax = true;
      optionsList = _smartSplitOptions(optionsString);
    } else if (description.contains('\n') || description.contains(':')) {
      // Website format with newlines: "Size: 7 inch\nBase: Tomato\nCrust: Normal"
      List<String> lines =
          description
              .split('\n')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();

      // Check if any line contains options (has colons)
      List<String> optionLines =
          lines.where((line) => line.contains(':')).toList();

      if (optionLines.isNotEmpty) {
        foundOptionsSyntax = true;
        optionsList = optionLines;

        // Find the first line that doesn't contain a colon (likely the item name)
        String foundItemName = '';
        for (var line in lines) {
          if (!line.contains(':')) {
            foundItemName = line;
            break;
          }
        }

        if (foundItemName.isNotEmpty) {
          options['baseItemName'] = foundItemName;
        } else {
          options['baseItemName'] = description; // Fallback to full description
        }
      }
    }

    // If no options syntax found, it's a simple description like "Chocolate Milkshake"
    if (!foundOptionsSyntax) {
      options['baseItemName'] = description;
      options['hasOptions'] = false;
      return options;
    }

    // Combine default toppings and cheese from the FoodItem
    final Set<String> defaultToppingsAndCheese = {};
    if (defaultFoodItemToppings != null) {
      defaultToppingsAndCheese.addAll(
        defaultFoodItemToppings.map((t) => t.trim().toLowerCase()),
      );
    }
    if (defaultFoodItemCheese != null) {
      defaultToppingsAndCheese.addAll(
        defaultFoodItemCheese.map((c) => c.trim().toLowerCase()),
      );
    }

    // Process the options and apply filtering for default values
    for (var option in optionsList) {
      String lowerOption = option.toLowerCase();

      // Enhanced meal detection
      if (lowerOption.contains('make it a meal') ||
          lowerOption.contains('meal') ||
          lowerOption.contains('with drink') ||
          lowerOption.contains('+ drink')) {
        options['isMeal'] = true;
        anyNonDefaultOptionFound = true;
      }
      // Enhanced drink extraction - handle multiple formats
      else if (lowerOption.startsWith('drink:') ||
          lowerOption.contains('drink:') ||
          lowerOption.startsWith('beverage:') ||
          lowerOption.contains('beverage:')) {
        String drinkValue;
        if (lowerOption.contains('drink:')) {
          drinkValue =
              option
                  .substring(
                    option.toLowerCase().indexOf('drink:') + 'drink:'.length,
                  )
                  .trim();
        } else if (lowerOption.contains('beverage:')) {
          drinkValue =
              option
                  .substring(
                    option.toLowerCase().indexOf('beverage:') +
                        'beverage:'.length,
                  )
                  .trim();
        } else {
          drinkValue = option.trim();
        }

        if (drinkValue.isNotEmpty) {
          options['drink'] = drinkValue;
          options['isMeal'] = true; // If there's a drink, it's likely a meal
          anyNonDefaultOptionFound = true;
        }
      } else if (lowerOption.startsWith('size:')) {
        String sizeValue = option.substring('size:'.length).trim();
        if (sizeValue.isNotEmpty) {
          options['size'] = sizeValue;
          // Only mark as non-default if it's actually not a standard default value
          if (sizeValue.toLowerCase() != 'default' &&
              sizeValue.toLowerCase() != 'regular') {
            anyNonDefaultOptionFound = true;
          }
        }
      } else if (lowerOption.startsWith('crust:')) {
        String crustValue = option.substring('crust:'.length).trim();
        if (crustValue.isNotEmpty) {
          options['crust'] = crustValue;
          // Only mark as non-default if it's actually not a standard default value
          if (crustValue.toLowerCase() != 'normal' &&
              crustValue.toLowerCase() != 'standard') {
            anyNonDefaultOptionFound = true;
          }
        }
      } else if (lowerOption.startsWith('base:')) {
        String baseValue = option.substring('base:'.length).trim();
        if (baseValue.isNotEmpty) {
          if (baseValue.contains(',')) {
            List<String> baseList =
                baseValue.split(',').map((b) => b.trim()).toList();
            options['base'] = baseList.join(', ');
          } else {
            options['base'] = baseValue;
          }
          // Only mark as non-default if it's actually not a standard default value
          if (baseValue.toLowerCase() != 'tomato' &&
              baseValue.toLowerCase() != 'standard') {
            anyNonDefaultOptionFound = true;
          }
        }
      } else if (lowerOption.startsWith('toppings:') ||
          lowerOption.startsWith('extra toppings:')) {
        String prefix =
            lowerOption.startsWith('extra toppings:')
                ? 'extra toppings:'
                : 'toppings:';
        String toppingsValue = option.substring(prefix.length).trim();

        if (toppingsValue.isNotEmpty) {
          List<String> currentToppingsFromDescription =
              toppingsValue
                  .split(',')
                  .map((t) => t.trim())
                  .where((t) => t.isNotEmpty)
                  .toList();

          // Filter against FoodItem's default toppings/cheese
          // Only filter if we have FoodItem data, otherwise show all toppings
          List<String> filteredToppings =
              currentToppingsFromDescription.where((topping) {
                String trimmedToppingLower = topping.trim().toLowerCase();
                // Always filter out clearly non-meaningful values
                if ([
                  'none',
                  'no toppings',
                  'standard',
                  'default',
                ].contains(trimmedToppingLower)) {
                  return false;
                }
                // Only filter against default toppings if we have FoodItem data
                if (defaultFoodItemToppings != null ||
                    defaultFoodItemCheese != null) {
                  return !defaultToppingsAndCheese.contains(
                    trimmedToppingLower,
                  );
                }
                // If no FoodItem data, show all toppings (don't filter)
                return true;
              }).toList();

          if (filteredToppings.isNotEmpty) {
            List<String> existingToppings = List<String>.from(
              options['toppings'],
            );
            existingToppings.addAll(filteredToppings);
            options['toppings'] = existingToppings.toSet().toList();
            anyNonDefaultOptionFound = true;
          }
        }
      } else if (lowerOption.startsWith('sauce dips:') ||
          lowerOption.startsWith('dips:') ||
          lowerOption.startsWith('sauce:') ||
          lowerOption.contains('dip:')) {
        String sauceDipsValue = '';
        if (lowerOption.startsWith('sauce dips:')) {
          sauceDipsValue = option.substring('sauce dips:'.length).trim();
        } else if (lowerOption.startsWith('dips:')) {
          sauceDipsValue = option.substring('dips:'.length).trim();
        } else if (lowerOption.startsWith('sauce:')) {
          sauceDipsValue = option.substring('sauce:'.length).trim();
        } else if (lowerOption.contains('dip:')) {
          int dipIndex = lowerOption.indexOf('dip:');
          sauceDipsValue = option.substring(dipIndex + 'dip:'.length).trim();
        }

        if (sauceDipsValue.isNotEmpty) {
          List<String> sauceDipsList =
              sauceDipsValue
                  .split(',')
                  .map((t) => t.trim())
                  .where((t) => t.isNotEmpty)
                  .toList();
          List<String> currentSauceDips = List<String>.from(
            options['sauceDips'],
          );
          currentSauceDips.addAll(sauceDipsList);
          options['sauceDips'] = currentSauceDips.toSet().toList();
          anyNonDefaultOptionFound = true;
        }
      } else if (lowerOption.startsWith('comment:') ||
          lowerOption.startsWith('note:') ||
          lowerOption.startsWith('notes:') ||
          lowerOption.startsWith('special instructions:')) {
        String commentValue = '';
        if (lowerOption.startsWith('comment:')) {
          commentValue = option.substring('comment:'.length).trim();
        } else if (lowerOption.startsWith('note:')) {
          commentValue = option.substring('note:'.length).trim();
        } else if (lowerOption.startsWith('notes:')) {
          commentValue = option.substring('notes:'.length).trim();
        } else if (lowerOption.startsWith('special instructions:')) {
          commentValue =
              option.substring('special instructions:'.length).trim();
        }

        if (commentValue.isNotEmpty) {
          options['extractedComment'] = commentValue;
          anyNonDefaultOptionFound = true;
        }
      } else if (lowerOption == 'no salad' ||
          lowerOption == 'no sauce' ||
          lowerOption == 'no cream') {
        List<String> currentToppings = List<String>.from(options['toppings']);
        currentToppings.add(option);
        options['toppings'] = currentToppings.toSet().toList();
        anyNonDefaultOptionFound = true;
      }
      // Additional pattern matching for drinks mentioned without prefix
      else if (lowerOption.contains('coke') ||
          lowerOption.contains('pepsi') ||
          lowerOption.contains('fanta') ||
          lowerOption.contains('sprite') ||
          lowerOption.contains('milkshake') ||
          lowerOption.contains('juice') ||
          (lowerOption.contains('can') &&
              (lowerOption.contains('drink') || lowerOption.length < 20))) {
        if (options['drink'] == null) {
          options['drink'] = option.trim();
          options['isMeal'] = true;
          anyNonDefaultOptionFound = true;
        }
      }
    }

    // Additional meal detection based on item names and common patterns
    String baseItemName = options['baseItemName'].toString().toLowerCase();
    if (!options['isMeal'] &&
        (baseItemName.contains('burger') &&
            (description.toLowerCase().contains('coke') ||
                description.toLowerCase().contains('pepsi') ||
                description.toLowerCase().contains('fanta') ||
                description.toLowerCase().contains('sprite') ||
                description.toLowerCase().contains('drink') ||
                description.toLowerCase().contains('beverage') ||
                optionsList.any(
                  (opt) =>
                      opt.toLowerCase().contains('drink') ||
                      opt.toLowerCase().contains('beverage') ||
                      opt.toLowerCase().contains('coke') ||
                      opt.toLowerCase().contains('pepsi'),
                )))) {
      options['isMeal'] = true;
      anyNonDefaultOptionFound = true;

      // Try to extract drink from description if not already found
      if (options['drink'] == null) {
        for (var option in optionsList) {
          String lowerOpt = option.toLowerCase();
          if (lowerOpt.contains('coke') ||
              lowerOpt.contains('pepsi') ||
              lowerOpt.contains('fanta') ||
              lowerOpt.contains('sprite')) {
            options['drink'] = option.trim();
            break;
          }
        }
      }
    }

    // Set hasOptions to true if we found any structured data (not just non-default)
    // This ensures that even if all options are "default", we still parse and display them properly
    options['hasOptions'] =
        foundOptionsSyntax &&
        (options['size'] != null ||
            options['crust'] != null ||
            options['base'] != null ||
            options['drink'] != null ||
            options['isMeal'] == true ||
            (options['toppings'] as List).isNotEmpty ||
            (options['sauceDips'] as List).isNotEmpty ||
            anyNonDefaultOptionFound);
    return options;
  }

  // Helper method for EPOS format (parentheses) smart splitting
  List<String> _smartSplitOptions(String optionsString) {
    List<String> result = [];
    String current = '';
    bool inToppings = false;
    bool inSauceDips = false;

    List<String> parts = optionsString.split(', ');

    for (int i = 0; i < parts.length; i++) {
      String part = parts[i];
      String lowerPart = part.toLowerCase();

      if (lowerPart.startsWith('toppings:') ||
          lowerPart.startsWith('extra toppings:')) {
        if (current.isNotEmpty) {
          result.add(current.trim());
          current = '';
        }
        current = part;
        inToppings = true;
        inSauceDips = false;
      } else if (lowerPart.startsWith('sauce dips:') ||
          lowerPart.startsWith('dips:') ||
          lowerPart.startsWith('sauce:') ||
          lowerPart.contains('dip:')) {
        if (current.isNotEmpty) {
          result.add(current.trim());
          current = '';
        }
        current = part;
        inToppings = false;
        inSauceDips = true;
      } else if (lowerPart.startsWith('size:') ||
          lowerPart.startsWith('base:') ||
          lowerPart.startsWith('crust:') ||
          lowerPart.startsWith('drink:') ||
          lowerPart.startsWith('beverage:')) {
        if (current.isNotEmpty) {
          result.add(current.trim());
          current = '';
        }
        current = part;
        inToppings = false;
        inSauceDips = false;
      } else {
        if (inToppings || inSauceDips) {
          current += ', ' + part;
        } else {
          if (current.isNotEmpty) {
            result.add(current.trim());
          }
          current = part;
        }
      }
    }

    if (current.isNotEmpty) {
      result.add(current.trim());
    }

    return result;
  }

  Future<void> _printOrderReceipt(Order order) async {
    try {
      print(
        "MainAppWrapper: Starting to print receipt for order ${order.orderId}",
      );

      // Convert Order items to CartItem format
      List<CartItem> cartItems = _convertOrderToCartItems(order);

      // Calculate subtotal
      double subtotal = order.orderTotalPrice;

      // Use the thermal printer service to print
      bool
      success = await ThermalPrinterService().printReceiptWithUserInteraction(
        transactionId: order.orderId.toString(),
        orderType: order.orderType,
        cartItems: cartItems,
        subtotal: subtotal,
        totalCharge: order.orderTotalPrice,
        changeDue: order.changeDue,
        extraNotes: order.orderExtraNotes,
        customerName: order.customerName,
        customerEmail: order.customerEmail,
        phoneNumber: order.phoneNumber,
        streetAddress: order.streetAddress,
        city: order.city,
        postalCode: order.postalCode,
        paymentType: order.paymentType,
        onShowMethodSelection: (availableMethods) {
          _showMainWrapperPopup(
            "Available printing methods: ${availableMethods.join(', ')}. Please check printer connections.",
            type: PopupType.success,
          );
        },
      );

      if (success) {
        print(
          "MainAppWrapper: Receipt printed successfully for order ${order.orderId}",
        );
        _showMainWrapperPopup(
          'Receipt printed for order ${order.orderId}',
          type: PopupType.success,
        );
      } else {
        print(
          "MainAppWrapper: Failed to print receipt for order ${order.orderId}",
        );
        _showMainWrapperPopup(
          'Failed to print receipt for order ${order.orderId}. Please check printer connection.',
          type: PopupType.failure,
        );
      }
    } catch (e) {
      print(
        'MainAppWrapper: Error printing receipt for order ${order.orderId}: $e',
      );
      _showMainWrapperPopup(
        'Error printing receipt for order ${order.orderId}: $e',
        type: PopupType.failure,
      );
    }
  }

  Future<void> _handleAcceptOrder(Order order) async {
    print("MainAppWrapper: Accepting order ${order.orderId}");

    try {
      // First update the order status
      bool success = await OrderApiService.updateOrderStatus(
        order.orderId,
        'yellow',
      );

      if (success) {
        print("MainAppWrapper: Order ${order.orderId} accepted successfully");

        // Show success popup
        _showMainWrapperPopup(
          'Order ${order.orderId} accepted.',
          type: PopupType.success,
        );

        // Remove from processing set (but don't remove notification - widget will do that)
        _processingOrderIds.remove(order.orderId);

        // Print the receipt automatically after successful acceptance
        await Future.delayed(const Duration(milliseconds: 500));
        await _printOrderReceipt(order);

        // Refresh the orders
        if (mounted && context.mounted) {
          Provider.of<OrderProvider>(
            context,
            listen: false,
          ).fetchWebsiteOrders();
        }
      } else {
        print("MainAppWrapper: Failed to accept order ${order.orderId}");
        _showMainWrapperPopup(
          'Failed to accept order ${order.orderId}. Please try again.',
          type: PopupType.failure,
        );
        // Throw error so widget knows to reset processing state
        throw Exception('Failed to accept order');
      }
    } catch (e) {
      print('MainAppWrapper: Error in _handleAcceptOrder: $e');
      _showMainWrapperPopup(
        'Error accepting order ${order.orderId}. Please try again.',
        type: PopupType.failure,
      );
      // Re-throw so widget knows there was an error
      rethrow;
    }
  }

  Future<void> _handleDeclineOrder(Order order) async {
    print("MainAppWrapper: Declining order ${order.orderId}");

    // Add a small delay to prevent double-clicking
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      bool success = await OrderApiService.updateOrderStatus(
        order.orderId,
        'declined',
      );

      if (success) {
        print("MainAppWrapper: Order ${order.orderId} declined successfully");

        // Remove notification immediately after successful API call
        _removeNewOrderNotification(order);

        _showMainWrapperPopup(
          'Order ${order.orderId} declined.',
          type: PopupType.success,
        );
      } else {
        print("MainAppWrapper: Failed to decline order ${order.orderId}");
        _showMainWrapperPopup(
          'Failed to decline order ${order.orderId}. Please try again.',
          type: PopupType.failure,
        );
        // Don't remove notification - let user try again
      }
    } catch (e) {
      print('MainAppWrapper: Error in _handleDeclineOrder: $e');
      _showMainWrapperPopup(
        'Error declining order ${order.orderId}. Please try again.',
        type: PopupType.failure,
      );
      // Don't remove notification - let user try again
    }
  }

  @override
  void dispose() {
    _newOrderSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Consumer<OrderProvider>(
        builder: (context, orderProvider, child) {
          // Check for cancelled orders whenever the provider updates
          _checkForCancelledOrders(orderProvider.websiteOrders);

          print(
            "MainAppWrapper: Building with ${_activeNewOrderNotifications.length} new and ${_activeCancelledOrderNotifications.length} cancelled notifications",
          );

          return Stack(
            children: [
              widget.child,

              // Backdrop filter for any notifications
              if (_activeNewOrderNotifications.isNotEmpty ||
                  _activeCancelledOrderNotifications.isNotEmpty)
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
                    child: Container(color: Colors.black.withOpacity(0.3)),
                  ),
                ),

              // New order notifications
              ..._activeNewOrderNotifications.map((order) {
                return NewOrderNotificationWidget(
                  key: ValueKey('new_${order.orderId}'),
                  order: order,
                  onAccept: _handleAcceptOrder,
                  onDecline: _handleDeclineOrder,
                  onDismiss: () => _removeNewOrderNotification(order),
                );
              }).toList(),

              // Cancelled order notifications
              ..._activeCancelledOrderNotifications.map((order) {
                return CancelledOrderNotificationWidget(
                  key: ValueKey('cancelled_${order.orderId}'),
                  order: order,
                  onDismiss: () => _removeCancelledOrderNotification(order),
                );
              }).toList(),
            ],
          );
        },
      ),
    );
  }
}
