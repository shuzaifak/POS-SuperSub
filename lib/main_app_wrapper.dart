// lib/main_app_wrapper.dart

import 'package:flutter/material.dart';
import 'package:epos/services/order_api_service.dart';
import 'package:epos/services/thermal_printer_service.dart';
import 'package:epos/models/order.dart';
import 'package:epos/models/cart_item.dart';
import 'package:epos/models/food_item.dart';
import 'package:epos/new_order_notification_widget.dart';
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

  // Change this line:
  final Set<int> _processingOrderIds =
      {}; // Changed from Set<String> to Set<int>

  @override
  void initState() {
    super.initState();
    _orderApiService = OrderApiService();

    _newOrderSubscription = _orderApiService.newOrderStream.listen((newOrder) {
      print(
        "MainAppWrapper: New order received from socket: ${newOrder.orderId}",
      );
      if ((newOrder.status.toLowerCase() == 'pending' ||
              newOrder.status.toLowerCase() == 'yellow') &&
          !_processingOrderIds.contains(newOrder.orderId)) {
        _addNewOrderNotification(newOrder);
      }
    });

    _orderApiService.connectionStatusStream.listen((isConnected) {
      print("MainAppWrapper: Socket connection status: $isConnected");
    });
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
        selectedOptions: null, // OrderItem doesn't have selectedOptions
        comment: orderItem.comment,
        pricePerUnit: pricePerUnit,
      );
    }).toList();
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

  void _handleAcceptOrder(Order order) async {
    print("MainAppWrapper: Accepting order ${order.orderId}");

    try {
      // First update the order status
      bool success = await OrderApiService.updateOrderStatus(
        order.orderId,
        'yellow',
      );

      if (success) {
        // Show success popup immediately
        _showMainWrapperPopup(
          'Order ${order.orderId} accepted.',
          type: PopupType.success,
        );

        // Wait a bit to ensure acceptance popup is visible before printer popup
        await Future.delayed(const Duration(milliseconds: 1500));

        // Print the receipt automatically after successful acceptance
        await _printOrderReceipt(order);

        // Refresh the orders
        if (mounted && context.mounted) {
          Provider.of<OrderProvider>(
            context,
            listen: false,
          ).fetchWebsiteOrders();
        }
      } else {
        _showMainWrapperPopup(
          'Failed to accept order ${order.orderId}.',
          type: PopupType.failure,
        );
      }
    } catch (e) {
      print('MainAppWrapper: Error in _handleAcceptOrder: $e');
      _showMainWrapperPopup(
        'Error accepting order ${order.orderId}: $e',
        type: PopupType.failure,
      );
    }
  }

  void _handleDeclineOrder(Order order) async {
    print("MainAppWrapper: Declining order ${order.orderId}");

    try {
      // Note: If orderId is int, ensure your API method `updateOrderStatus` can handle it.
      // If it expects a String, you'll need to convert order.orderId.toString() there.
      bool success = await OrderApiService.updateOrderStatus(
        order.orderId,
        'declined',
      ); // Potentially convert to String for API

      if (success) {
        _showMainWrapperPopup(
          'Order ${order.orderId} declined.',
          type: PopupType.success,
        );
      } else {
        _showMainWrapperPopup(
          'Failed to decline order ${order.orderId}.',
          type: PopupType.failure,
        );
      }
    } catch (e) {
      print('MainAppWrapper: Error in _handleDeclineOrder: $e');
      _showMainWrapperPopup(
        'Error declining order ${order.orderId}: $e',
        type: PopupType.failure,
      );
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
      child: Stack(
        children: [
          widget.child,

          if (_activeNewOrderNotifications.isNotEmpty)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
                child: Container(color: Colors.black.withOpacity(0.3)),
              ),
            ),

          ..._activeNewOrderNotifications.map((order) {
            return NewOrderNotificationWidget(
              key: ValueKey(order.orderId),
              order: order,
              onAccept: _handleAcceptOrder,
              onDecline: _handleDeclineOrder,
              onDismiss: () => _removeNewOrderNotification(order),
            );
          }).toList(),
        ],
      ),
    );
  }
}
