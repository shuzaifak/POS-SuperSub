import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:async';
import '../models/order.dart';
import '../models/customer_search_model.dart';
import '../config/brand_info.dart';

class ShopStatusData {
  final bool shopOpen;

  ShopStatusData({required this.shopOpen});

  factory ShopStatusData.fromJson(Map<String, dynamic> json) {
    return ShopStatusData(shopOpen: json['shop_open'] ?? false);
  }
}

class OrderApiService {
  static const String _httpProxyUrl = 'https://corsproxy.io/?';
  static const String _backendBaseUrl =
      'https://thevillage-backend.onrender.com';

  static final OrderApiService _instance = OrderApiService._internal();
  factory OrderApiService() {
    return _instance;
  }
  OrderApiService._internal() {
    _initSocket();
  }

  late IO.Socket _socket;

  final _newOrderController = StreamController<Order>.broadcast();
  final _offersUpdatedController = StreamController<List<dynamic>>.broadcast();
  final _shopStatusUpdatedController =
  StreamController<ShopStatusData>.broadcast();
  final _connectionStatusController = StreamController<bool>.broadcast();
  final _acceptedOrderController = StreamController<Order>.broadcast();
  final _orderStatusOrDriverChangedController =
  StreamController<Map<String, dynamic>>.broadcast();

  Stream<Order> get newOrderStream => _newOrderController.stream;
  Stream<List<dynamic>> get offersUpdatedStream =>
      _offersUpdatedController.stream;
  Stream<ShopStatusData> get shopStatusUpdatedStream =>
      _shopStatusUpdatedController.stream;
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;
  Stream<Order> get acceptedOrderStream => _acceptedOrderController.stream;
  Stream<Map<String, dynamic>> get orderStatusOrDriverChangedStream =>
      _orderStatusOrDriverChangedController.stream;

  void addAcceptedOrder(Order order) {
    _acceptedOrderController.add(order);
  }

  void _initSocket() {
    _socket = IO.io(
      _backendBaseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableForceNewConnection()
          .enableAutoConnect()
          .setExtraHeaders({
        'withCredentials': 'true',
        'brand': BrandInfo.currentBrand,
        'x-client-id': BrandInfo.currentBrand,
      })
          .build(),
    );

    _socket.onConnect((_) {
      _connectionStatusController.add(true);
      _socket.emit('join_brand_room', {'brand': BrandInfo.currentBrand});
    });

    _socket.on('new_order', (data) {
      try {
        final orderData = Order.fromJson(data);
        _newOrderController.add(orderData);
      } catch (e) {
        // Error handling
      }
    });

    _socket.on('offers_updated', (data) {
      if (data is List) {
        _offersUpdatedController.add(data);
      }
    });

    _socket.on('shop_status_updated', (data) {
      try {
        final shopStatus = ShopStatusData.fromJson(data);
        _shopStatusUpdatedController.add(shopStatus);
      } catch (e) {

      }
    });

    _socket.on("order_status_or_driver_changed", (data) {
      if (data is Map<String, dynamic>) {
        _orderStatusOrDriverChangedController.add(data);
      }
    });

    _socket.onDisconnect((_) {
      _connectionStatusController.add(false);
    });

    _socket.onError((error) {
      _connectionStatusController.add(false);
    });

    _socket.onConnectError((err) => {});
    _socket.onReconnectError((err) => {});
    _socket.onReconnectAttempt((_) => {});
    _socket.onReconnect((attempt) => {});
    _socket.onReconnectFailed((_) => {});
  }

  void connectSocket() {
    if (!_socket.connected) {
      _socket.connect();
    }
  }

  void disconnectSocket() {
    _socket.disconnect();
  }

  void dispose() {
    _newOrderController.close();
    _offersUpdatedController.close();
    _shopStatusUpdatedController.close();
    _connectionStatusController.close();
    _acceptedOrderController.close();
    _orderStatusOrDriverChangedController.close();
    _socket.dispose();
  }

  static Uri _buildProxyUrl(String path) {
    return Uri.parse('$_httpProxyUrl$_backendBaseUrl$path');
  }

  static Future<List<Order>> fetchTodayOrders() async {
    final url = _buildProxyUrl('/orders/today');
    try {
      final response = await http.get(
        url,
        headers: BrandInfo.getDefaultHeaders(),
      );

      if (response.statusCode == 200) {
        List jsonResponse = json.decode(response.body);
        return jsonResponse
            .map((orderJson) => Order.fromJson(orderJson))
            .toList();
      } else {
        throw Exception(
          'Failed to load today\'s orders: ${response.statusCode} ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Error fetching today\'s orders: $e');
    }
  }

  static Future<bool> updateOrderStatus(int orderId, String newStatus) async {
    final url = _buildProxyUrl('/orders/update-status');

    String statusToSend;
    switch (newStatus.toLowerCase()) {
      case 'pending':
        statusToSend = 'yellow';
        break;
      case 'ready':
      case 'on its way':
      case 'preparing':
        statusToSend = 'green';
        break;
      case 'completed':
      case 'delivered':
        statusToSend = 'blue';
        break;
      default:
        statusToSend = newStatus.toLowerCase();
        break;
    }

    try {
      final response = await http.post(
        url,
        headers: BrandInfo.getDefaultHeaders(),
        body: jsonEncode(<String, dynamic>{
          'order_id': orderId,
          'status': statusToSend,
          'driver_id': null,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  static Future<CustomerSearchResponse?> searchCustomerByPhoneNumber(
      String phoneNumber,
      ) async {
    String cleanedPhoneNumber = phoneNumber.replaceAll(RegExp(r'\s+'), '');
    final url = _buildProxyUrl('/orders/search-customer');

    try {
      final response = await http.post(
        url,
        headers: BrandInfo.getDefaultHeaders(),
        body: jsonEncode(<String, dynamic>{'phone_number': cleanedPhoneNumber}),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        if (responseData.isNotEmpty) {
          return CustomerSearchResponse.fromJson(responseData);
        } else {
          return null;
        }
      } else if (response.statusCode == 404) {
        return null;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }
}
