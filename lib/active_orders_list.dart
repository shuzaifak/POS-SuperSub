// lib/active_orders_list.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:epos/models/order.dart';
import 'package:provider/provider.dart';
import 'package:epos/providers/active_orders_provider.dart';
import 'package:epos/services/thermal_printer_service.dart';
import 'package:epos/services/custom_popup_service.dart';
import 'models/cart_item.dart';
import 'models/food_item.dart';

extension HexColor on Color {
  static Color fromHex(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }
}

class ActiveOrdersList extends StatefulWidget {
  const ActiveOrdersList({super.key});

  @override
  State<ActiveOrdersList> createState() => _ActiveOrdersListState();
}

class _ActiveOrdersListState extends State<ActiveOrdersList> {
  Order? _selectedOrder;
  final ScrollController _scrollController = ScrollController();
  bool _isPrinterConnected = false;
  bool _isCheckingPrinter = false;
  Timer? _printerStatusTimer;
  DateTime? _lastPrinterCheck;
  Map<String, bool>? _cachedPrinterStatus;

  @override
  void initState() {
    super.initState();
    _startPrinterStatusChecking();
  }

  void _startPrinterStatusChecking() {
    _checkPrinterStatus();

    // Check every 2 minutes instead of 30 seconds to reduce printer communication
    _printerStatusTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      _checkPrinterStatus();
    });
  }

  Future<void> _checkPrinterStatus() async {
    if (_isCheckingPrinter || !mounted) return; // Add mounted check

    setState(() {
      _isCheckingPrinter = true;
    });

    try {
      // Use a more lightweight check - just check if printer service has cached connection info
      // without actually communicating with the printer
      Map<String, bool> connectionStatus = {'usb': false, 'bluetooth': false};

      // Only do a real check every 5 minutes, otherwise use cached status
      final now = DateTime.now();
      if (_lastPrinterCheck == null ||
          now.difference(_lastPrinterCheck!).inMinutes >= 5) {
        connectionStatus =
            await ThermalPrinterService().checkConnectionStatusOnly();
        _lastPrinterCheck = now;
        _cachedPrinterStatus = connectionStatus;
      } else {
        // Use cached status to avoid frequent printer communication
        connectionStatus =
            _cachedPrinterStatus ?? {'usb': false, 'bluetooth': false};
      }

      bool isConnected =
          connectionStatus['usb'] == true ||
          connectionStatus['bluetooth'] == true;

      if (mounted) {
        setState(() {
          _isPrinterConnected = isConnected;
          _isCheckingPrinter = false;
        });
      }
    } catch (e) {
      print('Error checking printer status: $e');
      if (mounted) {
        setState(() {
          _isPrinterConnected = false;
          _isCheckingPrinter = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _printerStatusTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void refreshOrders() {
    Provider.of<ActiveOrdersProvider>(context, listen: false).refreshOrders();
  }

  String _getCategoryIcon(String categoryName) {
    switch (categoryName.toUpperCase()) {
      case 'PIZZA':
        return 'assets/images/PizzasS.png';
      case 'SHAWARMAS':
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

  Widget _buildOrderSummaryContent(Order order) {
    final textStyle = const TextStyle(
      fontSize: 17,
      color: Colors.black,
      fontFamily: 'Poppins',
    );

    if (order.orderSource.toLowerCase() == 'epos') {
      final itemNames = order.items
          .map((item) => ' ${item.itemName}')
          .join(', ');
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          itemNames.isNotEmpty ? itemNames : 'No items',
          style: textStyle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.left,
        ),
      );
    } else if (order.orderSource.toLowerCase() == 'website') {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          order.displayAddressSummary,
          style: textStyle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.left,
        ),
      );
    }
    return Center(
      child: Text(
        order.displaySummary,
        style: textStyle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
    );
  }

  String _getDisplayOrderType(Order order) {
    String source = order.orderSource.toLowerCase();
    String type = order.orderType.toLowerCase();

    if (source == 'website') {
      return 'Web ${type == 'delivery' ? 'Delivery' : 'Pickup'}';
    } else if (source == 'epos') {
      if (type == 'delivery') {
        return 'POS Delivery';
      } else if (type == 'dinein') {
        return 'POS Dine-In';
      } else if (type == 'takeout') {
        return 'POS Takeout';
      } else {
        return 'POS Collection';
      }
    }
    return '${source.toUpperCase()} ${type.toUpperCase()}';
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

  // UPDATED METHOD WITH DEFAULT VALUE FILTERING (same as website screen)
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

      if (lines.isNotEmpty) {
        foundOptionsSyntax = true;
        optionsList = lines;

        // Find the first line that doesn't contain a colon and isn't a special topping (likely the item name)
        String foundItemName = '';
        for (var line in lines) {
          String lowerLine = line.toLowerCase();
          if (!line.contains(':') &&
              lowerLine != 'no salad' &&
              lowerLine != 'no sauce' &&
              lowerLine != 'no cream' &&
              lowerLine != 'meal') {
            foundItemName = line;
            break;
          }
        }

        if (foundItemName.isNotEmpty) {
          options['baseItemName'] = foundItemName;
        } else {
          options['baseItemName'] = description;
        }
      }
    }

    // If no options syntax found, it's a simple description like "Chocolate Milkshake"
    if (!foundOptionsSyntax) {
      options['baseItemName'] = description;
      options['hasOptions'] = false;
      return options;
    }

    // --- Combine default toppings and cheese from the FoodItem ---
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

      // Check for meal option
      if (lowerOption.contains('make it a meal') ||
          lowerOption.contains('meal') ||
          lowerOption == 'meal') {
        options['isMeal'] = true;
        anyNonDefaultOptionFound = true;
      }
      // Extract drink information
      else if (lowerOption.startsWith('drink:')) {
        String drinkValue = option.substring('drink:'.length).trim();
        if (drinkValue.isNotEmpty) {
          options['drink'] = drinkValue;
          anyNonDefaultOptionFound = true;
        }
      } else if (lowerOption.startsWith('size:')) {
        String sizeValue = option.substring('size:'.length).trim();
        if (sizeValue.isNotEmpty) {
          options['size'] = sizeValue;
          anyNonDefaultOptionFound = true;
        }
      } else if (lowerOption.startsWith('crust:')) {
        String crustValue = option.substring('crust:'.length).trim();
        if (crustValue.isNotEmpty) {
          options['crust'] = crustValue;
          anyNonDefaultOptionFound = true;
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
          anyNonDefaultOptionFound = true;
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
          List<String> filteredToppings =
              currentToppingsFromDescription.where((topping) {
                String trimmedToppingLower = topping.trim().toLowerCase();
                return !defaultToppingsAndCheese.contains(
                      trimmedToppingLower,
                    ) &&
                    ![
                      'none',
                      'no toppings',
                      'standard',
                      'default',
                    ].contains(trimmedToppingLower);
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
    }

    options['hasOptions'] = anyNonDefaultOptionFound;
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
          lowerPart.startsWith('crust:')) {
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

  @override
  Widget build(BuildContext context) {
    final activeOrdersProvider = Provider.of<ActiveOrdersProvider>(context);
    final List<Order> activeOrders = activeOrdersProvider.activeOrders;
    final bool isLoadingOrders = activeOrdersProvider.isLoading;
    final String? errorLoadingOrders = activeOrdersProvider.error;

    // Get screen dimensions for responsive design
    final screenWidth = MediaQuery.of(context).size.width;
    final isLargeScreen = screenWidth > 1200;

    if (_selectedOrder != null &&
        !activeOrders.any((o) => o.orderId == _selectedOrder!.orderId)) {
      _selectedOrder = null;
    }

    if (isLoadingOrders) {
      return const Center(child: CircularProgressIndicator());
    }
    if (errorLoadingOrders != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                errorLoadingOrders,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () => activeOrdersProvider.refreshOrders(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // Detailed order view (similar to website orders screen)
    if (_selectedOrder != null) {
      return Stack(
        children: [
          Padding(
            padding: EdgeInsets.all(isLargeScreen ? 20.0 : 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back button
                Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    icon: Image.asset(
                      'assets/images/bArrow.png',
                      width: isLargeScreen ? 35 : 30,
                      height: isLargeScreen ? 35 : 30,
                    ),
                    onPressed: () {
                      setState(() {
                        _selectedOrder = null;
                      });
                    },
                  ),
                ),

                // Order header information
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isLargeScreen ? 25.0 : 20.0,
                    vertical: isLargeScreen ? 8 : 5,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _selectedOrder!.orderType.toLowerCase() ==
                                        "delivery" &&
                                    _selectedOrder!.postalCode != null &&
                                    _selectedOrder!.postalCode!.isNotEmpty
                                ? '${_selectedOrder!.postalCode} '
                                : '',
                            style: TextStyle(
                              fontSize: isLargeScreen ? 19 : 17,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                          Text(
                            'Order no. ${_selectedOrder!.orderId}',
                            style: TextStyle(
                              fontSize: isLargeScreen ? 19 : 17,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        _selectedOrder!.customerName,
                        style: TextStyle(
                          fontSize: isLargeScreen ? 19 : 17,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      if (_selectedOrder!.orderType.toLowerCase() ==
                              "delivery" &&
                          _selectedOrder!.streetAddress != null &&
                          _selectedOrder!.streetAddress!.isNotEmpty)
                        Text(
                          _selectedOrder!.streetAddress!,
                          style: TextStyle(fontSize: isLargeScreen ? 20 : 18),
                        ),
                      if (_selectedOrder!.orderType.toLowerCase() ==
                              "delivery" &&
                          _selectedOrder!.city != null &&
                          _selectedOrder!.city!.isNotEmpty)
                        Text(
                          '${_selectedOrder!.city}, ${_selectedOrder!.postalCode ?? ''}',
                          style: TextStyle(fontSize: isLargeScreen ? 20 : 18),
                        ),
                      if (_selectedOrder!.phoneNumber != null &&
                          _selectedOrder!.phoneNumber!.isNotEmpty)
                        Text(
                          _selectedOrder!.phoneNumber!,
                          style: TextStyle(fontSize: isLargeScreen ? 20 : 18),
                        ),
                      if (_selectedOrder!.customerEmail != null &&
                          _selectedOrder!.customerEmail!.isNotEmpty)
                        Text(
                          _selectedOrder!.customerEmail!,
                          style: TextStyle(fontSize: isLargeScreen ? 20 : 18),
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

                // Items list with scrollbar
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
                        final item = _selectedOrder!.items[itemIndex];

                        // Enhanced option extraction
                        Map<String, dynamic> itemOptions =
                            _extractAllOptionsFromDescription(
                              item.description,
                              defaultFoodItemToppings:
                                  item.foodItem?.defaultToppings,
                              defaultFoodItemCheese:
                                  item.foodItem?.defaultCheese,
                            );

                        String? selectedSize = itemOptions['size'];
                        String? selectedCrust = itemOptions['crust'];
                        String? selectedBase = itemOptions['base'];
                        String? selectedDrink = itemOptions['drink'];
                        bool isMeal = itemOptions['isMeal'] ?? false;
                        List<String> toppings = itemOptions['toppings'] ?? [];
                        List<String> sauceDips = itemOptions['sauceDips'] ?? [];
                        String baseItemName =
                            itemOptions['baseItemName'] ?? item.itemName;
                        String displayItemName = item.itemName;
                        bool hasOptions = itemOptions['hasOptions'] ?? false;
                        String? extractedComment =
                            itemOptions['extractedComment'];

                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: isLargeScreen ? 15.0 : 12.0,
                          ),
                          child: Column(
                            children: [
                              Container(
                                padding: EdgeInsets.symmetric(
                                  vertical: isLargeScreen ? 12 : 10,
                                  horizontal: isLargeScreen ? 45 : 40,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      flex: 6,
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${item.quantity}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: isLargeScreen ? 38 : 34,
                                              fontFamily: 'Poppins',
                                            ),
                                          ),
                                          Expanded(
                                            child: Padding(
                                              padding: EdgeInsets.only(
                                                left: isLargeScreen ? 35 : 30,
                                                right: isLargeScreen ? 12 : 10,
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  if (hasOptions) ...[
                                                    // Show extracted base item name if it's different and meaningful
                                                    if (baseItemName !=
                                                            displayItemName &&
                                                        baseItemName
                                                            .trim()
                                                            .isNotEmpty &&
                                                        !baseItemName
                                                            .toLowerCase()
                                                            .contains(
                                                              'size:',
                                                            ) &&
                                                        !baseItemName
                                                            .toLowerCase()
                                                            .contains(
                                                              'crust:',
                                                            ) &&
                                                        !baseItemName
                                                            .toLowerCase()
                                                            .contains('base:'))
                                                      Text(
                                                        baseItemName,
                                                        style: TextStyle(
                                                          fontSize:
                                                              isLargeScreen
                                                                  ? 17
                                                                  : 15,
                                                          fontFamily: 'Poppins',
                                                          color: Colors.black,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                        overflow:
                                                            TextOverflow
                                                                .ellipsis,
                                                      ),

                                                    // Display Size (only if not default)
                                                    if (selectedSize != null)
                                                      Text(
                                                        'Size: $selectedSize',
                                                        style: TextStyle(
                                                          fontSize:
                                                              isLargeScreen
                                                                  ? 17
                                                                  : 15,
                                                          fontFamily: 'Poppins',
                                                          color: Colors.black,
                                                        ),
                                                        overflow:
                                                            TextOverflow
                                                                .ellipsis,
                                                      ),

                                                    // Display Crust (only if not default)
                                                    if (selectedCrust != null)
                                                      Text(
                                                        'Crust: $selectedCrust',
                                                        style: TextStyle(
                                                          fontSize:
                                                              isLargeScreen
                                                                  ? 17
                                                                  : 15,
                                                          fontFamily: 'Poppins',
                                                          color: Colors.black,
                                                        ),
                                                        overflow:
                                                            TextOverflow
                                                                .ellipsis,
                                                      ),

                                                    // Display Base (only if not default)
                                                    if (selectedBase != null)
                                                      Text(
                                                        'Base: $selectedBase',
                                                        style: TextStyle(
                                                          fontSize:
                                                              isLargeScreen
                                                                  ? 17
                                                                  : 15,
                                                          fontFamily: 'Poppins',
                                                          color: Colors.black,
                                                        ),
                                                        overflow:
                                                            TextOverflow
                                                                .ellipsis,
                                                      ),

                                                    // Display MEAL first if it's a meal
                                                    if (isMeal)
                                                      Text(
                                                        'MEAL',
                                                        style: TextStyle(
                                                          fontSize:
                                                              isLargeScreen
                                                                  ? 17
                                                                  : 15,
                                                          fontFamily: 'Poppins',
                                                          color: Colors.black,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                        overflow:
                                                            TextOverflow
                                                                .ellipsis,
                                                      ),

                                                    // Display drink information
                                                    if (selectedDrink != null &&
                                                        selectedDrink
                                                            .isNotEmpty)
                                                      Text(
                                                        'Drink: $selectedDrink',
                                                        style: TextStyle(
                                                          fontSize:
                                                              isLargeScreen
                                                                  ? 17
                                                                  : 15,
                                                          fontFamily: 'Poppins',
                                                          color: Colors.black,
                                                        ),
                                                        overflow:
                                                            TextOverflow
                                                                .ellipsis,
                                                      ),

                                                    // Display Toppings (only if not empty)
                                                    if (toppings.isNotEmpty)
                                                      Text(
                                                        'Extra Toppings: ${toppings.join(', ')}',
                                                        style: TextStyle(
                                                          fontSize:
                                                              isLargeScreen
                                                                  ? 17
                                                                  : 15,
                                                          fontFamily: 'Poppins',
                                                          color: Colors.black,
                                                        ),
                                                        maxLines: 3,
                                                        overflow:
                                                            TextOverflow
                                                                .ellipsis,
                                                      ),

                                                    // Display Sauce Dips (only if not empty)
                                                    if (sauceDips.isNotEmpty)
                                                      Text(
                                                        'Sauce Dips: ${sauceDips.join(', ')}',
                                                        style: TextStyle(
                                                          fontSize:
                                                              isLargeScreen
                                                                  ? 17
                                                                  : 15,
                                                          fontFamily: 'Poppins',
                                                          color: Colors.black,
                                                        ),
                                                        maxLines: 2,
                                                        overflow:
                                                            TextOverflow
                                                                .ellipsis,
                                                      ),
                                                  ] else ...[
                                                    // No structured options found, show raw description
                                                    Text(
                                                      item.description,
                                                      style: TextStyle(
                                                        fontSize:
                                                            isLargeScreen
                                                                ? 17
                                                                : 15,
                                                        fontFamily: 'Poppins',
                                                        color: Colors.black,
                                                        fontStyle:
                                                            FontStyle.normal,
                                                      ),
                                                      maxLines: 3,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ],

                                                  // Display item comment/notes if present
                                                  if (item.comment != null &&
                                                      item.comment!.isNotEmpty)
                                                    Text(
                                                      'Note: ${item.comment!}',
                                                      style: TextStyle(
                                                        fontSize:
                                                            isLargeScreen
                                                                ? 17
                                                                : 15,
                                                        fontFamily: 'Poppins',
                                                        color:
                                                            Colors.orange[700],
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                      maxLines: 3,
                                                      overflow:
                                                          TextOverflow.ellipsis,
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
                                      height: isLargeScreen ? 120 : 110,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 0,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(30),
                                        color: const Color(0xFFB2B2B2),
                                      ),
                                    ),

                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Container(
                                            width: isLargeScreen ? 100 : 90,
                                            height: isLargeScreen ? 74 : 64,
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            clipBehavior: Clip.hardEdge,
                                            child: Image.asset(
                                              _getCategoryIcon(item.itemType),
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                          SizedBox(
                                            height: isLargeScreen ? 10 : 8,
                                          ),
                                          Text(
                                            displayItemName,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: isLargeScreen ? 18 : 16,
                                              fontWeight: FontWeight.normal,
                                              fontFamily: 'Poppins',
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Comment section for extracted comments from description
                              if ((item.comment != null &&
                                      item.comment!.isNotEmpty) ||
                                  (extractedComment != null &&
                                      extractedComment.isNotEmpty))
                                Padding(
                                  padding: EdgeInsets.only(
                                    top: isLargeScreen ? 10.0 : 8.0,
                                  ),
                                  child: Container(
                                    width: double.infinity,
                                    padding: EdgeInsets.symmetric(
                                      vertical: isLargeScreen ? 10.0 : 8.0,
                                      horizontal: isLargeScreen ? 15.0 : 12.0,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFDF1C7),
                                      borderRadius: BorderRadius.circular(8.0),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'Comment: ${item.comment ?? extractedComment ?? ''}',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: isLargeScreen ? 18 : 16,
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

                // Bottom section with total and print button
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Payment Type:',
                          style: TextStyle(fontSize: isLargeScreen ? 20 : 18),
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
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: EdgeInsets.all(isLargeScreen ? 40 : 35),
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Total',
                                    style: TextStyle(
                                      fontSize: isLargeScreen ? 22 : 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: isLargeScreen ? 120 : 110),
                                  Text(
                                    '£${_selectedOrder!.orderTotalPrice.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: isLargeScreen ? 22 : 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                              if (_selectedOrder!.changeDue > 0) ...[
                                SizedBox(height: isLargeScreen ? 12 : 10),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Change Due',
                                      style: TextStyle(
                                        fontSize: isLargeScreen ? 22 : 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(width: isLargeScreen ? 50 : 40),
                                    Text(
                                      '£${_selectedOrder!.changeDue.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: isLargeScreen ? 22 : 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        SizedBox(width: isLargeScreen ? 25 : 20),

                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () async {
                              await _handlePrintingOrderReceipt();
                            },
                            child: Container(
                              padding: EdgeInsets.all(isLargeScreen ? 10 : 8),
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.asset(
                                    'assets/images/printer.png',
                                    width: isLargeScreen ? 65 : 58,
                                    height: isLargeScreen ? 65 : 58,
                                    color: Colors.white,
                                  ),
                                  SizedBox(height: isLargeScreen ? 6 : 4),
                                  Text(
                                    'Print Receipt',
                                    style: TextStyle(
                                      fontSize: isLargeScreen ? 17 : 15,
                                      fontWeight: FontWeight.bold,
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
                SizedBox(height: isLargeScreen ? 20 : 16),
              ],
            ),
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
      );
    } else if (activeOrders.isEmpty) {
      return const Center(
        child: Text(
          'No unpaid orders found.',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    } else {
      const double fixedBoxHeight = 50.0;

      return Column(
        children: [
          const SizedBox(height: 30),
          Padding(
            padding: const EdgeInsets.only(top: 10.0, bottom: 10.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3D9FF),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: const Text(
                    'Active Orders',
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3D9FF),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: const Text(
                    'Unpaid Orders',
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 60.0),
            child: Divider(height: 0, thickness: 2.5, color: Colors.grey),
          ),
          const SizedBox(height: 30),
          Expanded(
            child: ListView.builder(
              itemCount: activeOrders.length,
              itemBuilder: (context, index) {
                final order = activeOrders[index];
                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedOrder = order;
                      });
                    },
                    child: Card(
                      margin: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 8,
                      ),
                      elevation: 0,
                      color: Colors.transparent,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 0,
                          horizontal: 4.0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  flex: 4,
                                  child: Container(
                                    height: fixedBoxHeight,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 0,
                                      horizontal: 10.0,
                                    ),
                                    decoration: BoxDecoration(
                                      color: HexColor.fromHex('FFF6D4'),
                                      borderRadius: BorderRadius.circular(35),
                                    ),
                                    child: _buildOrderSummaryContent(order),
                                  ),
                                ),
                                const SizedBox(width: 20),
                                Expanded(
                                  flex: 2,
                                  child: Container(
                                    height: fixedBoxHeight,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 0,
                                      horizontal: 6.0,
                                    ),
                                    decoration: BoxDecoration(
                                      color: HexColor.fromHex('FFF6D4'),
                                      borderRadius: BorderRadius.circular(35),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      _getDisplayOrderType(order),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.normal,
                                        color: Colors.black,
                                        fontFamily: 'Poppins',
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }
  }
}
