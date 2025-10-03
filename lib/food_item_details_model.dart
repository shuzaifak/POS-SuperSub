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

  bool _isInSizeSelectionMode = false;
  bool _sizeHasBeenSelected = false;

  final TextEditingController _reviewNotesController = TextEditingController();

  // Breakfast & Sandwich specific options
  String? _selectedBread;
  String? _selectedMeat;
  bool _doubleMeat = false;
  bool _goLarge = false;

  // Generic option lists for Breakfast and Sandwich categories
  final List<String> _breadOptions = [
    'White',
    'WholeMeal',
    'MultiGrain',
    'White Bread Cheese & Herbs',
  ];

  final List<String> _meatOptions = [
    'Plain chicken',
    'Meat Ball',
    'Chicken Tikka',
    'Chicken Teriyaki',
    'Salami',
    'Ham',
    'Pepperoni',
    'Shredded Beef',
  ];

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

  bool _isRemoveButtonPressed = false;
  bool _isAddButtonPressed = false;

  @override
  void initState() {
    super.initState();
    print('🔍 INIT STATE: Starting initialization for ${widget.foodItem.name}');

    if (widget.isEditing && widget.initialCartItem != null) {
      final CartItem item = widget.initialCartItem!;
      _quantity = item.quantity;
      _reviewNotesController.text = item.comment ?? '';

      print('🔍 EDITING MODE: Editing ${widget.foodItem.name}');
      print('🔍 Cart item options: ${item.selectedOptions}');

      // Parse selected options from the cart item
      if (item.selectedOptions != null) {
        for (var option in item.selectedOptions!) {
          String lowerOption = option.toLowerCase();

          if (lowerOption.startsWith('bread:')) {
            _selectedBread = option.split(':').last.trim();
          } else if (lowerOption.startsWith('meat:')) {
            _selectedMeat = option.split(':').last.trim();
          } else if (lowerOption == 'double meat') {
            _doubleMeat = true;
          } else if (lowerOption == 'go large') {
            _goLarge = true;
          } else if (lowerOption.startsWith('toppings:')) {
            _selectedToppings.addAll(
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
      if (['Wraps', 'Salads', 'Bowls'].contains(widget.foodItem.category)) {
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

      // For Wraps, Salads, and Bowls, default to 'Meat' tab (no bread needed)
      if (['Wraps', 'Salads', 'Bowls'].contains(widget.foodItem.category)) {
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

    // Breakfast, Sandwich, Wraps, Salads, and Bowls specific pricing
    if ([
      'Breakfast',
      'Sandwiches',
      'Wraps',
      'Salads',
      'Bowls',
    ].contains(widget.foodItem.category)) {
      // Add meat topping cost
      if (_selectedMeat == 'Meat Ball') {
        price += 0.50;
        debugPrint("Added Meat Ball cost: £0.50");
      }

      // Add double meat cost
      if (_doubleMeat) {
        price += 1.50;
        debugPrint("Added Double Meat cost: £1.50");
      }

      // Add extra cheese cost
      if (_selectedToppings.contains('Extra Cheese')) {
        price += 0.50;
        debugPrint("Added Extra Cheese cost: £0.50");
      }
    }

    // Go Large is only for Sandwiches
    if (widget.foodItem.category == 'Sandwiches' && _goLarge) {
      price += 2.50;
      debugPrint("Added Go Large cost: £2.50");
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

    final List<String> selectedOptions = [];

    // Add size if applicable
    if (_selectedSize != null && widget.foodItem.price.keys.length > 1) {
      selectedOptions.add('Size: $_selectedSize');
    }

    // Breakfast, Sandwich & Wraps specific options
    if ([
      'Breakfast',
      'Sandwiches',
      'Wraps',
      'Salads',
      'Bowls',
    ].contains(widget.foodItem.category)) {
      // Bread only for Breakfast and Sandwiches (not Wraps, Salads, or Bowls)
      if ((widget.foodItem.category == 'Breakfast' ||
              widget.foodItem.category == 'Sandwiches') &&
          _selectedBread != null) {
        selectedOptions.add('Bread: $_selectedBread');
      }

      if (_selectedMeat != null) {
        selectedOptions.add('Meat: $_selectedMeat');
      }

      if (_doubleMeat) {
        selectedOptions.add('Double Meat');
      }

      if (_selectedToppings.isNotEmpty) {
        selectedOptions.add('Toppings: ${_selectedToppings.join(', ')}');
      }

      if (_selectedSauces.isNotEmpty) {
        selectedOptions.add('Sauces: ${_selectedSauces.join(', ')}');
      }
    }

    // Go Large is only for Sandwiches
    if (widget.foodItem.category == 'Sandwiches' && _goLarge) {
      selectedOptions.add('Go Large');
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

        // Go Large option (only for Sandwiches)
        if (widget.foodItem.category == 'Sandwiches') _buildGoLargeOption(),

        if (widget.foodItem.category == 'Sandwiches')
          const SizedBox(height: 30),

        // Review Note section
        _buildReviewNoteSection(),
      ],
    );
  }

  Widget _buildCategoryTabs() {
    // Hide 'Bread' tab for Wraps, Salads, and Bowls categories
    final List<String> categories =
        ['Wraps', 'Salads', 'Bowls'].contains(widget.foodItem.category)
            ? ['Meat', 'Toppings', 'Sauces']
            : ['Bread', 'Meat', 'Toppings', 'Sauces'];

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Meat:',
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
                  _meatOptions.map((meat) {
                    final bool isActive = _selectedMeat == meat;
                    final bool hasCost = meat.contains('Meat Ball');
                    return SizedBox(
                      width: buttonWidth,
                      child: _buildOptionButton(
                        title: hasCost ? '$meat (+£0.50)' : meat,
                        isActive: isActive,
                        onTap: () {
                          setState(() {
                            _selectedMeat = meat;
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

  Widget _buildGoLargeOption() {
    return InkWell(
      onTap: () {
        setState(() {
          _goLarge = !_goLarge;
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
                color: _goLarge ? Colors.white : Colors.transparent,
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(4),
              ),
              child:
                  _goLarge
                      ? const Icon(Icons.check, color: Colors.black, size: 18)
                      : null,
            ),
            const SizedBox(width: 12),
            const Text(
              'Go Large (+£2.50)',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
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
