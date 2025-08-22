// lib/widgets/receipt_preview_dialog.dart

import 'package:flutter/material.dart';
import 'package:epos/models/order.dart';
import 'package:epos/models/cart_item.dart';

class ReceiptPreviewDialog extends StatelessWidget {
  final Order order;
  final List<CartItem> cartItems;
  final double subtotal;

  const ReceiptPreviewDialog({
    Key? key,
    required this.order,
    required this.cartItems,
    required this.subtotal,
  }) : super(key: key);

  static Future<void> show(
    BuildContext context,
    Order order,
    List<CartItem> cartItems,
    double subtotal,
  ) async {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return ReceiptPreviewDialog(
          order: order,
          cartItems: cartItems,
          subtotal: subtotal,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    String receiptContent = _generateReceiptContent();

    return Dialog(
      child: Container(
        width: 400,
        height: 600,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Receipt Preview',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    receiptContent,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _generateReceiptContent() {
    StringBuffer content = StringBuffer();
    content.writeln('================================================');
    content.writeln('                RECEIPT PREVIEW                ');
    content.writeln('================================================');
    content.writeln('Order ID: ${order.orderId}');
    content.writeln('Order Type: ${order.orderType}');
    content.writeln('Date: ${DateTime.now().toString().split('.')[0]}');
    content.writeln('------------------------------------------------');

    if (order.customerName.isNotEmpty == true) {
      content.writeln('Customer: ${order.customerName}');
    }
    if (order.phoneNumber?.isNotEmpty == true) {
      content.writeln('Phone: ${order.phoneNumber}');
    }
    if (order.streetAddress?.isNotEmpty == true) {
      content.writeln('Address: ${order.streetAddress}');
      if (order.city?.isNotEmpty == true) {
        content.writeln('City: ${order.city}');
      }
      if (order.postalCode?.isNotEmpty == true) {
        content.writeln('Postal Code: ${order.postalCode}');
      }
    }
    content.writeln('------------------------------------------------');

    for (var item in cartItems) {
      content.writeln('${item.foodItem.name} x${item.quantity}');
      content.writeln(
        '  £${(item.pricePerUnit * item.quantity).toStringAsFixed(2)}',
      );

      if (item.selectedOptions != null && item.selectedOptions!.isNotEmpty) {
        for (var option in item.selectedOptions!) {
          content.writeln('  + $option');
        }
      }

      if (item.comment?.isNotEmpty == true) {
        content.writeln('  Note: ${item.comment}');
      }
      content.writeln('');
    }

    content.writeln('------------------------------------------------');
    content.writeln('Subtotal: £${subtotal.toStringAsFixed(2)}');
    content.writeln('TOTAL: £${order.orderTotalPrice.toStringAsFixed(2)}');

    if (order.changeDue > 0) {
      content.writeln('Change Due: £${order.changeDue.toStringAsFixed(2)}');
    }

    if (order.paymentType.isNotEmpty == true) {
      content.writeln('Payment: ${order.paymentType}');
    }

    if (order.orderExtraNotes?.isNotEmpty == true) {
      content.writeln('------------------------------------------------');
      content.writeln('Notes: ${order.orderExtraNotes}');
    }

    content.writeln('================================================');
    content.writeln('           Thank you for your order!           ');
    content.writeln('================================================');

    return content.toString();
  }
}
