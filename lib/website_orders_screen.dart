// lib/website_orders_screen.dart

import 'dart:async';
import 'package:epos/services/thermal_printer_service.dart';
import 'package:flutter/material.dart';
import 'package:epos/models/order.dart';
import 'package:epos/providers/website_orders_provider.dart';
import 'package:provider/provider.dart';
import 'package:epos/providers/order_counts_provider.dart';
import 'package:epos/custom_bottom_nav_bar.dart';
import 'package:epos/circular_timer_widget.dart';
import 'models/cart_item.dart';
import 'models/food_item.dart';
import 'package:epos/services/uk_time_service.dart';
import 'package:epos/services/custom_popup_service.dart';

extension HexColor on Color {
  static Color fromHex(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }
}

class WebsiteOrdersScreen extends StatefulWidget {
  final int initialBottomNavItemIndex;

  const WebsiteOrdersScreen({super.key, required this.initialBottomNavItemIndex});

  @override
  State<WebsiteOrdersScreen> createState() => _WebsiteOrdersScreenState();
}

class _WebsiteOrdersScreenState extends State<WebsiteOrdersScreen> {
  List<Order> activeOrders = [];
  List<Order> completedOrders = [];
  Order? _selectedOrder;
  late int _selectedBottomNavItem;
  String _selectedOrderType = 'all';
  final ScrollController _scrollController = ScrollController();
  bool _isPrinterConnected = false;
  bool _isCheckingPrinter = false;
  Timer? _printerStatusTimer;

  @override
  void initState() {
    super.initState();
    _selectedBottomNavItem = widget.initialBottomNavItemIndex;
    print("WebsiteOrdersScreen: initState called.");

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final orderProvider = Provider.of<OrderProvider>(context, listen: false);
      _separateOrders(orderProvider.websiteOrders);
      _updateWebsiteOrderCountsInProvider();
      if (!orderProvider.isPolling) {
        orderProvider.startPolling();
      }

      _startPrinterStatusChecking();
    });
  }

  void _startPrinterStatusChecking() {
    _checkPrinterStatus();

    // Create a periodic timer and store the reference
    _printerStatusTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _checkPrinterStatus();
    });
  }

  Future<void> _checkPrinterStatus() async {
    if (_isCheckingPrinter || !mounted) return; // Add mounted check

    setState(() {
      _isCheckingPrinter = true;
    });

    try {
      Map<String, bool> connectionStatus =
      await ThermalPrinterService().checkConnectionStatusOnly();
      bool isConnected =
          connectionStatus['usb'] == true ||
              connectionStatus['bluetooth'] == true;

      if (mounted) {
        // Check mounted before setState
        setState(() {
          _isPrinterConnected = isConnected;
          _isCheckingPrinter = false;
        });
      }
    } catch (e) {
      print('Error checking printer status: $e');
      if (mounted) {
        // Check mounted before setState
        setState(() {
          _isPrinterConnected = false;
          _isCheckingPrinter = false;
        });
      }
    }
  }

  @override
  void dispose() {
    // Cancel the timer before disposing
    _printerStatusTimer?.cancel();

    try {
      Provider.of<OrderProvider>(
        context,
        listen: false,
      ).removeListener(_onOrderProviderChange);
    } catch (e) {
      print("Error removing listener: $e");
    }
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orderProvider = Provider.of<OrderProvider>(context, listen: false);
    try {
      orderProvider.removeListener(_onOrderProviderChange);
    } catch (e) {
      // Listener might not exist yet
    }
    orderProvider.addListener(_onOrderProviderChange);
    // Re-separate orders whenever dependencies change or provider updates
    _separateOrders(orderProvider.websiteOrders);
  }

  void _onOrderProviderChange() {
    print(
      "WebsiteOrdersScreen: OrderProvider data changed, updating UI. Current orders in provider: ${Provider.of<OrderProvider>(context, listen: false).websiteOrders.length}",
    );
    final allWebsiteOrders =
        Provider.of<OrderProvider>(context, listen: false).websiteOrders;
    _separateOrders(allWebsiteOrders);
    _updateWebsiteOrderCountsInProvider(); // Update counts whenever provider changes
  }

  void _updateWebsiteOrderCountsInProvider() {
    final orderCountsProvider = Provider.of<OrderCountsProvider>(
      context,
      listen: false,
    );
    int newWebsiteActiveCount = 0;
    for (var order
    in Provider.of<OrderProvider>(context, listen: false).websiteOrders) {
      if (!(order.status.toLowerCase() == 'completed' ||
          order.status.toLowerCase() == 'delivered' ||
          order.status.toLowerCase() == 'blue' ||
          order.status.toLowerCase() == 'cancelled' ||
          order.status.toLowerCase() == 'red')) {
        newWebsiteActiveCount++;
      }
    }
    orderCountsProvider.setOrderCount('website', newWebsiteActiveCount);
  }

  // Helper method to define status priority for sorting
  int _getStatusPriority(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
      case 'yellow':
      case 'accepted':
        return 1; // Highest priority (shows first)
      case 'ready':
      case 'green':
      case 'preparing':
        return 2; // Second priority
      default:
        return 3; // Lowest priority for other statuses
    }
  }

  Future<void> _handlePrintingOrderReceipt() async {
    if (_selectedOrder == null) {
      CustomPopupService.show(
        context,
        "No order selected for printing",
        type: PopupType.failure,
      );
      return;
    }

    try {
      // Convert Order items to CartItem format for the printer service
      List<CartItem> cartItems =
      _selectedOrder!.items.map((orderItem) {
        // Calculate price per unit from total price and quantity
        double pricePerUnit =
        orderItem.quantity > 0
            ? (orderItem.totalPrice / orderItem.quantity)
            : 0.0;

        // Extract options from description for proper printing
        Map<String, dynamic> itemOptions =
        _extractAllOptionsFromDescription(
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
          selectedOptions:
          selectedOptions.isNotEmpty ? selectedOptions : null,
          comment: orderItem.comment,
          pricePerUnit: pricePerUnit,
        );
      }).toList();

      // Calculate subtotal
      double subtotal = _selectedOrder!.orderTotalPrice;

      // // Show test dialog with receipt content
      // await _showReceiptDialog(_selectedOrder!, cartItems, subtotal);

      // Use the thermal printer service to print
      bool
      success = await ThermalPrinterService().printReceiptWithUserInteraction(
        transactionId:
        _selectedOrder!.transactionId.isNotEmpty
            ? _selectedOrder!.transactionId
            : _selectedOrder!.orderId.toString(),
        orderType: _selectedOrder!.orderType,
        cartItems: cartItems,
        subtotal: subtotal,
        totalCharge: _selectedOrder!.orderTotalPrice,
        changeDue: _selectedOrder!.changeDue,
        extraNotes: _selectedOrder!.orderExtraNotes,
        customerName: _selectedOrder!.customerName,
        customerEmail: _selectedOrder!.customerEmail,
        phoneNumber: _selectedOrder!.phoneNumber,
        streetAddress: _selectedOrder!.streetAddress,
        city: _selectedOrder!.city,
        postalCode: _selectedOrder!.postalCode,
        paymentType: _selectedOrder!.paymentType,
        onShowMethodSelection: (availableMethods) {
          CustomPopupService.show(
            context,
            "Available printing methods: ${availableMethods.join(', ')}. Please check printer connections.",
            type: PopupType.success,
          );
        },
      );

      if (success) {
        CustomPopupService.show(
          context,
          "Receipt printed successfully",
          type: PopupType.success,
        );
      } else {
        CustomPopupService.show(
          context,
          "Failed to print receipt. Check printer connection.",
          type: PopupType.failure,
        );
      }
    } catch (e) {
      print('Error printing receipt: $e');
      CustomPopupService.show(
        context,
        "Error printing Receipt.",
        type: PopupType.failure,
      );
    }
  }

  // Updated _separateOrders method with proper sorting
  void _separateOrders(List<Order> allOrdersFromProvider) {
    setState(() {
      int? selectedOrderId = _selectedOrder?.orderId;

      List<Order> typeFilteredOrders;
      if (_selectedOrderType == 'pickup') {
        typeFilteredOrders =
            allOrdersFromProvider
                .where((order) => order.orderType.toLowerCase() == 'pickup')
                .toList();
      } else if (_selectedOrderType == 'delivery') {
        typeFilteredOrders =
            allOrdersFromProvider
                .where((order) => order.orderType.toLowerCase() == 'delivery')
                .toList();
      } else {
        typeFilteredOrders = List.from(allOrdersFromProvider);
      }

      List<Order> tempActive = [];
      List<Order> tempCompleted = [];

      for (var order in typeFilteredOrders) {
        if (order.status.toLowerCase() == 'completed' ||
            order.status.toLowerCase() == 'delivered' ||
            order.status.toLowerCase() == 'blue' ||
            order.status.toLowerCase() == 'cancelled' ||
            order.status.toLowerCase() == 'red') {
          tempCompleted.add(order);
        } else {
          tempActive.add(order);
        }
      }
      // Sort active orders: Pending first, then others, then by creation time within each group
      tempActive.sort((a, b) {
        int statusPriorityA = _getStatusPriority(a.status);
        int statusPriorityB = _getStatusPriority(b.status);

        if (statusPriorityA != statusPriorityB) {
          return statusPriorityA.compareTo(
            statusPriorityB,
          ); // Lower number = higher priority
        }
        // If same status priority, sort by creation time (LATEST first - newest orders on top)
        return b.createdAt.compareTo(a.createdAt);
      });
      // Completed orders: Latest first (newest completed orders on top)
      tempCompleted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      activeOrders = tempActive;
      completedOrders = tempCompleted;
      print(
        "WebsiteOrdersScreen: Active orders: ${activeOrders.length}, Completed orders: ${completedOrders.length} for type '$_selectedOrderType'",
      );
      if (selectedOrderId != null) {
        Order? foundOrder;
        try {
          foundOrder = activeOrders.firstWhere(
                (o) => o.orderId == selectedOrderId,
          );
          print(
            "WebsiteOrdersScreen: Found selected order ${selectedOrderId} in active orders",
          );
        } catch (e) {
          try {
            foundOrder = completedOrders.firstWhere(
                  (o) => o.orderId == selectedOrderId,
            );
            print(
              "WebsiteOrdersScreen: Found selected order ${selectedOrderId} in completed orders",
            );
          } catch (e) {
            foundOrder = null;
            print(
              "WebsiteOrdersScreen: Selected order ${selectedOrderId} not found in any list",
            );
          }
        }

        if (foundOrder != null) {
          _selectedOrder = foundOrder;
          print(
            "WebsiteOrdersScreen: Maintained selection for order: ${_selectedOrder?.orderId}",
          );
        } else {
          _selectedOrder =
          activeOrders.isNotEmpty
              ? activeOrders.first
              : completedOrders.isNotEmpty
              ? completedOrders.first
              : null;
          print(
            "WebsiteOrdersScreen: Selected order disappeared, new selected: ${_selectedOrder?.orderId}",
          );
        }
      } else {
        _selectedOrder =
        activeOrders.isNotEmpty
            ? activeOrders.first
            : completedOrders.isNotEmpty
            ? completedOrders.first
            : null;
        if (_selectedOrder != null) {
          print(
            "WebsiteOrdersScreen: No order selected, setting default: ${_selectedOrder?.orderId}",
          );
        }
      }
    });
  }

  String get _screenHeading {
    return 'Website';
  }

  String get _screenImage {
    return 'webwhite.png';
  }

  String _getEmptyStateMessage() {
    if (_selectedOrderType == 'pickup') {
      return 'No pickup orders found.';
    } else if (_selectedOrderType == 'delivery') {
      return 'No delivery orders found.';
    }
    return 'No website orders found.';
  }

  String _nextStatus(Order order) {
    print(
      "WebsiteOrdersScreen: nextStatus: Current status is '${order.status}'. Order Type: ${order.orderType}, Driver ID: ${order.driverId}",
    );

    final String currentStatusLower = order.status.toLowerCase();
    final String orderTypeLower = order.orderType.toLowerCase();
    final bool hasDriver =
        order.driverId != null &&
            order.driverId != 0; // Fixed: use != 0 instead of isNotEmpty

    final bool isWebsiteDeliveryOrder = orderTypeLower == 'delivery';

    if (isWebsiteDeliveryOrder) {
      switch (currentStatusLower) {
        case 'pending':
        case 'accepted':
        case 'yellow':
          return 'Ready'; // Allow PENDING delivery to go to READY
        case 'ready':
        case 'preparing':
        case 'green':
        // If it's ready but no driver assigned yet, keep it as ready
        // If driver is assigned, it should show "On Its Way" in display but status stays 'green'
          if (hasDriver) {
            return 'Ready'; // Don't change status, just display changes
          }
          return 'Ready'; // Stays 'ready' (frontend enforcement)
        case 'completed':
        case 'delivered':
        case 'blue':
          return 'Completed'; // Stays completed
        case 'cancelled':
        case 'red':
          return 'Completed'; // Stays cancelled
        default:
          return 'Ready'; // Fallback
      }
    } else {
      // For all other website order types (e.g., 'pickup')
      switch (currentStatusLower) {
        case 'pending':
        case 'accepted':
        case 'yellow':
          return 'Ready';
        case 'ready':
        case 'preparing':
        case 'green':
          return 'Completed';
        case 'completed':
        case 'delivered':
        case 'blue':
          return 'Completed';
        case 'cancelled':
        case 'red':
          return 'Completed';
        default:
          return 'Ready';
      }
    }
  }

  String _getCategoryIcon(String categoryName) {
    switch (categoryName.toUpperCase()) {
      case 'PIZZA':
        return 'assets/images/PizzasS.png';
      case 'SHAWARMA':
        return 'assets/images/ShawarmaS.png';
      case 'BURGERS':
        return 'assets/images/BurgersS.png';
      case 'CALZONES':
        return 'assets/images/CalzonesS.png';
      case 'GARLICBREAD':
        return 'assets/images/GarlicBreadS.png';
      case 'WRAPS':
        return 'assets/images/WrapsS.png';
      case 'KIDSMEAL':
        return 'assets/images/KidsMealS.png';
      case 'SIDES':
        return 'assets/images/SidesS.png';
      case 'DRINKS':
        return 'assets/images/DrinksS.png';
      case 'MILKSHAKE':
        return 'assets/images/MilkshakeS.png';
      case 'DIPS':
        return 'assets/images/DipsS.png';
      case 'DESSERTS':
        return 'assets/images/Desserts.png';
      case 'CHICKEN':
        return 'assets/images/Chicken.png';
      case 'KEBABS':
        return 'assets/images/Kebabs.png';
      case 'WINGS':
        return 'assets/images/Wings.png';
      default:
        return 'assets/images/default.png';
    }
  }

  Map<String, dynamic> _extractAllOptionsFromDescription(
      String description, {
        List<String>? defaultFoodItemToppings,
        List<String>? defaultFoodItemCheese,
      }) {
    Map<String, dynamic> options = {
      'size': null,
      'crust': null,
      'base': null,
      'drink': null, // NEW: Add drink support
      'isMeal': false, // NEW: Add meal detection
      'toppings': <String>[],
      'sauceDips': <String>[],
      'baseItemName': description,
      'hasOptions': false,
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

    // --- NEW: Combine default toppings and cheese from the FoodItem ---
    // If FoodItem data is not available, use empty set to avoid filtering out valid toppings
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

      // NEW: Enhanced meal detection
      if (lowerOption.contains('make it a meal') ||
          lowerOption.contains('meal') ||
          lowerOption.contains('with drink') ||
          lowerOption.contains('+ drink')) {
        options['isMeal'] = true;
        anyNonDefaultOptionFound = true;
      }
      // NEW: Enhanced drink extraction - handle multiple formats
      else if (lowerOption.startsWith('drink:') ||
          lowerOption.contains('drink:') ||
          lowerOption.startsWith('beverage:') ||
          lowerOption.contains('beverage:')) {
        String drinkValue;
        if (lowerOption.contains('drink:')) {
          drinkValue = option.substring(option.toLowerCase().indexOf('drink:') + 'drink:'.length).trim();
        } else if (lowerOption.contains('beverage:')) {
          drinkValue = option.substring(option.toLowerCase().indexOf('beverage:') + 'beverage:'.length).trim();
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

          // --- Filter against FoodItem's default toppings/cheese ---
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
      } else if (lowerOption.startsWith('sauce dips:')) {
        String sauceDipsValue = option.substring('sauce dips:'.length).trim();
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
      } else if (lowerOption == 'no salad' ||
          lowerOption == 'no sauce' ||
          lowerOption == 'no cream') {
        List<String> currentToppings = List<String>.from(options['toppings']);
        currentToppings.add(option);
        options['toppings'] = currentToppings.toSet().toList();
        anyNonDefaultOptionFound = true;
      }
      // Additional pattern matching for drinks mentioned without prefix
      else if (lowerOption.contains('coke') || lowerOption.contains('pepsi') ||
          lowerOption.contains('fanta') || lowerOption.contains('sprite') ||
          lowerOption.contains('milkshake') || lowerOption.contains('juice') ||
          (lowerOption.contains('can') && (lowerOption.contains('drink') ||
              lowerOption.length < 20))) {
        if (options['drink'] == null) {
          options['drink'] = option.trim();
          options['isMeal'] = true;
          anyNonDefaultOptionFound = true;
        }
      }
    }

    // Additional meal detection based on item names and common patterns
    String baseItemName = options['baseItemName'].toString().toLowerCase();
    if (!options['isMeal'] && (
        baseItemName.contains('burger') &&
            (description.toLowerCase().contains('coke') ||
                description.toLowerCase().contains('pepsi') ||
                description.toLowerCase().contains('fanta') ||
                description.toLowerCase().contains('sprite') ||
                description.toLowerCase().contains('drink') ||
                description.toLowerCase().contains('beverage') ||
                optionsList.any((opt) => opt.toLowerCase().contains('drink') ||
                    opt.toLowerCase().contains('beverage') ||
                    opt.toLowerCase().contains('coke') ||
                    opt.toLowerCase().contains('pepsi')))
    )) {
      options['isMeal'] = true;
      anyNonDefaultOptionFound = true;

      // Try to extract drink from description if not already found
      if (options['drink'] == null) {
        for (var option in optionsList) {
          String lowerOpt = option.toLowerCase();
          if (lowerOpt.contains('coke') || lowerOpt.contains('pepsi') ||
              lowerOpt.contains('fanta') || lowerOpt.contains('sprite')) {
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
            (anyNonDefaultOptionFound ||
                options['size'] != null ||
                options['crust'] != null ||
                options['base'] != null ||
                options['drink'] != null ||
                options['isMeal'] == true ||
                (options['toppings'] as List).isNotEmpty ||
                (options['sauceDips'] as List).isNotEmpty);
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
      } else if (lowerPart.startsWith('sauce dips:')) {
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

  // Future<void> _showReceiptDialog(
  //   Order order,
  //   List<CartItem> cartItems,
  //   double subtotal,
  // ) async {
  //   String receiptContent = _generateReceiptContent(order, cartItems, subtotal);
  //
  //   showDialog(
  //     context: context,
  //     builder: (BuildContext context) {
  //       return Dialog(
  //         child: Container(
  //           width: 400,
  //           height: 600,
  //           padding: const EdgeInsets.all(16),
  //           child: Column(
  //             children: [
  //               Row(
  //                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
  //                 children: [
  //                   const Text(
  //                     'Receipt Preview',
  //                     style: TextStyle(
  //                       fontSize: 18,
  //                       fontWeight: FontWeight.bold,
  //                     ),
  //                   ),
  //                   IconButton(
  //                     icon: const Icon(Icons.close),
  //                     onPressed: () => Navigator.of(context).pop(),
  //                   ),
  //                 ],
  //               ),
  //               const Divider(),
  //               Expanded(
  //                 child: SingleChildScrollView(
  //                   child: Container(
  //                     padding: const EdgeInsets.all(12),
  //                     decoration: BoxDecoration(
  //                       color: Colors.grey[100],
  //                       borderRadius: BorderRadius.circular(8),
  //                     ),
  //                     child: Text(
  //                       receiptContent,
  //                       style: const TextStyle(
  //                         fontFamily: 'monospace',
  //                         fontSize: 12,
  //                       ),
  //                     ),
  //                   ),
  //                 ),
  //               ),
  //             ],
  //           ),
  //         ),
  //       );
  //     },
  //   );
  // }
  //
  // String _generateReceiptContent(
  //   Order order,
  //   List<CartItem> cartItems,
  //   double subtotal,
  // ) {
  //   StringBuffer content = StringBuffer();
  //   content.writeln('================================================');
  //   content.writeln('                RECEIPT PREVIEW                ');
  //   content.writeln('================================================');
  //   content.writeln('Order ID: ${order.orderId}');
  //   content.writeln('Order Type: ${order.orderType}');
  //   content.writeln('Date: ${DateTime.now().toString().split('.')[0]}');
  //   content.writeln('------------------------------------------------');
  //
  //   if (order.customerName.isNotEmpty == true) {
  //     content.writeln('Customer: ${order.customerName}');
  //   }
  //   if (order.phoneNumber?.isNotEmpty == true) {
  //     content.writeln('Phone: ${order.phoneNumber}');
  //   }
  //   if (order.streetAddress?.isNotEmpty == true) {
  //     content.writeln('Address: ${order.streetAddress}');
  //     if (order.city?.isNotEmpty == true) {
  //       content.writeln('City: ${order.city}');
  //     }
  //     if (order.postalCode?.isNotEmpty == true) {
  //       content.writeln('Postal Code: ${order.postalCode}');
  //     }
  //   }
  //   content.writeln('------------------------------------------------');
  //
  //   for (var item in cartItems) {
  //     content.writeln('${item.foodItem.name} x${item.quantity}');
  //     content.writeln(
  //       '  £${(item.pricePerUnit * item.quantity).toStringAsFixed(2)}',
  //     );
  //
  //     if (item.selectedOptions != null && item.selectedOptions!.isNotEmpty) {
  //       for (var option in item.selectedOptions!) {
  //         content.writeln('  + $option');
  //       }
  //     }
  //
  //     if (item.comment?.isNotEmpty == true) {
  //       content.writeln('  Note: ${item.comment}');
  //     }
  //     content.writeln('');
  //   }
  //
  //   content.writeln('------------------------------------------------');
  //   content.writeln('Subtotal: £${subtotal.toStringAsFixed(2)}');
  //   content.writeln('TOTAL: £${order.orderTotalPrice.toStringAsFixed(2)}');
  //
  //   if (order.changeDue > 0) {
  //     content.writeln('Change Due: £${order.changeDue.toStringAsFixed(2)}');
  //   }
  //
  //   if (order.paymentType.isNotEmpty == true) {
  //     content.writeln('Payment: ${order.paymentType}');
  //   }
  //
  //   if (order.orderExtraNotes?.isNotEmpty == true) {
  //     content.writeln('------------------------------------------------');
  //     content.writeln('Notes: ${order.orderExtraNotes}');
  //   }
  //
  //   content.writeln('================================================');
  //   content.writeln('           Thank you for your order!           ');
  //   content.writeln('================================================');
  //
  //   return content.toString();
  // }

  @override
  Widget build(BuildContext context) {
    print(
      "WebsiteOrdersScreen: build method called. Active orders: ${activeOrders.length}, Completed orders: ${completedOrders.length}",
    );

    // Get screen dimensions for responsive design
    final screenWidth = MediaQuery.of(context).size.width;

    // Calculate responsive dimensions based on 10.5" screen
    final isLargeScreen = screenWidth > 1200;
    final headerImageSize = isLargeScreen ? 70.0 : 60.0;
    final headerFontSize = isLargeScreen ? 52.0 : 46.0;
    final buttonWidth = isLargeScreen ? 220.0 : 200.0;
    final buttonHeight = isLargeScreen ? 65.0 : 55.0;
    final buttonFontSize = isLargeScreen ? 32.0 : 28.0;

    final allOrdersForDisplay = <Order>[];
    allOrdersForDisplay.addAll(activeOrders);

    if (activeOrders.isNotEmpty && completedOrders.isNotEmpty) {
      allOrdersForDisplay.add(
        Order(
          orderId: -1,
          customerName: '',
          items: [],
          orderTotalPrice: 0.0,
          createdAt: UKTimeService.now(),
          status: 'divider',
          orderType: 'divider',
          changeDue: 0.0,
          orderSource: 'internal',
          paymentType: '',
          transactionId: '',
        ),
      );
    }

    allOrdersForDisplay.addAll(completedOrders);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Row(
              children: [
                // --- Left Panel (Order List) ---
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: EdgeInsets.all(isLargeScreen ? 20.0 : 16.0),
                    color: Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: EdgeInsets.all(isLargeScreen ? 20 : 17),
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(25),
                              ),
                              child: Image.asset(
                                'assets/images/${_screenImage}',
                                width: headerImageSize,
                                height: headerImageSize,
                              ),
                            ),
                            SizedBox(width: isLargeScreen ? 25 : 20),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: isLargeScreen ? 22 : 18,
                                vertical: isLargeScreen ? 16 : 14,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(25),
                              ),
                              child: Text(
                                _screenHeading,
                                style: TextStyle(
                                  fontSize: headerFontSize,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: isLargeScreen ? 25 : 20),
                        // Pickup/Delivery Filter Buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedOrderType = 'pickup';
                                    _separateOrders(
                                      Provider.of<OrderProvider>(
                                        context,
                                        listen: false,
                                      ).websiteOrders,
                                    );
                                  });
                                },
                                child: Container(
                                  width: buttonWidth,
                                  height: buttonHeight,
                                  margin: EdgeInsets.symmetric(
                                    horizontal: isLargeScreen ? 10 : 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                    _selectedOrderType == 'pickup'
                                        ? Colors.grey[100]
                                        : Colors.black,
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Pickup',
                                      style: TextStyle(
                                        fontSize: buttonFontSize,
                                        fontWeight: FontWeight.bold,
                                        color:
                                        _selectedOrderType == 'pickup'
                                            ? Colors.black
                                            : Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedOrderType = 'delivery';
                                    _separateOrders(
                                      Provider.of<OrderProvider>(
                                        context,
                                        listen: false,
                                      ).websiteOrders,
                                    );
                                  });
                                },
                                child: Container(
                                  width: buttonWidth,
                                  height: buttonHeight,
                                  margin: EdgeInsets.symmetric(
                                    horizontal: isLargeScreen ? 10 : 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                    _selectedOrderType == 'delivery'
                                        ? Colors.grey[100]
                                        : Colors.black,
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Delivery',
                                      style: TextStyle(
                                        fontSize: buttonFontSize,
                                        fontWeight: FontWeight.bold,
                                        color:
                                        _selectedOrderType == 'delivery'
                                            ? Colors.black
                                            : Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: isLargeScreen ? 25 : 20),

                        Expanded(
                          child:
                          allOrdersForDisplay.isEmpty
                              ? Center(
                            child: Text(
                              _getEmptyStateMessage(),
                              style: TextStyle(
                                fontSize: isLargeScreen ? 20 : 18,
                                color: Colors.grey[600],
                              ),
                            ),
                          )
                              : ListView.builder(
                            itemCount: allOrdersForDisplay.length,
                            itemBuilder: (context, index) {
                              final order = allOrdersForDisplay[index];

                              if (order.orderId == -1 &&
                                  order.status == 'divider' &&
                                  order.orderType == 'divider') {
                                return Padding(
                                  padding: EdgeInsets.symmetric(
                                    vertical:
                                    isLargeScreen ? 12.0 : 10.0,
                                    horizontal: isLargeScreen ? 70 : 60,
                                  ),
                                  child: const Divider(
                                    color: Color(0xFFB2B2B2),
                                    thickness: 2,
                                  ),
                                );
                              }

                              bool isActiveOrder = activeOrders
                                  .contains(order);
                              int? serialNumber;
                              if (isActiveOrder) {
                                serialNumber =
                                    activeOrders.indexOf(order) + 1;
                              }

                              Color finalDisplayColor;

                              // Helper function for time-based colors - NOW TAKES THE SPECIFIC ORDER
                              Color getTimeBasedColor(
                                  String status,
                                  DateTime orderCreatedAt,
                                  ) {
                                // Calculate time for THIS specific order
                                DateTime now = UKTimeService.now();
                                Duration orderAge = now.difference(
                                  orderCreatedAt,
                                );
                                int minutesPassed = orderAge.inMinutes;

                                // Completed orders are always grey regardless of time
                                if (status.toLowerCase() == 'blue' ||
                                    status.toLowerCase() ==
                                        'completed' ||
                                    status.toLowerCase() ==
                                        'delivered') {
                                  return HexColor.fromHex('D6D6D6');
                                }

                                // Cancelled orders keep their red color
                                if (status.toLowerCase() == 'red' ||
                                    status.toLowerCase() ==
                                        'cancelled') {
                                  return Colors.red[100]!;
                                }

                                // Time-based colors for active orders
                                if (minutesPassed < 30) {
                                  return HexColor.fromHex(
                                    'DEF5D4',
                                  ); // Green - 0-30 minutes
                                } else if (minutesPassed >= 30 &&
                                    minutesPassed < 45) {
                                  return HexColor.fromHex(
                                    'FFF6D4',
                                  ); // Yellow - 30-45 minutes
                                } else {
                                  return HexColor.fromHex(
                                    'ffcaca',
                                  ); // Red - 45+ minutes
                                }
                              }

                              Provider.of<OrderProvider>(
                                context,
                                listen: false,
                              );
                              finalDisplayColor = getTimeBasedColor(
                                order.status.toLowerCase(),
                                order.createdAt,
                              );

                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedOrder = order;
                                  });
                                },
                                child: Container(
                                  margin: EdgeInsets.symmetric(
                                    vertical: 1,
                                    horizontal: isLargeScreen ? 70 : 60,
                                  ),
                                  padding: EdgeInsets.all(
                                    isLargeScreen ? 10 : 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(
                                      22,
                                    ),
                                    border: Border.all(
                                      color: Colors.transparent,
                                      width: 3,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      if (serialNumber != null)
                                        Text(
                                          '$serialNumber',
                                          style: TextStyle(
                                            fontSize:
                                            isLargeScreen ? 55 : 50,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                      else
                                        const SizedBox(width: 0),

                                      SizedBox(
                                        width:
                                        serialNumber != null
                                            ? (isLargeScreen
                                            ? 18
                                            : 15)
                                            : 0,
                                      ),

                                      Expanded(
                                        flex:
                                        serialNumber != null
                                            ? 3
                                            : 4,
                                        child: GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _selectedOrder = order;
                                            });
                                          },
                                          child: Container(
                                            padding:
                                            EdgeInsets.symmetric(
                                              horizontal:
                                              isLargeScreen
                                                  ? 35
                                                  : 30,
                                              vertical:
                                              isLargeScreen
                                                  ? 25
                                                  : 20,
                                            ),
                                            decoration: BoxDecoration(
                                              color: finalDisplayColor,
                                              borderRadius:
                                              BorderRadius.circular(
                                                50,
                                              ),
                                            ),
                                            child: Text(
                                              order
                                                  .displayAddressSummary,
                                              style: TextStyle(
                                                fontSize:
                                                isLargeScreen
                                                    ? 32
                                                    : 29,
                                                color: Colors.black,
                                              ),
                                              overflow:
                                              TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: isLargeScreen ? 12 : 10,
                                      ),
                                      // Circular Timer - only show for active orders
                                      if (serialNumber != null) ...[
                                        CircularTimer(
                                          startTime: order.createdAt,
                                          size:
                                          isLargeScreen
                                              ? 80.0
                                              : 70.0,
                                          progressColor: Colors.black,
                                          backgroundColor: Colors.grey,
                                          strokeWidth:
                                          isLargeScreen ? 6.0 : 5.0,
                                          maxMinutes: 60,
                                        ),
                                      ],
                                      SizedBox(
                                        width: isLargeScreen ? 12 : 10,
                                      ),

                                      GestureDetector(
                                        onTap: () async {
                                          // First, check if the order is already in a final state (completed, delivered, cancelled)
                                          final bool isFinalState =
                                              order.status
                                                  .toLowerCase() ==
                                                  'completed' ||
                                                  order.status
                                                      .toLowerCase() ==
                                                      'delivered' ||
                                                  order.status
                                                      .toLowerCase() ==
                                                      'blue' ||
                                                  order.status
                                                      .toLowerCase() ==
                                                      'cancelled' ||
                                                  order.status
                                                      .toLowerCase() ==
                                                      'red';

                                          if (isFinalState) {
                                            if (mounted) {
                                              CustomPopupService.show(
                                                context,
                                                'Order ${order.orderId} is already ${order.statusLabel}.',
                                                //type: PopupType.failure,
                                              );
                                            }
                                            return; // Do nothing if it's already in a final state
                                          }

                                          // Determine the next intended status using the intelligent function
                                          final String
                                          nextIntendedStatus = _nextStatus(
                                            order,
                                          ); // Pass the full order object

                                          // Specific rule for Website Delivery Orders:
                                          // If it's a delivery order and currently 'ready', AND the _nextStatus function also says 'ready'
                                          // (meaning it cannot progress further from this app), then show a message and stop.
                                          final bool
                                          isWebsiteDeliveryOrder =
                                              order.orderType
                                                  .toLowerCase() ==
                                                  'delivery';

                                          if (isWebsiteDeliveryOrder &&
                                              order.status
                                                  .toLowerCase() ==
                                                  'ready' &&
                                              nextIntendedStatus
                                                  .toLowerCase() ==
                                                  'ready') {
                                            if (mounted) {
                                              CustomPopupService.show(
                                                context,
                                                "Website Delivery orders cannot be updated beyond 'Ready' from this screen.",
                                                type: PopupType.failure,
                                              );
                                            }
                                            return; // Prevent update
                                          }

                                          final orderProvider =
                                          Provider.of<
                                              OrderProvider
                                          >(context, listen: false);
                                          Provider.of<
                                              OrderCountsProvider
                                          >(context, listen: false);

                                          bool
                                          success = await orderProvider
                                              .updateAndRefreshOrder(
                                            order.orderId,
                                            nextIntendedStatus,
                                          );

                                          if (success) {
                                            if (mounted) {
                                              CustomPopupService.show(
                                                context,
                                                'Order ${order.orderId} status updated to ${nextIntendedStatus.toUpperCase()}.',
                                                type: PopupType.success,
                                              );
                                            }
                                          } else {
                                            if (mounted) {
                                              CustomPopupService.show(
                                                context,
                                                'Order ${order.orderId} status updated to ${nextIntendedStatus.toUpperCase()}.',
                                                type: PopupType.success,
                                              );

                                              CustomPopupService.show(
                                                context,
                                                'Failed to update status for order ${order.orderId}. Please try again.',
                                                type: PopupType.failure,
                                              );
                                            }
                                          }
                                        },
                                        child: Container(
                                          width:
                                          isLargeScreen ? 220 : 200,
                                          height:
                                          isLargeScreen ? 90 : 80,
                                          alignment: Alignment.center,
                                          padding: EdgeInsets.symmetric(
                                            horizontal:
                                            isLargeScreen ? 16 : 14,
                                            vertical:
                                            isLargeScreen ? 12 : 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: finalDisplayColor, // Use the determined color
                                            borderRadius:
                                            BorderRadius.circular(
                                              50,
                                            ),
                                          ),
                                          child: Text(
                                            // Dynamic text for the button - use the same logic as display label
                                            (() {
                                              final orderProvider =
                                              Provider.of<
                                                  OrderProvider
                                              >(
                                                context,
                                                listen: false,
                                              );
                                              final displayStatus =
                                              orderProvider
                                                  .getDeliveryDisplayStatus(
                                                order,
                                              );

                                              // For completed orders, always show "Completed"
                                              if (order.status
                                                  .toLowerCase() ==
                                                  'completed' ||
                                                  order.status
                                                      .toLowerCase() ==
                                                      'blue' ||
                                                  order.status
                                                      .toLowerCase() ==
                                                      'delivered') {
                                                return 'Completed';
                                              }

                                              // For delivery orders that are ready with driver, show "On Its Way"
                                              if (order.orderType
                                                  .toLowerCase() ==
                                                  'delivery' &&
                                                  order.status
                                                      .toLowerCase() ==
                                                      'green' &&
                                                  order.driverId !=
                                                      null &&
                                                  order.driverId != 0) {
                                                return 'On Its Way';
                                              }

                                              return displayStatus;
                                            })(),
                                            style: TextStyle(
                                              fontSize:
                                              isLargeScreen
                                                  ? 28
                                                  : 25,
                                              color: Colors.black,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: isLargeScreen ? 25.0 : 20.0,
                  ),
                  child: const VerticalDivider(
                    width: 3,
                    thickness: 3,
                    color: Colors.grey,
                  ),
                ),

                //RIGHT PANEL
                Expanded(
                  flex: 1,
                  child: Container(
                    color: Colors.white,
                    padding: EdgeInsets.all(isLargeScreen ? 12.0 : 9.0),
                    child:
                    _selectedOrder == null
                        ? Center(
                      child: Text(
                        'Select an order to see details',
                        style: TextStyle(
                          fontSize: isLargeScreen ? 20 : 18,
                          color: Colors.grey[600],
                        ),
                      ),
                    )
                        : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Order Number and Header
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isLargeScreen ? 25.0 : 20.0,
                            vertical: isLargeScreen ? 8 : 5,
                          ),
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _selectedOrder!.orderType
                                        .toLowerCase() ==
                                        "delivery" &&
                                        _selectedOrder!
                                            .postalCode !=
                                            null &&
                                        _selectedOrder!
                                            .postalCode!
                                            .isNotEmpty
                                        ? '${_selectedOrder!.postalCode} '
                                        : '',
                                    style: TextStyle(
                                      fontSize: isLargeScreen ? 19 : 17,
                                      fontWeight: FontWeight.normal,
                                    ),
                                  ),
                                  // Display Order Number
                                  Text(
                                    'Order no. ${_selectedOrder!.orderId}',
                                    style: TextStyle(
                                      fontSize: isLargeScreen ? 19 : 17,
                                      fontWeight: FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),

                              if (_selectedOrder!.orderType
                                  .toLowerCase() ==
                                  "delivery" &&
                                  _selectedOrder!.streetAddress !=
                                      null &&
                                  _selectedOrder!
                                      .streetAddress!
                                      .isNotEmpty)
                                Text(
                                  _selectedOrder!.streetAddress!,
                                  style: TextStyle(
                                    fontSize: isLargeScreen ? 20 : 18,
                                  ),
                                ),
                              if (_selectedOrder!.orderType
                                  .toLowerCase() ==
                                  "delivery" &&
                                  _selectedOrder!.city != null &&
                                  _selectedOrder!.city!.isNotEmpty)
                                Text(
                                  '${_selectedOrder!.city}, ${_selectedOrder!.postalCode ?? ''}',
                                  style: TextStyle(
                                    fontSize: isLargeScreen ? 20 : 18,
                                  ),
                                ),
                              if (_selectedOrder!.phoneNumber != null &&
                                  _selectedOrder!
                                      .phoneNumber!
                                      .isNotEmpty)
                                Text(
                                  _selectedOrder!.phoneNumber!,
                                  style: TextStyle(
                                    fontSize: isLargeScreen ? 20 : 18,
                                  ),
                                ),
                              Text(
                                _selectedOrder!.customerName,
                                style: TextStyle(
                                  fontSize: isLargeScreen ? 19 : 17,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                              if ((_selectedOrder!.orderType
                                  .toLowerCase() ==
                                  "delivery" ||
                                  _selectedOrder!.orderType
                                      .toLowerCase() ==
                                      "takeaway") &&
                                  _selectedOrder!.customerEmail !=
                                      null &&
                                  _selectedOrder!
                                      .customerEmail!
                                      .isNotEmpty)
                                Text(
                                  _selectedOrder!.customerEmail!,
                                  style: TextStyle(
                                    fontSize: isLargeScreen ? 20 : 18,
                                  ),
                                ),

                              // Display order-level extra notes
                              if (_selectedOrder!.orderExtraNotes != null &&
                                  _selectedOrder!.orderExtraNotes!.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12.0,
                                    horizontal: 16.0,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE8F5E8),
                                    borderRadius: BorderRadius.circular(8.0),
                                    border: Border.all(
                                      color: const Color(0xFF4CAF50),
                                      width: 1,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Order Notes:',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF2E7D2E),
                                          fontFamily: 'Poppins',
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _selectedOrder!.orderExtraNotes!,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          color: Color(0xFF2E7D2E),
                                          fontFamily: 'Poppins',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        SizedBox(height: isLargeScreen ? 25 : 20),
                        // Horizontal Divider
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isLargeScreen ? 65.0 : 55.0,
                          ),
                          child: const Divider(
                            height: 0,
                            thickness: 3,
                            color: Color(0xFFB2B2B2),
                          ),
                        ),

                        SizedBox(height: isLargeScreen ? 15 : 10),
                        Expanded(
                          child: RawScrollbar(
                            controller: _scrollController,
                            thumbVisibility: true,
                            trackVisibility: false,
                            thickness: isLargeScreen ? 12.0 : 10.0,
                            radius: const Radius.circular(30),
                            interactive: true,
                            thumbColor: const Color(0xFFF2D9F9),
                            child: ListView.builder(
                              controller: _scrollController,
                              itemCount: _selectedOrder!.items.length,
                              itemBuilder: (context, itemIndex) {
                                final item =
                                _selectedOrder!.items[itemIndex];

                                // Enhanced option extraction
                                Map<String, dynamic> itemOptions =
                                _extractAllOptionsFromDescription(
                                  item.description,
                                  defaultFoodItemToppings:
                                  item
                                      .foodItem
                                      ?.defaultToppings,
                                  defaultFoodItemCheese:
                                  item.foodItem?.defaultCheese,
                                );

                                String? selectedSize =
                                itemOptions['size'];
                                String? selectedCrust =
                                itemOptions['crust'];
                                String? selectedBase =
                                itemOptions['base'];
                                String? selectedDrink =
                                itemOptions['drink'];
                                bool isMeal =
                                    itemOptions['isMeal'] ?? false;
                                List<String> toppings =
                                    itemOptions['toppings'] ?? [];
                                List<String> sauceDips =
                                    itemOptions['sauceDips'] ?? [];
                                String baseItemName =
                                    itemOptions['baseItemName'] ??
                                        item.itemName;
                                String displayItemName = item.itemName;
                                bool hasOptions =
                                    itemOptions['hasOptions'] ?? false;

                                return Padding(
                                  padding: EdgeInsets.only(
                                    bottom: isLargeScreen ? 15.0 : 12.0,
                                  ),
                                  child: Column(
                                    children: [
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          vertical:
                                          isLargeScreen ? 12 : 10,
                                          horizontal:
                                          isLargeScreen ? 45 : 40,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                          children: [
                                            Expanded(
                                              flex: 6,
                                              child: Row(
                                                crossAxisAlignment:
                                                CrossAxisAlignment
                                                    .start,
                                                children: [
                                                  Text(
                                                    '${item.quantity}',
                                                    style: TextStyle(
                                                      fontWeight:
                                                      FontWeight
                                                          .bold,
                                                      fontSize:
                                                      isLargeScreen
                                                          ? 38
                                                          : 34,
                                                      fontFamily:
                                                      'Poppins',
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: Padding(
                                                      padding: EdgeInsets.only(
                                                        left:
                                                        isLargeScreen
                                                            ? 35
                                                            : 30,
                                                        right:
                                                        isLargeScreen
                                                            ? 12
                                                            : 10,
                                                      ),
                                                      child: Column(
                                                        crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                        children: [
                                                          // Always show parsed information if available, otherwise show raw description
                                                          // Replace this section in the build method where item details are displayed
// Look for the section that starts with "if (hasOptions) ...[" and replace it with this:

                                                          if (hasOptions) ...[
                                                            // Show extracted base item name if it's different and meaningful
                                                            if (baseItemName != displayItemName &&
                                                                baseItemName.trim().isNotEmpty &&
                                                                !baseItemName.toLowerCase().contains('size:') &&
                                                                !baseItemName.toLowerCase().contains('crust:') &&
                                                                !baseItemName.toLowerCase().contains('base:'))
                                                              Text(
                                                                baseItemName,
                                                                style: TextStyle(
                                                                  fontSize: isLargeScreen ? 17 : 15,
                                                                  fontFamily: 'Poppins',
                                                                  color: Colors.black,
                                                                  fontWeight: FontWeight.w600,
                                                                ),
                                                                overflow: TextOverflow.ellipsis,
                                                              ),

                                                            // Display Size (only if not default)
                                                            if (selectedSize != null)
                                                              Text(
                                                                'Size: $selectedSize',
                                                                style: TextStyle(
                                                                  fontSize: isLargeScreen ? 17 : 15,
                                                                  fontFamily: 'Poppins',
                                                                  color: Colors.black,
                                                                ),
                                                                overflow: TextOverflow.ellipsis,
                                                              ),

                                                            // Display Crust (only if not default)
                                                            if (selectedCrust != null)
                                                              Text(
                                                                'Crust: $selectedCrust',
                                                                style: TextStyle(
                                                                  fontSize: isLargeScreen ? 17 : 15,
                                                                  fontFamily: 'Poppins',
                                                                  color: Colors.black,
                                                                ),
                                                                overflow: TextOverflow.ellipsis,
                                                              ),

                                                            // Display Base (only if not default)
                                                            if (selectedBase != null)
                                                              Text(
                                                                'Base: $selectedBase',
                                                                style: TextStyle(
                                                                  fontSize: isLargeScreen ? 17 : 15,
                                                                  fontFamily: 'Poppins',
                                                                  color: Colors.black,
                                                                ),
                                                                overflow: TextOverflow.ellipsis,
                                                              ),

                                                            // Display Toppings (only if not empty)
                                                            if (toppings.isNotEmpty)
                                                              Text(
                                                                'Extra Toppings: ${toppings.join(', ')}',
                                                                style: TextStyle(
                                                                  fontSize: isLargeScreen ? 17 : 15,
                                                                  fontFamily: 'Poppins',
                                                                  color: Colors.black,
                                                                ),
                                                                maxLines: 3,
                                                                overflow: TextOverflow.ellipsis,
                                                              ),

                                                            // Display Sauce Dips (only if not empty)
                                                            if (sauceDips.isNotEmpty)
                                                              Text(
                                                                'Sauce Dips: ${sauceDips.join(', ')}',
                                                                style: TextStyle(
                                                                  fontSize: isLargeScreen ? 17 : 15,
                                                                  fontFamily: 'Poppins',
                                                                  color: Colors.black,
                                                                ),
                                                                maxLines: 2,
                                                                overflow: TextOverflow.ellipsis,
                                                              ),

                                                            // Display meal information with drink - CONSOLIDATED to avoid duplication
                                                            if (isMeal && selectedDrink != null && selectedDrink.isNotEmpty)
                                                              Text(
                                                                'Drink: $selectedDrink',
                                                                style: TextStyle(
                                                                  fontSize: isLargeScreen ? 17 : 15,
                                                                  fontFamily: 'Poppins',
                                                                  color: Colors.black,
                                                                ),
                                                                overflow: TextOverflow.ellipsis,
                                                              )
                                                            // Display drink separately only if it's NOT part of a meal
                                                            else if (!isMeal && selectedDrink != null && selectedDrink.isNotEmpty)
                                                              Text(
                                                                'Drink: $selectedDrink',
                                                                style: TextStyle(
                                                                  fontSize: isLargeScreen ? 17 : 15,
                                                                  fontFamily: 'Poppins',
                                                                  color: Colors.black,
                                                                ),
                                                                overflow: TextOverflow.ellipsis,
                                                              ),
                                                          ] else ...[
                                                            // No structured options found, show raw description
                                                            Text(
                                                              item.description,
                                                              style: TextStyle(
                                                                fontSize: isLargeScreen ? 17 : 15,
                                                                fontFamily: 'Poppins',
                                                                color: Colors.black,
                                                                fontStyle: FontStyle.normal,
                                                              ),
                                                              maxLines: 3,
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ],

                                                          // Display item comment/notes if present (moved outside the hasOptions check)
                                                          if (item.comment !=
                                                              null &&
                                                              item
                                                                  .comment!
                                                                  .isNotEmpty)
                                                            Text(
                                                              'Note: ${item.comment!}',
                                                              style: TextStyle(
                                                                fontSize:
                                                                isLargeScreen
                                                                    ? 17
                                                                    : 15,
                                                                fontFamily:
                                                                'Poppins',
                                                                color:
                                                                Colors.orange[700],
                                                                fontWeight:
                                                                FontWeight.w500,
                                                              ),
                                                              maxLines:
                                                              3,
                                                              overflow:
                                                              TextOverflow
                                                                  .ellipsis,
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                            Container(
                                              width: 3,
                                              height:
                                              isLargeScreen
                                                  ? 120
                                                  : 110,
                                              margin:
                                              const EdgeInsets.symmetric(
                                                horizontal: 0,
                                              ),
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                BorderRadius.circular(
                                                  30,
                                                ),
                                                color: const Color(
                                                  0xFFB2B2B2,
                                                ),
                                              ),
                                            ),

                                            Expanded(
                                              flex: 3,
                                              child: Column(
                                                crossAxisAlignment:
                                                CrossAxisAlignment
                                                    .center,
                                                children: [
                                                  Container(
                                                    width:
                                                    isLargeScreen
                                                        ? 100
                                                        : 90,
                                                    height:
                                                    isLargeScreen
                                                        ? 74
                                                        : 64,
                                                    decoration:
                                                    BoxDecoration(
                                                      borderRadius:
                                                      BorderRadius.circular(
                                                        12,
                                                      ),
                                                    ),
                                                    clipBehavior:
                                                    Clip.hardEdge,
                                                    child: Image.asset(
                                                      _getCategoryIcon(
                                                        item.itemType,
                                                      ),
                                                      fit:
                                                      BoxFit
                                                          .contain,
                                                    ),
                                                  ),
                                                  SizedBox(
                                                    height:
                                                    isLargeScreen
                                                        ? 10
                                                        : 8,
                                                  ),
                                                  Text(
                                                    displayItemName,
                                                    textAlign:
                                                    TextAlign
                                                        .center,
                                                    style: TextStyle(
                                                      fontSize:
                                                      isLargeScreen
                                                          ? 18
                                                          : 16,
                                                      fontWeight:
                                                      FontWeight
                                                          .normal,
                                                      fontFamily:
                                                      'Poppins',
                                                    ),
                                                    maxLines: 2,
                                                    overflow:
                                                    TextOverflow
                                                        .ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      if (item.comment != null &&
                                          item.comment!.isNotEmpty)
                                        Padding(
                                          padding: EdgeInsets.only(
                                            top:
                                            isLargeScreen
                                                ? 10.0
                                                : 8.0,
                                          ),
                                          child: Container(
                                            width: double.infinity,
                                            padding:
                                            EdgeInsets.symmetric(
                                              vertical:
                                              isLargeScreen
                                                  ? 10.0
                                                  : 8.0,
                                              horizontal:
                                              isLargeScreen
                                                  ? 15.0
                                                  : 12.0,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(
                                                0xFFFDF1C7,
                                              ),
                                              borderRadius:
                                              BorderRadius.circular(
                                                8.0,
                                              ),
                                            ),
                                            child: Center(
                                              child: Text(
                                                'Comment: ${item.comment!}',
                                                textAlign:
                                                TextAlign.center,
                                                style: TextStyle(
                                                  fontSize:
                                                  isLargeScreen
                                                      ? 18
                                                      : 16,
                                                  color: Colors.black,
                                                  fontFamily: 'Poppins',
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        // Horizontal Divider
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isLargeScreen ? 65.0 : 55.0,
                          ),
                          child: const Divider(
                            height: 0,
                            thickness: 3,
                            color: Color(0xFFB2B2B2),
                          ),
                        ),

                        SizedBox(height: isLargeScreen ? 15 : 10),

                        Column(
                          children: [
                            // Payment Type Row
                            Row(
                              mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Payment Type:',
                                  style: TextStyle(
                                    fontSize: isLargeScreen ? 20 : 18,
                                  ),
                                ),
                                Text(
                                  _selectedOrder!.paymentType,
                                  style: TextStyle(
                                    fontSize: isLargeScreen ? 20 : 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: isLargeScreen ? 18 : 13),

                            // Total and Change Due Box with Printer Icon
                            Row(
                              mainAxisAlignment:
                              MainAxisAlignment.spaceEvenly,
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: EdgeInsets.all(
                                    isLargeScreen ? 40 : 35,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.circular(
                                      15,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                        MainAxisAlignment
                                            .spaceBetween,
                                        children: [
                                          Text(
                                            'Total',
                                            style: TextStyle(
                                              fontSize:
                                              isLargeScreen
                                                  ? 22
                                                  : 20,
                                              fontWeight:
                                              FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                          SizedBox(
                                            width:
                                            isLargeScreen
                                                ? 120
                                                : 110,
                                          ),
                                          Text(
                                            '£${_selectedOrder!.orderTotalPrice.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              fontSize:
                                              isLargeScreen
                                                  ? 22
                                                  : 20,
                                              fontWeight:
                                              FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (_selectedOrder!.changeDue >
                                          0) ...[
                                        SizedBox(
                                          height:
                                          isLargeScreen ? 12 : 10,
                                        ),
                                        Row(
                                          mainAxisAlignment:
                                          MainAxisAlignment
                                              .spaceBetween,
                                          children: [
                                            Text(
                                              'Change Due',
                                              style: TextStyle(
                                                fontSize:
                                                isLargeScreen
                                                    ? 22
                                                    : 20,
                                                fontWeight:
                                                FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                            SizedBox(
                                              width:
                                              isLargeScreen
                                                  ? 50
                                                  : 40,
                                            ),
                                            Text(
                                              '£${_selectedOrder!.changeDue.toStringAsFixed(2)}',
                                              style: TextStyle(
                                                fontSize:
                                                isLargeScreen
                                                    ? 22
                                                    : 20,
                                                fontWeight:
                                                FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: isLargeScreen ? 25 : 20,
                                ),

                                MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: GestureDetector(
                                    onTap: () async {
                                      await _handlePrintingOrderReceipt();
                                    },
                                    child: Container(
                                      padding: EdgeInsets.all(
                                        isLargeScreen ? 10 : 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black,
                                        borderRadius:
                                        BorderRadius.circular(15),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Image.asset(
                                            'assets/images/printer.png',
                                            width:
                                            isLargeScreen ? 65 : 58,
                                            height:
                                            isLargeScreen ? 65 : 58,
                                            color: Colors.white,
                                          ),
                                          SizedBox(
                                            height:
                                            isLargeScreen ? 6 : 4,
                                          ),
                                          Text(
                                            'Print Receipt',
                                            style: TextStyle(
                                              fontSize:
                                              isLargeScreen
                                                  ? 17
                                                  : 15,
                                              fontWeight:
                                              FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // Printer status indicator - positioned at top left
            Positioned(
              top: isLargeScreen ? 20 : 16,
              left: isLargeScreen ? 20 : 16,
              child: Container(
                width: isLargeScreen ? 15 : 12,
                height: isLargeScreen ? 15 : 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isPrinterConnected ? Colors.green : Colors.red,
                  boxShadow: [
                    BoxShadow(
                      color: (_isPrinterConnected ? Colors.green : Colors.red)
                          .withOpacity(0.5),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      bottomNavigationBar: CustomBottomNavBar(
        selectedIndex: _selectedBottomNavItem,
        showDivider: true,
        onItemSelected: (index) {
          if (index == 3) {
            setState(() {
              _selectedBottomNavItem = index;
            });
          }
        },
      ),
    );
  }
}
