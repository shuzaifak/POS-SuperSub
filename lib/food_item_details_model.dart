// lib/food_item_details_model.dart

import 'package:flutter/material.dart';
import 'package:epos/models/food_item.dart';
import 'package:epos/models/cart_item.dart';
import 'dart:math';
import 'package:epos/services/custom_popup_service.dart';

extension HexColor on Color {
  static Color fromHex(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }
}

extension StringCasingExtension on String {
  String capitalize() {
    if (isEmpty) return '';
    return '${this[0].toUpperCase()}${substring(1).toLowerCase()}';
  }
}

class FoodItemDetailsModal extends StatefulWidget {
  final FoodItem foodItem;
  final Function(CartItem) onAddToCart;
  final VoidCallback? onClose;
  final CartItem? initialCartItem;
  final bool isEditing;
  final List<FoodItem> allFoodItems;

  const FoodItemDetailsModal({
    super.key,
    required this.foodItem,
    required this.onAddToCart,
    this.onClose,
    this.initialCartItem,
    this.isEditing = false,
    required this.allFoodItems,
  });

  @override
  State<FoodItemDetailsModal> createState() => _FoodItemDetailsModalState();
}

class _FoodItemDetailsModalState extends State<FoodItemDetailsModal> {
  late double _calculatedPricePerUnit;
  int _quantity = 1;
  String _selectedOptionCategory =
      'Bread'; // Will be changed to 'Meat' for Wraps in initState

  String? _selectedSize;
  Set<String> _selectedToppings = {};
  Set<String> _selectedSauces = {};
  Set<String> _selectedExtraToppings = {};
  Set<String> _selectedClassicToppings = {}; // For JackedPotato

  bool _isInSizeSelectionMode = false;
  bool _sizeHasBeenSelected = false;

  final TextEditingController _reviewNotesController = TextEditingController();

  // Breakfast & Sandwich specific options
  String? _selectedBread;
  String? _selectedMeat; // Only one meat can be selected
  bool _doubleMeat = false;

  // Generic option lists for Breakfast and Sandwich categories
  final List<String> _breadOptions = [
    'White',
    'WholeMeal',
    'MultiGrain',
    'White Bread Cheese & Herbs',
  ];

  final List<String> _meatOptions = [
    'Plain Chicken',
    'Meat Ball',
    'Chicken Tikka',
    'Chicken Teriyaki',
    'Salami',
    'Ham',
    'Pepperoni',
    'Shredded Beef',
    'Chicken Shawarma',
    'Chicken Strips',
    'Bacon',
    'Turkey',
    'Tuna',
    'Vegetables',
  ];

  // Meat topping base prices (hidden from UI)
  final Map<String, double> _meatPrices = {
    'Chicken Tikka': 0.50,
    'Shredded Beef': 0.50,
    'Chicken Shawarma': 1.49,
    'Meat Ball': 0.50,
  };

  // Extra toppings with their prices and parent mapping
  final Map<String, Map<String, dynamic>> _extraToppingsData = {
    'Plain Chicken': {'price': 1.50, 'parent': 'Plain Chicken'},
    'Meat Ball': {'price': 2.00, 'parent': 'Meat Ball'},
    'Chicken Tikka': {'price': 2.00, 'parent': 'Chicken Tikka'},
    'Chicken Teriyaki': {'price': 1.50, 'parent': 'Chicken Teriyaki'},
    'Salami': {'price': 1.50, 'parent': 'Salami'},
    'Ham': {'price': 1.50, 'parent': 'Ham'},
    'Pepperoni': {'price': 1.50, 'parent': 'Pepperoni'},
    'Shredded Beef': {'price': 2.00, 'parent': 'Shredded Beef'},
    'Chicken Shawarma': {'price': 2.00, 'parent': 'Chicken Shawarma'},
    'Chicken Strips': {'price': 2.00, 'parent': 'Chicken Strips'},
    'Bacon': {'price': 1.50, 'parent': 'Bacon'},
    'Turkey': {'price': 1.50, 'parent': 'Turkey'},
    'Tuna': {'price': 1.50, 'parent': 'Tuna'},
  };

  final List<String> _toppingOptions = [
    'Lettuce',
    'Cucumber',
    'Tomato',
    'Red Onion',
    'Pickles',
    'Sweetcorn',
    'Mix Pepper',
    'Jalapeno',
    'Black Olives',
    'Cheese',
    'Extra Cheese',
  ];

  final List<String> _sauceOptions = [
    'Garlic',
    'Mayo',
    'Chipotle',
    'Honey Mustard',
    'Sweet Chilli',
    'Vegan Mayo',
    'PeriPeri',
    'BBQ',
    'Ketchup',
  ];

  // JackedPotato specific options
  final List<String> _classicToppingsOptions = [
    'Cheese',
    'Tuna',
    'Butter',
    'Beans',
  ];

  bool _isRemoveButtonPressed = false;
  bool _isAddButtonPressed = false;

  // Make it a Meal options
  bool _makeItAMeal = false;
  FoodItem? _selectedMealDrink;
  FoodItem? _selectedMealSide; // Either crisp or cookie
  String? _selectedSideType; // 'Crisp' or 'Cookie'
  List<FoodItem> _availableDrinks = [];
  List<FoodItem> _availableCrisps = [];
  List<FoodItem> _availableCookies = [];

  @override
  void initState() {
    super.initState();
    print('🔍 INIT STATE: Starting initialization for ${widget.foodItem.name}');

    // Initialize meal deal options for eligible categories
    if ([
      'Sandwiches',
      'Wraps',
      'Salads',
      'Bowls',
    ].contains(widget.foodItem.category)) {
      _initializeMealDealOptions();
    }

    if (widget.isEditing && widget.initialCartItem != null) {
      final CartItem item = widget.initialCartItem!;
      _quantity = item.quantity;
      _reviewNotesController.text = item.comment ?? '';

      print('🔍 EDITING MODE: Editing ${widget.foodItem.name}');
      print('🔍 Cart item options: ${item.selectedOptions}');

      // Restore meal deal selections
      if (item.isMealDeal) {
        _makeItAMeal = true;
        _selectedMealDrink = item.mealDealDrink;
        _selectedMealSide = item.mealDealSide;
        // Determine side type from the selected meal side
        if (_selectedMealSide != null) {
          if (_selectedMealSide!.category.toUpperCase() == 'CRISPS') {
            _selectedSideType = 'Crisp';
          } else if (_selectedMealSide!.category.toUpperCase() == 'DESSERTS') {
            _selectedSideType = 'Cookie';
          }
        }
      }

      // Parse selected options from the cart item
      if (item.selectedOptions != null) {
        for (var option in item.selectedOptions!) {
          String lowerOption = option.toLowerCase();

          if (lowerOption.startsWith('bread:')) {
            _selectedBread = option.split(':').last.trim();
          } else if (lowerOption.startsWith('classic toppings:')) {
            _selectedClassicToppings.addAll(
              option.split(':').last.trim().split(',').map((s) => s.trim()),
            );
          } else if (lowerOption.startsWith('meat:')) {
            // Only take the first meat when editing (single selection)
            final meats =
                option
                    .split(':')
                    .last
                    .trim()
                    .split(',')
                    .map((s) => s.trim())
                    .toList();
            if (meats.isNotEmpty) {
              _selectedMeat = meats.first;
            }
          } else if (lowerOption == 'double meat') {
            _doubleMeat = true;
          } else if (lowerOption.startsWith('toppings:')) {
            _selectedToppings.addAll(
              option.split(':').last.trim().split(',').map((s) => s.trim()),
            );
          } else if (lowerOption.startsWith('extra toppings:')) {
            _selectedExtraToppings.addAll(
              option.split(':').last.trim().split(',').map((s) => s.trim()),
            );
          } else if (lowerOption.startsWith('sauces:')) {
            _selectedSauces.addAll(
              option.split(':').last.trim().split(',').map((s) => s.trim()),
            );
          } else if (lowerOption.startsWith('size:')) {
            _selectedSize = option.split(':').last.trim();
            _sizeHasBeenSelected = true;
          }
        }
      }

      _isInSizeSelectionMode = false;
      _sizeHasBeenSelected =
          _selectedSize != null ||
          (widget.foodItem.price.keys.length == 1 &&
              widget.foodItem.price.isNotEmpty);

      // Set correct tab for categories without Bread when editing
      if (widget.foodItem.category == 'JackedPotato') {
        _selectedOptionCategory = 'Classic Toppings';
      } else if ([
        'Wraps',
        'Salads',
        'Bowls',
      ].contains(widget.foodItem.category)) {
        _selectedOptionCategory = 'Meat';
      } else if (widget.foodItem.category == 'Breakfast' ||
          widget.foodItem.category == 'Sandwiches') {
        _selectedOptionCategory = 'Bread';
      }
    } else {
      // Set default bread selection for Breakfast and Sandwich categories
      if ((widget.foodItem.category == 'Breakfast' ||
              widget.foodItem.category == 'Sandwiches') &&
          _breadOptions.isNotEmpty) {
        _selectedBread = _breadOptions.first; // Default to 'White'
      }

      // Pre-select Bacon for items with "bacon" in their name
      if (widget.foodItem.name.toLowerCase().contains('bacon')) {
        _selectedMeat = 'Bacon';
      }

      // Pre-select Chicken Strip for items with "chicken strip" in their name
      if (widget.foodItem.name.toLowerCase().contains('chicken strip')) {
        _selectedMeat = 'Chicken Strip';
      }

      // Pre-select Chicken Tikka for items with "chicken tikka" in their name
      if (widget.foodItem.name.toLowerCase().contains('chicken tikka')) {
        _selectedMeat = 'Chicken Tikka';
      }

      // Pre-select Chicken Teriyaki for items with "chicken teriyaki" in their name
      if (widget.foodItem.name.toLowerCase().contains('chicken teriyaki')) {
        _selectedMeat = 'Chicken Teriyaki';
      }

      // Pre-select Ham for items with "ham" in their name
      if (widget.foodItem.name.toLowerCase().contains('ham')) {
        _selectedMeat = 'Ham';
      }

      // Pre-select Meat Ball for items with "meatball" in their name
      if (widget.foodItem.name.toLowerCase().contains('meatball')) {
        _selectedMeat = 'Meat Ball';
      }

      // Pre-select Pepperoni for items with "pepperoni" in their name
      if (widget.foodItem.name.toLowerCase().contains('pepperoni')) {
        _selectedMeat = 'Pepperoni';
      }

      // Pre-select Plain Chicken for items with "plain chicken" in their name
      if (widget.foodItem.name.toLowerCase().contains('plain chicken')) {
        _selectedMeat = 'Plain Chicken';
      }

      // Pre-select Salami for items with "salami" in their name
      if (widget.foodItem.name.toLowerCase().contains('salami')) {
        _selectedMeat = 'Salami';
      }

      // Pre-select Chicken Shawarma for items with "shawarma" in their name
      if (widget.foodItem.name.toLowerCase().contains('shawarma')) {
        _selectedMeat = 'Chicken Shawarma';
      }

      // Pre-select Shredded Beef for items with "shredded beef" in their name
      if (widget.foodItem.name.toLowerCase().contains('shredded beef')) {
        _selectedMeat = 'Shredded Beef';
      }

      // Pre-select Tuna for items with "tuna" in their name
      if (widget.foodItem.name.toLowerCase().contains('tuna')) {
        _selectedMeat = 'Tuna';
      }

      // Pre-select Turkey for items with "turkey" in their name
      if (widget.foodItem.name.toLowerCase().contains('turkey')) {
        _selectedMeat = 'Turkey';
      }

      // Pre-select Vegetables for items with "vegetables" in their name
      if (widget.foodItem.name.toLowerCase().contains('vegetables')) {
        _selectedMeat = 'Vegetables';
      }

      // For JackedPotato, default to 'Classic Toppings' tab
      if (widget.foodItem.category == 'JackedPotato') {
        _selectedOptionCategory = 'Classic Toppings';
      }
      // For Wraps, Salads, and Bowls, default to 'Meat' tab (no bread needed)
      else if ([
        'Wraps',
        'Salads',
        'Bowls',
      ].contains(widget.foodItem.category)) {
        _selectedOptionCategory = 'Meat';
      }

      bool requiresSizeSelection = widget.foodItem.price.keys.length > 1;

      if (requiresSizeSelection) {
        _isInSizeSelectionMode = true;
        _selectedSize = null;
      } else {
        if (widget.foodItem.price.keys.length == 1 &&
            widget.foodItem.price.isNotEmpty) {
          _selectedSize = widget.foodItem.price.keys.first;
          _sizeHasBeenSelected = true;
        }
        _isInSizeSelectionMode = false;
      }
    }

    _calculatedPricePerUnit = _calculatePricePerUnit();
  }

  void _initializeMealDealOptions() {
    // Filter drinks from SOFTDRINKS category, excluding Red Bull
    _availableDrinks =
        widget.allFoodItems
            .where(
              (item) =>
                  item.category.toUpperCase() == 'SOFTDRINKS' &&
                  !item.name.toUpperCase().contains('RED BULL'),
            )
            .toList();

    // Filter crisps from CRISPS category
    _availableCrisps =
        widget.allFoodItems
            .where((item) => item.category.toUpperCase() == 'CRISPS')
            .toList();

    // Filter cookies from DESSERTS category (assuming cookies are in desserts)
    // You may need to adjust this filter based on how cookies are categorized
    _availableCookies =
        widget.allFoodItems
            .where(
              (item) =>
                  item.category.toUpperCase() == 'DESSERTS' &&
                  item.name.toUpperCase().contains('COOKIE'),
            )
            .toList();
  }

  @override
  void dispose() {
    _reviewNotesController.dispose();
    super.dispose();
  }

  double _calculatePricePerUnit() {
    debugPrint("--- Calculating Price for ${widget.foodItem.name} ---");
    debugPrint("Food Item Price Map: ${widget.foodItem.price}");
    debugPrint("Selected Size: $_selectedSize");

    double price = 0.0;

    // Get base price from size
    if (_selectedSize != null &&
        widget.foodItem.price.containsKey(_selectedSize)) {
      price = widget.foodItem.price[_selectedSize] ?? 0.0;
    } else if (widget.foodItem.price.keys.length == 1 &&
        widget.foodItem.price.isNotEmpty) {
      price = widget.foodItem.price.values.first;
    } else {
      debugPrint("No valid size selected or price not found");
      return 0.0;
    }

    debugPrint("Initial price: $price");

    // Breakfast, Sandwich, Wraps, Salads, Bowls and JackedPotato specific pricing
    if ([
      'Breakfast',
      'Sandwiches',
      'Wraps',
      'Salads',
      'Bowls',
      'JackedPotato',
    ].contains(widget.foodItem.category)) {
      // Add meat topping base cost (hidden price) - not for JackedPotato
      if (widget.foodItem.category != 'JackedPotato' &&
          _selectedMeat != null &&
          _meatPrices.containsKey(_selectedMeat)) {
        final meatPrice = _meatPrices[_selectedMeat]!;
        price += meatPrice;
        debugPrint(
          "Added $_selectedMeat cost: £${meatPrice.toStringAsFixed(2)}",
        );
      }

      // Add extra toppings costs
      for (var extraTopping in _selectedExtraToppings) {
        if (_extraToppingsData.containsKey(extraTopping)) {
          final toppingPrice =
              _extraToppingsData[extraTopping]!['price'] as double;
          price += toppingPrice;
          debugPrint(
            "Added $extraTopping cost: £${toppingPrice.toStringAsFixed(2)}",
          );
        }
      }

      // Add double meat cost - not for JackedPotato
      if (widget.foodItem.category != 'JackedPotato' && _doubleMeat) {
        price += 1.50;
        debugPrint("Added Double Meat cost: £1.50");
      }

      // Add extra cheese cost
      if (_selectedToppings.contains('Extra Cheese')) {
        price += 0.50;
        debugPrint("Added Extra Cheese cost: £0.50");
      }
    }

    // Make it a Meal adds £1.50
    if (_makeItAMeal) {
      price += 1.50;
      debugPrint("Added Make it a Meal cost: £1.50");
    }

    debugPrint("Final price: $price");
    return price;
  }

  void _updatePriceDisplay() {
    setState(() {
      _calculatedPricePerUnit = _calculatePricePerUnit();
    });
  }

  void _closeModal() {
    widget.onClose?.call();
  }

  void _onSizeSelected(String size) {
    setState(() {
      _selectedSize = size;
      _sizeHasBeenSelected = true;
      _isInSizeSelectionMode = false;
      _updatePriceDisplay();
    });
  }

  void _changeSize() {
    setState(() {
      _isInSizeSelectionMode = true;
    });
  }

  void _confirmSelection() {
    // Validation for Breakfast and Sandwich categories (Wraps don't need bread)
    if (widget.foodItem.category == 'Breakfast' ||
        widget.foodItem.category == 'Sandwiches') {
      if (_selectedBread == null) {
        CustomPopupService.show(
          context,
          "Please select bread type",
          type: PopupType.failure,
        );
        return;
      }
    }

    // Size validation
    if (widget.foodItem.price.keys.length > 1 && _selectedSize == null) {
      CustomPopupService.show(
        context,
        "Please select a size before adding to cart",
        type: PopupType.failure,
      );
      return;
    }

    // Make it a Meal validation
    if (_makeItAMeal) {
      if (_selectedMealDrink == null) {
        CustomPopupService.show(
          context,
          "Please select a drink for your meal deal",
          type: PopupType.failure,
        );
        return;
      }
      if (_selectedMealSide == null) {
        CustomPopupService.show(
          context,
          "Please select a crisp or cookie for your meal deal",
          type: PopupType.failure,
        );
        return;
      }
    }

    final List<String> selectedOptions = [];

    // Add size if applicable
    if (_selectedSize != null && widget.foodItem.price.keys.length > 1) {
      selectedOptions.add('Size: $_selectedSize');
    }

    // Breakfast, Sandwich, Wraps, Salads, Bowls, and JackedPotato specific options
    if ([
      'Breakfast',
      'Sandwiches',
      'Wraps',
      'Salads',
      'Bowls',
      'JackedPotato',
    ].contains(widget.foodItem.category)) {
      // Bread only for Breakfast and Sandwiches (not Wraps, Salads, Bowls, or JackedPotato)
      if ((widget.foodItem.category == 'Breakfast' ||
              widget.foodItem.category == 'Sandwiches') &&
          _selectedBread != null) {
        selectedOptions.add('Bread: $_selectedBread');
      }

      // Classic Toppings for JackedPotato
      if (widget.foodItem.category == 'JackedPotato' &&
          _selectedClassicToppings.isNotEmpty) {
        selectedOptions.add(
          'Classic Toppings: ${_selectedClassicToppings.join(', ')}',
        );
      }

      if (_selectedMeat != null) {
        selectedOptions.add('Meat: $_selectedMeat');
      }

      if (_doubleMeat && widget.foodItem.category != 'JackedPotato') {
        selectedOptions.add('Double Meat');
      }

      if (_selectedToppings.isNotEmpty) {
        selectedOptions.add('Toppings: ${_selectedToppings.join(', ')}');
      }

      if (_selectedExtraToppings.isNotEmpty) {
        selectedOptions.add(
          'Extra Toppings: ${_selectedExtraToppings.join(', ')}',
        );
      }

      if (_selectedSauces.isNotEmpty) {
        selectedOptions.add('Sauces: ${_selectedSauces.join(', ')}');
      }
    }

    // Make it a Meal options
    if (_makeItAMeal) {
      selectedOptions.add('Make it a Meal');
      // Add drink and side to selectedOptions for printing
      if (_selectedMealDrink != null) {
        selectedOptions.add('Drink: ${_selectedMealDrink!.name}');
      }
      if (_selectedSideType != null) {
        selectedOptions.add('Side: $_selectedSideType');
      }
    }

    final String userComment = _reviewNotesController.text.trim();

    print('🔍 CREATING CARTITEM FOR ${widget.foodItem.name}');
    print('🔍 selectedOptions = $selectedOptions');

    final cartItem = CartItem(
      foodItem: widget.foodItem,
      quantity: _quantity,
      selectedOptions: selectedOptions.isEmpty ? null : selectedOptions,
      comment: userComment.isNotEmpty ? userComment : null,
      pricePerUnit: _calculatedPricePerUnit,
      isMealDeal: _makeItAMeal,
      mealDealDrink: _selectedMealDrink,
      mealDealSide: _selectedMealSide,
      mealDealSideType: _selectedSideType, // Pass the type (Crisp/Cookie)
    );

    print(
      '🔍 CARTITEM CREATED WITH selectedOptions: ${cartItem.selectedOptions}',
    );
    widget.onAddToCart(cartItem);

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        widget.onClose?.call();
      }
    });
  }

  Widget _buildOptionButton({
    required String title,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: isActive ? Colors.grey[100] : Colors.black,
        foregroundColor: isActive ? Colors.black : Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: isActive ? 4 : 2,
      ),
      child: Text(
        title,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: isActive ? Colors.black : Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.normal,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  String _getDisplaySize(String size) {
    switch (size.toLowerCase()) {
      case 'regular':
        return 'Reg';
      case 'large':
        return 'Lrg';
      case 'default':
        return 'Def';
      default:
        final parts = size.split(' ');
        if (parts.isNotEmpty) {
          return parts.first;
        }
        return size;
    }
  }

  @override
  Widget build(BuildContext context) {
    final double modalWidth = min(
      MediaQuery.of(context).size.width * 0.8,
      1500.0,
    );

    bool canConfirmSelection = true;

    // Breakfast & Sandwich validation
    if ((widget.foodItem.category == 'Breakfast' ||
            widget.foodItem.category == 'Sandwiches') &&
        _selectedBread == null) {
      canConfirmSelection = false;
    }

    // Size validation
    if (widget.foodItem.price.keys.length > 1 && _selectedSize == null) {
      canConfirmSelection = false;
    }

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        width: modalWidth,
        constraints: BoxConstraints(
          maxWidth: 1500,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade100, width: 1.0),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              decoration: const BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left: Selected size
                  Expanded(
                    flex: 1,
                    child:
                        _sizeHasBeenSelected &&
                                _selectedSize != null &&
                                !_isInSizeSelectionMode
                            ? Row(
                              children: [
                                InkWell(
                                  onTap: _changeSize,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 22,
                                      vertical: 18,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'Size',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 15),
                                InkWell(
                                  onTap: _changeSize,
                                  child: Container(
                                    width: 73,
                                    height: 73,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        _getDisplaySize(_selectedSize!),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize:
                                              _getDisplaySize(
                                                        _selectedSize!,
                                                      ).length >
                                                      5
                                                  ? 18
                                                  : 22,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                            : Container(),
                  ),

                  // Center: Item name
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        widget.foodItem.name.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 25),

                  // Right: Quantity controls
                  Expanded(
                    flex: 1,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (_sizeHasBeenSelected &&
                            !_isInSizeSelectionMode) ...[
                          InkWell(
                            onTapDown:
                                (_) => setState(
                                  () => _isRemoveButtonPressed = true,
                                ),
                            onTapUp:
                                (_) => setState(
                                  () => _isRemoveButtonPressed = false,
                                ),
                            onTapCancel:
                                () => setState(
                                  () => _isRemoveButtonPressed = false,
                                ),
                            onTap: () {
                              setState(() {
                                if (_quantity > 1) _quantity--;
                                _updatePriceDisplay();
                              });
                            },
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color:
                                    _isRemoveButtonPressed
                                        ? Colors.grey[100]
                                        : Colors.black,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.grey[100]!,
                                  width: 4,
                                ),
                              ),
                              child: const Icon(
                                Icons.remove,
                                color: Colors.white,
                                size: 35,
                              ),
                            ),
                          ),
                          Container(
                            width: 60,
                            height: 50,
                            margin: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: Colors.grey[100]!),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '$_quantity',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          InkWell(
                            onTapDown:
                                (_) =>
                                    setState(() => _isAddButtonPressed = true),
                            onTapUp:
                                (_) =>
                                    setState(() => _isAddButtonPressed = false),
                            onTapCancel:
                                () =>
                                    setState(() => _isAddButtonPressed = false),
                            onTap: () {
                              setState(() {
                                _quantity++;
                                _updatePriceDisplay();
                              });
                            },
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color:
                                    _isAddButtonPressed
                                        ? Colors.grey[100]
                                        : Colors.black,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.grey[100]!,
                                  width: 4,
                                ),
                              ),
                              child: const Icon(
                                Icons.add,
                                color: Colors.white,
                                size: 35,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  InkWell(
                    onTap: _closeModal,
                    child: const Text(
                      '×',
                      style: TextStyle(color: Colors.white, fontSize: 60),
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (_isInSizeSelectionMode) ...[
                      _buildSizeSelectionSection(),
                    ] else ...[
                      if ([
                        'Breakfast',
                        'Sandwiches',
                        'Wraps',
                        'Salads',
                        'Bowls',
                        'JackedPotato',
                      ].contains(widget.foodItem.category)) ...[
                        _buildCustomizableOptions(),
                      ] else ...[
                        // For other categories (Sides, Drinks, Desserts, etc.), just show Review Note
                        _buildReviewNoteSection(),
                      ],
                    ],
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border(top: BorderSide(color: Colors.grey[100]!)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total: £${(_calculatedPricePerUnit * _quantity).toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: _closeModal,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[100],
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 18,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 15),
                      ElevatedButton(
                        onPressed:
                            canConfirmSelection ? _confirmSelection : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              canConfirmSelection ? Colors.black : Colors.grey,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 18,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          widget.isEditing ? 'Update Cart' : 'Add to Cart',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSizeSelectionSection() {
    return Container(
      height: MediaQuery.of(context).size.height * 0.5,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 18),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Size',
              style: TextStyle(
                color: Colors.white,
                fontSize: 42,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Wrap(
            spacing: 15,
            runSpacing: 15,
            alignment: WrapAlignment.center,
            children:
                widget.foodItem.price.keys.map((sizeKey) {
                  final bool isActive = _selectedSize == sizeKey;
                  final String displayedText = _getDisplaySize(sizeKey);

                  return SizedBox(
                    width: 110,
                    height: 110,
                    child: ElevatedButton(
                      onPressed: () => _onSizeSelected(sizeKey),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            isActive ? Colors.grey[100] : Colors.black,
                        foregroundColor: isActive ? Colors.black : Colors.white,
                        shape: const CircleBorder(
                          side: BorderSide(color: Colors.white, width: 4),
                        ),
                        padding: EdgeInsets.zero,
                      ),
                      child: Text(
                        displayedText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: displayedText.length > 5 ? 20 : 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomizableOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category tabs
        _buildCategoryTabs(),
        const SizedBox(height: 20),

        // Content based on selected category
        _buildCategoryContent(),

        const SizedBox(height: 30),

        // Make it a Meal option (for Sandwiches, Wraps, Salads, Bowls)
        if ([
          'Sandwiches',
          'Wraps',
          'Salads',
          'Bowls',
        ].contains(widget.foodItem.category))
          _buildMakeItAMealOption(),

        if ([
          'Sandwiches',
          'Wraps',
          'Salads',
          'Bowls',
        ].contains(widget.foodItem.category))
          const SizedBox(height: 30),

        // Review Note section
        _buildReviewNoteSection(),
      ],
    );
  }

  Widget _buildCategoryTabs() {
    // Define tabs based on category
    final List<String> categories;
    if (widget.foodItem.category == 'JackedPotato') {
      categories = ['Classic Toppings', 'Extra Toppings', 'Toppings', 'Sauces'];
    } else if ([
      'Wraps',
      'Salads',
      'Bowls',
    ].contains(widget.foodItem.category)) {
      categories = ['Meat', 'Toppings', 'Sauces'];
    } else {
      categories = ['Bread', 'Meat', 'Toppings', 'Sauces'];
    }

    return Row(
      children: List.generate(categories.length, (index) {
        final category = categories[index];
        final bool isSelected = _selectedOptionCategory == category;

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              left: 4.0,
              right: index == categories.length - 1 ? 0 : 4.0,
            ),
            child: InkWell(
              onTap: () => setState(() => _selectedOptionCategory = category),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.grey[100] : Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  category,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isSelected ? Colors.black : Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildCategoryContent() {
    switch (_selectedOptionCategory) {
      case 'Bread':
        return _buildBreadSelection();
      case 'Meat':
        return _buildMeatSelection();
      case 'Classic Toppings':
        return _buildClassicToppingsSelection();
      case 'Extra Toppings':
        return _buildExtraToppingsSelectionForJackedPotato();
      case 'Toppings':
        return _buildToppingsSelection();
      case 'Sauces':
        return _buildSaucesSelection();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildBreadSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Bread:',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 15),
        LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            final buttonWidth =
                (availableWidth - 24) / 3; // 24 = spacing (12 * 2)
            return Wrap(
              spacing: 12,
              runSpacing: 15,
              children:
                  _breadOptions.map((bread) {
                    final bool isActive = _selectedBread == bread;
                    return SizedBox(
                      width: buttonWidth,
                      child: _buildOptionButton(
                        title: bread,
                        isActive: isActive,
                        onTap: () => setState(() => _selectedBread = bread),
                      ),
                    );
                  }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMeatSelection() {
    final bool hasMeatSelected = _selectedMeat != null;

    // Check if item name contains "bacon" (case-insensitive)
    final bool isBaconItem = widget.foodItem.name.toLowerCase().contains(
      'bacon',
    );

    // Check if item name contains "chicken strip" (case-insensitive)
    final bool isChickenStripItem = widget.foodItem.name.toLowerCase().contains(
      'chicken strip',
    );

    // Check if item name contains "chicken tikka" (case-insensitive)
    final bool isChickenTikkaItem = widget.foodItem.name.toLowerCase().contains(
      'chicken tikka',
    );

    // Check if item name contains "chicken teriyaki" (case-insensitive)
    final bool isChickenTeriyakiItem = widget.foodItem.name
        .toLowerCase()
        .contains('chicken teriyaki');

    // Check if item name contains "ham" (case-insensitive)
    final bool isHamItem = widget.foodItem.name.toLowerCase().contains('ham');

    // Check if item name contains "meatball" (case-insensitive)
    final bool isMeatballItem = widget.foodItem.name.toLowerCase().contains(
      'meatball',
    );

    // Check if item name contains "pepperoni" (case-insensitive)
    final bool isPepperoniItem = widget.foodItem.name.toLowerCase().contains(
      'pepperoni',
    );

    // Check if item name contains "plain chicken" (case-insensitive)
    final bool isPlainChickenItem = widget.foodItem.name.toLowerCase().contains(
      'plain chicken',
    );

    // Check if item name contains "salami" (case-insensitive)
    final bool isSalamiItem = widget.foodItem.name.toLowerCase().contains(
      'salami',
    );

    // Check if item name contains "shawarma" (case-insensitive)
    final bool isShawarmaItem = widget.foodItem.name.toLowerCase().contains(
      'shawarma',
    );

    // Check if item name contains "shredded beef" (case-insensitive)
    final bool isShreddedBeefItem = widget.foodItem.name.toLowerCase().contains(
      'shredded beef',
    );

    // Check if item name contains "tuna" (case-insensitive)
    final bool isTunaItem = widget.foodItem.name.toLowerCase().contains('tuna');

    // Check if item name contains "turkey" (case-insensitive)
    final bool isTurkeyItem = widget.foodItem.name.toLowerCase().contains(
      'turkey',
    );

    // Check if item name contains "vegetables" (case-insensitive)
    final bool isVegetablesItem = widget.foodItem.name.toLowerCase().contains(
      'vegetables',
    );

    // If bacon item, only show Bacon in meat options
    // If chicken strip item, only show Chicken Strip in meat options
    // If chicken tikka item, only show Chicken Tikka in meat options
    // If chicken teriyaki item, only show Chicken Teriyaki in meat options
    // If ham item, only show Ham in meat options
    // If meatball item, only show Meat Ball in meat options
    // If pepperoni item, only show Pepperoni in meat options
    // If plain chicken item, only show Plain Chicken in meat options
    // If salami item, only show Salami in meat options
    // If shawarma item, only show Chicken Shawarma in meat options
    // If shredded beef item, only show Shredded Beef in meat options
    // If tuna item, only show Tuna in meat options
    // If turkey item, only show Turkey in meat options
    // If vegetables item, only show Vegetables in meat options
    final List<String> displayedMeatOptions =
        isBaconItem
            ? ['Bacon']
            : isChickenStripItem
            ? ['Chicken Strip']
            : isChickenTikkaItem
            ? ['Chicken Tikka']
            : isChickenTeriyakiItem
            ? ['Chicken Teriyaki']
            : isHamItem
            ? ['Ham']
            : isMeatballItem
            ? ['Meat Ball']
            : isPepperoniItem
            ? ['Pepperoni']
            : isPlainChickenItem
            ? ['Plain Chicken']
            : isSalamiItem
            ? ['Salami']
            : isShawarmaItem
            ? ['Chicken Shawarma']
            : isShreddedBeefItem
            ? ['Shredded Beef']
            : isTunaItem
            ? ['Tuna']
            : isTurkeyItem
            ? ['Turkey']
            : isVegetablesItem
            ? ['Vegetables']
            : _meatOptions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Meat Topping:',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 15),
        LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            final buttonWidth =
                (availableWidth - 24) / 3; // 24 = spacing (12 * 2)
            return Wrap(
              spacing: 12,
              runSpacing: 15,
              children:
                  displayedMeatOptions.map((meat) {
                    final bool isActive = _selectedMeat == meat;
                    return SizedBox(
                      width: buttonWidth,
                      child: _buildOptionButton(
                        title: meat, // No price shown
                        isActive: isActive,
                        onTap: () {
                          setState(() {
                            if (isActive) {
                              // For bacon, chicken strip, chicken tikka, chicken teriyaki, or ham items, don't allow deselection
                              if (!isBaconItem &&
                                  !isChickenStripItem &&
                                  !isChickenTikkaItem &&
                                  !isChickenTeriyakiItem &&
                                  !isHamItem) {
                                // Deselect meat
                                _selectedMeat = null;
                                // Remove all extra toppings when meat is deselected
                                _selectedExtraToppings.clear();
                              }
                            } else {
                              // Select only one meat at a time
                              _selectedMeat = meat;
                              // Keep all selected extra toppings (no need to clear)
                            }
                            _updatePriceDisplay();
                          });
                        },
                      ),
                    );
                  }).toList(),
            );
          },
        ),
        const SizedBox(height: 20),

        // Extra Toppings section (always displayed, disabled when no meat selected)
        const SizedBox(height: 30),
        Text(
          'Extra Toppings:',
          style: TextStyle(
            color: hasMeatSelected ? Colors.white : Colors.grey,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 15),
        LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            final buttonWidth = (availableWidth - 24) / 3;

            return Wrap(
              spacing: 12,
              runSpacing: 15,
              children:
                  _extraToppingsData.entries.map((entry) {
                    final extraName = entry.key;
                    final bool isActive = _selectedExtraToppings.contains(
                      extraName,
                    );
                    final price = entry.value['price'] as double;
                    final bool isClickable =
                        hasMeatSelected; // Enable all extra toppings when any meat is selected

                    return SizedBox(
                      width: buttonWidth,
                      child: Opacity(
                        opacity: isClickable ? 1.0 : 0.4,
                        child: _buildOptionButton(
                          title: '$extraName (+£${price.toStringAsFixed(2)})',
                          isActive: isActive,
                          onTap:
                              isClickable
                                  ? () {
                                    setState(() {
                                      if (isActive) {
                                        _selectedExtraToppings.remove(
                                          extraName,
                                        );
                                      } else {
                                        _selectedExtraToppings.add(extraName);
                                      }
                                      _updatePriceDisplay();
                                    });
                                  }
                                  : () {}, // Empty callback when not clickable
                        ),
                      ),
                    );
                  }).toList(),
            );
          },
        ),
        const SizedBox(height: 20),

        // Double Meat checkbox (meat-specific)
        InkWell(
          onTap: () {
            setState(() {
              _doubleMeat = !_doubleMeat;
              _updatePriceDisplay();
            });
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: _doubleMeat ? Colors.white : Colors.transparent,
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child:
                      _doubleMeat
                          ? const Icon(
                            Icons.check,
                            color: Colors.black,
                            size: 18,
                          )
                          : null,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Double Meat (+£1.50)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Helper method to get available extra toppings based on selected meat
  List<String> _getAvailableExtraToppings() {
    final List<String> available = [];

    if (_selectedMeat == null) {
      return available; // No meat selected, no extra toppings available
    }

    for (var entry in _extraToppingsData.entries) {
      final extraName = entry.key;
      final parent = entry.value['parent'];

      // Only add if parent matches the selected meat
      if (parent != null && parent == _selectedMeat) {
        available.add(extraName);
      }
    }

    return available;
  }

  // Helper method to get filtered meat options based on item name
  List<String> _getFilteredMeatOptions() {
    // If item name contains "meatball", only show "Meat Ball" option
    if (widget.foodItem.name.toLowerCase().contains('meatball')) {
      return ['Meat Ball'];
    }

    // If item name contains "pepperoni", only show "Pepperoni" option
    if (widget.foodItem.name.toLowerCase().contains('pepperoni')) {
      return ['Pepperoni'];
    }

    // If item name contains "plain chicken", only show "Plain Chicken" option
    if (widget.foodItem.name.toLowerCase().contains('plain chicken')) {
      return ['Plain Chicken'];
    }

    // If item name contains "salami", only show "Salami" option
    if (widget.foodItem.name.toLowerCase().contains('salami')) {
      return ['Salami'];
    }

    // If item name contains "shawarma", only show "Chicken Shawarma" option
    if (widget.foodItem.name.toLowerCase().contains('shawarma')) {
      return ['Chicken Shawarma'];
    }

    // If item name contains "shredded beef", only show "Shredded Beef" option
    if (widget.foodItem.name.toLowerCase().contains('shredded beef')) {
      return ['Shredded Beef'];
    }

    // If item name contains "tuna", only show "Tuna" option
    if (widget.foodItem.name.toLowerCase().contains('tuna')) {
      return ['Tuna'];
    }

    // If item name contains "turkey", only show "Turkey" option
    if (widget.foodItem.name.toLowerCase().contains('turkey')) {
      return ['Turkey'];
    }

    // If item name contains "vegetables", only show "Vegetables" option
    if (widget.foodItem.name.toLowerCase().contains('vegetables')) {
      return ['Vegetables'];
    }

    // Otherwise, return all meat options
    return _meatOptions;
  }

  Widget _buildToppingsSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Toppings:',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 15),
        LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            final buttonWidth =
                (availableWidth - 24) / 3; // 24 = spacing (12 * 2)
            return Wrap(
              spacing: 12,
              runSpacing: 15,
              children:
                  _toppingOptions.map((topping) {
                    final bool isActive = _selectedToppings.contains(topping);
                    final bool hasCost = topping == 'Extra Cheese';
                    return SizedBox(
                      width: buttonWidth,
                      child: _buildOptionButton(
                        title: hasCost ? '$topping (+£0.50)' : topping,
                        isActive: isActive,
                        onTap: () {
                          setState(() {
                            if (isActive) {
                              _selectedToppings.remove(topping);
                            } else {
                              _selectedToppings.add(topping);
                            }
                            _updatePriceDisplay();
                          });
                        },
                      ),
                    );
                  }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSaucesSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Sauces:',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 15),
        LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            final buttonWidth =
                (availableWidth - 24) / 3; // 24 = spacing (12 * 2)
            return Wrap(
              spacing: 12,
              runSpacing: 15,
              children:
                  _sauceOptions.map((sauce) {
                    final bool isActive = _selectedSauces.contains(sauce);
                    return SizedBox(
                      width: buttonWidth,
                      child: _buildOptionButton(
                        title: sauce,
                        isActive: isActive,
                        onTap: () {
                          setState(() {
                            if (isActive) {
                              _selectedSauces.remove(sauce);
                            } else {
                              _selectedSauces.add(sauce);
                            }
                          });
                        },
                      ),
                    );
                  }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildClassicToppingsSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Classic Toppings (Free):',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 15),
        LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            final buttonWidth = (availableWidth - 24) / 3;
            return Wrap(
              spacing: 12,
              runSpacing: 15,
              children:
                  _classicToppingsOptions.map((topping) {
                    final bool isActive = _selectedClassicToppings.contains(
                      topping,
                    );
                    return SizedBox(
                      width: buttonWidth,
                      child: _buildOptionButton(
                        title: topping,
                        isActive: isActive,
                        onTap: () {
                          setState(() {
                            if (isActive) {
                              _selectedClassicToppings.remove(topping);
                            } else {
                              _selectedClassicToppings.add(topping);
                            }
                          });
                        },
                      ),
                    );
                  }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildExtraToppingsSelectionForJackedPotato() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Extra Toppings:',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 15),
        LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            final buttonWidth = (availableWidth - 24) / 3;
            return Wrap(
              spacing: 12,
              runSpacing: 15,
              children:
                  _extraToppingsData.entries.map((entry) {
                    final extraName = entry.key;
                    final bool isActive = _selectedExtraToppings.contains(
                      extraName,
                    );
                    final price = entry.value['price'] as double;
                    return SizedBox(
                      width: buttonWidth,
                      child: _buildOptionButton(
                        title: '$extraName (+£${price.toStringAsFixed(2)})',
                        isActive: isActive,
                        onTap: () {
                          setState(() {
                            if (isActive) {
                              _selectedExtraToppings.remove(extraName);
                            } else {
                              _selectedExtraToppings.add(extraName);
                            }
                            _updatePriceDisplay();
                          });
                        },
                      ),
                    );
                  }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMakeItAMealOption() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Checkbox to enable Make it a Meal
        InkWell(
          onTap: () {
            setState(() {
              _makeItAMeal = !_makeItAMeal;
              // Reset selections when unchecking
              if (!_makeItAMeal) {
                _selectedMealDrink = null;
                _selectedMealSide = null;
                _selectedSideType = null;
              }
              _updatePriceDisplay();
            });
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: _makeItAMeal ? Colors.white : Colors.transparent,
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child:
                      _makeItAMeal
                          ? const Icon(
                            Icons.check,
                            color: Colors.black,
                            size: 18,
                          )
                          : null,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Make it a Meal (+£1.50)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Show drink and side selection when enabled
        if (_makeItAMeal) ...[
          const SizedBox(height: 20),

          // Drink selection
          const Text(
            'Select Drink:',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 15),
          LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              final buttonWidth = (availableWidth - 24) / 3;
              return Wrap(
                spacing: 12,
                runSpacing: 15,
                children:
                    _availableDrinks.map((drink) {
                      final bool isActive = _selectedMealDrink?.id == drink.id;
                      return SizedBox(
                        width: buttonWidth,
                        child: _buildOptionButton(
                          title: drink.name,
                          isActive: isActive,
                          onTap: () {
                            setState(() {
                              _selectedMealDrink = drink;
                            });
                          },
                        ),
                      );
                    }).toList(),
              );
            },
          ),

          const SizedBox(height: 30),

          // Crisp or Cookie selection
          const Text(
            'Select Crisp or Cookie:',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 15),
          LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              final buttonWidth = (availableWidth - 24) / 3;

              return Wrap(
                spacing: 12,
                runSpacing: 15,
                children: [
                  SizedBox(
                    width: buttonWidth,
                    child: _buildOptionButton(
                      title: 'Crisp',
                      isActive: _selectedSideType == 'Crisp',
                      onTap: () {
                        setState(() {
                          _selectedSideType = 'Crisp';
                          // Select the first crisp as default
                          if (_availableCrisps.isNotEmpty) {
                            _selectedMealSide = _availableCrisps.first;
                          }
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: buttonWidth,
                    child: _buildOptionButton(
                      title: 'Cookie',
                      isActive: _selectedSideType == 'Cookie',
                      onTap: () {
                        setState(() {
                          _selectedSideType = 'Cookie';
                          // Select the first cookie as default
                          if (_availableCookies.isNotEmpty) {
                            _selectedMealSide = _availableCookies.first;
                          }
                        });
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildReviewNoteSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Review Note:',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 15),
        Container(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[100]!, width: 2),
          ),
          child: TextField(
            controller: _reviewNotesController,
            maxLines: 3,
            style: const TextStyle(fontSize: 16, color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Add any special instructions or notes...',
              hintStyle: TextStyle(color: Colors.grey[400]),
              contentPadding: const EdgeInsets.all(16),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }
}
