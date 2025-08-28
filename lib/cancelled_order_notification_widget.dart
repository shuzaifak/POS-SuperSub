// lib/cancelled_order_notification_widget.dart

import 'package:flutter/material.dart';
import 'package:epos/models/order.dart';
import 'package:epos/services/notification_audio_service.dart';

class CancelledOrderNotificationWidget extends StatefulWidget {
  final Order order;
  final VoidCallback onDismiss;

  const CancelledOrderNotificationWidget({
    Key? key,
    required this.order,
    required this.onDismiss,
  }) : super(key: key);

  @override
  State<CancelledOrderNotificationWidget> createState() =>
      _CancelledOrderNotificationWidgetState();
}

class _CancelledOrderNotificationWidgetState
    extends State<CancelledOrderNotificationWidget> {
  final NotificationAudioService _audioService = NotificationAudioService();

  @override
  void initState() {
    super.initState();
    // Play notification sound when cancel order popup appears
    _audioService.playCancelOrderSound();
  }

  @override
  Widget build(BuildContext context) {
    final double cardWidth = 450.0;
    final double cardHeight = 520.0;
    final double cardPadding = 16.0;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          color: Colors.red[50],
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              spreadRadius: 2,
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with cross icon
            Container(
              padding: EdgeInsets.symmetric(
                vertical: 10.0,
                horizontal: cardPadding,
              ),
              decoration: const BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 40),
                  Expanded(
                    child: Text(
                      'Order ${widget.order.orderId} Cancelled',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Poppins',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  GestureDetector(
                    onTap: widget.onDismiss,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Body content
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(cardPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cancelled message
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red[300]!, width: 1),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.cancel_outlined,
                            color: Colors.red,
                            size: 24,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'This order has been cancelled',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.red,
                                fontFamily: 'Poppins',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Order items
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ...widget.order.items
                                .map(
                                  (item) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                item.itemName,
                                                style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.normal,
                                                  color: Colors.black87,
                                                  fontFamily: 'Poppins',
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Text(
                                              '£${item.totalPrice.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.normal,
                                                color: Colors.black87,
                                                fontFamily: 'Poppins',
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          'Qty: ${item.quantity}',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.normal,
                                            color: Colors.black54,
                                            fontFamily: 'Poppins',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                            if (widget.order.items.isEmpty)
                              const Text(
                                'No Items',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.normal,
                                  color: Colors.black87,
                                  fontFamily: 'Poppins',
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),

                    // Divider
                    const Divider(color: Colors.red, thickness: 1),
                    const SizedBox(height: 15),

                    // Total section
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8.0,
                        horizontal: 10.0,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                              fontFamily: 'Poppins',
                            ),
                          ),
                          Text(
                            '£${widget.order.orderTotalPrice.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Customer info
                    Text(
                      'Customer: ${widget.order.customerName}',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black,
                        fontFamily: 'Poppins',
                      ),
                    ),
                    if (widget.order.phoneNumber != null &&
                        widget.order.phoneNumber!.isNotEmpty)
                      Text(
                        'Phone: ${widget.order.phoneNumber}',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.black,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    Text(
                      'Type: ${widget.order.orderType}',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black,
                        fontFamily: 'Poppins',
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Close button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: widget.onDismiss,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 5,
                        ),
                        child: const Text(
                          'CLOSE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.normal,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
