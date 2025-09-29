  // Helper method to calculate order card color based on elapsed time (bypasses cached statusColor)
  Color _calculateOrderCardColor(Order order) {
    print('🎨 _calculateOrderCardColor called for order ${order.orderId}');

    // First check if order is completed - completed orders should always be grey
    switch (order.status.toLowerCase()) {
      case 'blue':
      case 'completed':
      case 'delivered':
        print('🎨 Order ${order.orderId} is completed - returning GREY');
        return HexColor.fromHex('D6D6D6'); // Always return grey for completed orders
    }

    // TESTING: Force orders with odd IDs to be red to test if color changes work
    if (order.orderId % 2 == 1) {
      print('🔴 TESTING: Forcing order ${order.orderId} to RED for testing');
      return HexColor.fromHex('ffcaca'); // Force red for testing
    }

    // For non-completed orders, calculate time-based colors with fresh time calculation
    final now = UKTimeService.now();
    final timeDifference = now.difference(order.createdAt);
    final minutesPassed = timeDifference.inMinutes;

    print('🕐 Order ${order.orderId}: ${minutesPassed} minutes elapsed - Color should be ${minutesPassed < 30 ? "GREEN" : minutesPassed < 45 ? "YELLOW" : "RED"}');

    if (minutesPassed < 30) {
      return HexColor.fromHex('DEF5D4'); // Green shade - order just placed
    } else if (minutesPassed >= 30 && minutesPassed < 45) {
      return HexColor.fromHex('FFF6D4'); // Yellow shade - 30-45 minutes
    } else {
      return HexColor.fromHex('ffcaca'); // Red shade - 45+ minutes
    }
  }