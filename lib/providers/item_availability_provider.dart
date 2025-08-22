// lib/providers/item_availability_provider.dart

import 'package:flutter/material.dart';
import 'package:epos/models/food_item.dart';
import 'package:epos/services/api_service.dart';
import 'package:epos/services/custom_popup_service.dart';

class ItemAvailabilityProvider with ChangeNotifier {
  List<FoodItem> _allItems = [];
  bool _isLoading = false;
  String? _error;

  // Add a singleton pattern to ensure only one instance exists
  static ItemAvailabilityProvider? _instance;

  factory ItemAvailabilityProvider() {
    return _instance ??= ItemAvailabilityProvider._internal();
  }

  ItemAvailabilityProvider._internal() {
    // Initial fetch when the provider is created
    fetchItems();
  }

  List<FoodItem> get allItems => _allItems;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Method to fetch all menu items
  Future<void> fetchItems() async {
    _isLoading = true;
    _error = null;
    notifyListeners(); // Notify UI that loading has started

    try {
      final items = await ApiService.fetchMenuItems();
      _allItems = items;
      print(
        '✅ ItemAvailabilityProvider: Menu items fetched: ${_allItems.length}',
      );
    } catch (e) {
      _error = e.toString();
      print('❌ ItemAvailabilityProvider: Error fetching items: $_error');
    } finally {
      _isLoading = false;
      notifyListeners(); // Notify UI that loading has finished
    }
  }

  // Method to update item availability with immediate consistency
  Future<void> updateItemAvailability(
    BuildContext context,
    int itemId,
    bool newAvailability,
  ) async {
    final int itemIndex = _allItems.indexWhere((item) => item.id == itemId);
    if (itemIndex == -1) {
      CustomPopupService.show(
        context,
        'Item not found in list.',
        type: PopupType.failure,
      );
      return;
    }

    // Store original item for potential rollback
    final FoodItem originalItem = _allItems[itemIndex];

    // Immediate optimistic update - this will reflect everywhere instantly
    final FoodItem updatedItem = originalItem.copyWith(
      availability: newAvailability,
    );
    _allItems[itemIndex] = updatedItem;
    notifyListeners(); // This notifies ALL listeners immediately

    print(
      '🔄 Optimistically updated ${originalItem.name} availability to $newAvailability',
    );

    try {
      // Make API call
      await ApiService.setItemAvailability(itemId, newAvailability);

      print(
        '✅ Server confirmed ${originalItem.name} availability: $newAvailability',
      );

      CustomPopupService.show(
        context,
        '${originalItem.name} ${newAvailability ? 'enabled' : 'disabled'}!',
        type: PopupType.success,
      );

      // Optionally refresh from server to ensure consistency
      // Uncomment the line below if you want to sync with server after each update
      // await _refreshSingleItem(itemId);
    } catch (e) {
      print('❌ Failed to update ${originalItem.name} on server: $e');

      // Revert optimistic update on error
      _allItems[itemIndex] = originalItem;
      notifyListeners(); // This reverts the change everywhere

      CustomPopupService.show(
        context,
        'Failed to update ${originalItem.name} availability.',
        type: PopupType.failure,
      );
    }
  }

  // Method to manually refresh all items (useful for periodic syncing)
  Future<void> refresh() async {
    await fetchItems();
  }

  // Helper to get only offline items
  List<FoodItem> get offlineItems =>
      _allItems.where((item) => !item.availability).toList();

  // Helper to get only available items
  List<FoodItem> get availableItems =>
      _allItems.where((item) => item.availability).toList();

  // Method to get item by ID
  FoodItem? getItemById(int itemId) {
    try {
      return _allItems.firstWhere((item) => item.id == itemId);
    } catch (e) {
      return null;
    }
  }

  // Method to check if item is available
  bool isItemAvailable(int itemId) {
    final item = getItemById(itemId);
    return item?.availability ?? false;
  }
}
