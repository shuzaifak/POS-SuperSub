// lib/food_item_details_model.dart

import 'package:flutter/material.dart';
import 'package:epos/models/food_item.dart';
import 'package:epos/models/cart_item.dart';
import 'dart:math';
import 'package:epos/services/custom_popup_service.dart';

// Assuming HexColor extension is in a common utility file or defined here
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
  // This callback will now pass the final CartItem, whether it's new or updated
  final Function(CartItem) onAddToCart;
  final VoidCallback? onClose;

  // NEW: Optional parameters for editing existing cart items
  final CartItem? initialCartItem;
  final bool isEditing;

  // NEW: List of all food items for dynamic deal options
  final List<FoodItem> allFoodItems;

  const FoodItemDetailsModal({
    super.key,
    required this.foodItem,
    required this.onAddToCart,
    this.onClose,
    this.initialCartItem, // Pass the existing CartItem here when editing
    this.isEditing = false, // Flag to indicate if we're in edit mode
    required this.allFoodItems, // Required for dynamic deal options
  });

  @override
  State<FoodItemDetailsModal> createState() => _FoodItemDetailsModalState();
}

class _FoodItemDetailsModalState extends State<FoodItemDetailsModal> {
  late double _calculatedPricePerUnit;
  int _quantity = 1;
  String _selectedOptionCategory = 'Toppings';
  String _selectedDealCategory = '';

  String? _selectedSize;
  Set<String> _selectedToppings = {};
  String? _selectedBase;
  String? _selectedCrust;
  Set<String> _selectedSauces = {};

  bool _makeItAMeal = false;
  String? _selectedDrink;
  String? _selectedDrinkFlavor;

  // NEW: Chip seasoning options
  String? _selectedChipSeasoning;

  String _saladChoice = 'Yes'; // 'Yes' or 'No'
  bool _noSauce = false;
  bool _noCream = false;

  bool _isInSizeSelectionMode = false;
  bool _sizeHasBeenSelected = false;

  final TextEditingController _reviewNotesController = TextEditingController();

  final List<String> _allToppings = [
    "Mushrooms",
    "Artichoke",
    "Carcioffi",
    "Onion",
    "Pepper",
    "Rocket",
    "Spinach",
    "Parsley",
    "Capers",
    "Oregano",
    "Egg",
    "Sweetcorn",
    "Chips",
    "Pineapple",
    "Chilli",
    "Basil",
    "Olives",
    "Sausages",
    "Mozzarella",
    "Emmental",
    "Taleggio",
    "Gorgonzola",
    "Brie",
    "Grana",
    "Red onion",
    "Red pepper",
    "Green chillies",
    "Buffalo mozzarella",
    "Fresh cherry tomatoes",
  ];

  final List<String> _allBases = ["BBQ", "Garlic", "Tomato"];
  final List<String> _allCrusts = ["Normal", "Stuffed"];
  final List<String> _allSauces = [
    "Mayo",
    "Ketchup",
    "Chilli sauce",
    "Sweet chilli",
    "Garlic Sauce",
    "BBQ",
    "Mint Sauce",
  ];
  final List<String> _allDrinks = [
    "Coca Cola",
    "7Up",
    "Diet Coca Cola",
    "Fanta",
    "Pepsi",
    "Sprite",
    "J20 GLASS BOTTLE",
  ];

  // NEW: Chip seasoning options
  final List<String> _chipSeasoningOptions = [
    "White Salt",
    "Red Salt",
    "Vinegar",
    "Salt and Vinegar",
  ];

  final Map<String, List<String>> _drinkFlavors = {
    "J20 GLASS BOTTLE": [
      "Apple & Raspberry",
      "Apple & Mango",
      "Orange & Passion Fruit",
    ],
  };

  bool _isRemoveButtonPressed = false;
  bool _isAddButtonPressed = false;

  // Deal-specific selections
  final Map<String, String?> _dealSelections = {};
  final Map<String, Set<String>> _dealMultiSelections = {};

  // Method to get all pizza flavours from the actual menu items
  List<String> _getPizzaFlavoursFromMenu() {
    return widget.allFoodItems
        .where((item) => item.category == 'Pizza')
        .map((item) => item.name)
        .where((name) => name.isNotEmpty)
        .toList()
      ..sort(); // Sort alphabetically
  }

  // Method to get shawarma options from the actual menu items
  List<String> _getShawarmaOptionsFromMenu() {
    List<String> shawarmaOptions = [];

    // Get items from Shawarma category with "Donner & Shawarma kebab" subType
    shawarmaOptions.addAll(
      widget.allFoodItems
          .where(
            (item) =>
                item.category == 'Shawarma' &&
                item.subType == 'Donner & Shawarma kebab',
          )
          .map((item) => item.name)
          .where((name) => name.isNotEmpty),
    );

    // Get items from Shawarma category with "Shawarma & kebab trays" subType and add "(Tray)" suffix
    shawarmaOptions.addAll(
      widget.allFoodItems
          .where(
            (item) =>
                item.category == 'Shawarma' &&
                item.subType == 'Shawarma & kebab trays',
          )
          .map((item) => '${item.name} (Tray)')
          .where((name) => name.isNotEmpty),
    );

    return shawarmaOptions..sort(); // Sort alphabetically
  }

  // Method to get shawarma options for Shawarma Deal (only Chicken Shawarma (Pitta))
  List<String> _getShawarmaOptionsForDeal() {
    // Only return Chicken Shawarma (Pitta) for all shawarma options
    return ['Chicken Shawarma (Pitta)']..sort(); // Sort alphabetically
  }

  // Method to get burger options from the actual menu items
  List<String> _getBurgerOptionsFromMenu() {
    return widget.allFoodItems
        .where((item) => item.category == 'Burgers')
        .map((item) => item.name)
        .where((name) => name.isNotEmpty)
        .toList()
      ..sort(); // Sort alphabetically
  }

  // Method to get calzone options from the actual menu items
  List<String> _getCalzoneOptionsFromMenu() {
    return widget.allFoodItems
        .where(
          (item) =>
              item.category == 'Calzone' ||
              item.name.toLowerCase().contains('calzone'),
        )
        .map((item) => item.name)
        .where((name) => name.isNotEmpty)
        .toList()
      ..sort(); // Sort alphabetically
  }

  @override
  void initState() {
    super.initState();

    if (widget.isEditing && widget.initialCartItem != null) {
      final CartItem item = widget.initialCartItem!;
      _quantity = item.quantity;
      _reviewNotesController.text = item.comment ?? '';

      print('🔍 EDITING MODE: Deal editing for ${widget.foodItem.name}');
      print('🔍 Cart item options: ${item.selectedOptions}');

      // Parse selected options from the cart item
      if (item.selectedOptions != null) {
        for (var option in item.selectedOptions!) {
          String lowerOption = option.toLowerCase();
          if (lowerOption.startsWith('size:')) {
            _selectedSize = option.split(':').last.trim();
            _sizeHasBeenSelected = true;
          } else if (lowerOption.startsWith('toppings:')) {
            _selectedToppings.addAll(
              option.split(':').last.trim().split(',').map((s) => s.trim()),
            );
          } else if (lowerOption.startsWith('base:')) {
            _selectedBase = option.split(':').last.trim();
          } else if (lowerOption.startsWith('crust:')) {
            _selectedCrust = option.split(':').last.trim();
          } else if (lowerOption.startsWith('sauce dips:')) {
            _selectedSauces.addAll(
              option.split(':').last.trim().split(',').map((s) => s.trim()),
            );
          } else if (lowerOption == 'make it a meal') {
            _makeItAMeal = true;
          } else if (lowerOption.startsWith('drink:')) {
            String drinkAndFlavor = option.split(':').last.trim();
            if (drinkAndFlavor.contains('(') && drinkAndFlavor.contains(')')) {
              _selectedDrink =
                  drinkAndFlavor
                      .substring(0, drinkAndFlavor.indexOf('('))
                      .trim();
              _selectedDrinkFlavor =
                  drinkAndFlavor
                      .substring(
                        drinkAndFlavor.indexOf('(') + 1,
                        drinkAndFlavor.indexOf(')'),
                      )
                      .trim();
            } else {
              _selectedDrink = drinkAndFlavor;
            }
          } else if (lowerOption.startsWith('chips seasoning:')) {
            _selectedChipSeasoning = option.split(':').last.trim();
          } else if (lowerOption == 'no salad') {
            _saladChoice = 'No';
          } else if (lowerOption == 'no sauce') {
            _noSauce = true;
          } else if (lowerOption == 'no cream') {
            _noCream = true;
          } else if (lowerOption.startsWith('flavor:') &&
              !_drinkFlavors.containsKey(widget.foodItem.name)) {
            // This handles standalone drink flavors if not already handled by 'drink:'
            _selectedDrinkFlavor = option.split(':').last.trim();
          }
          // Parse deal-specific options for editing
          else if (widget.foodItem.category == 'Deals') {
            print('🔍 PROCESSING DEAL OPTION: "$option"');
            // Parse deal options like "Pizza: Margherita", "Shawarma: Chicken Shawarma", etc.
            if (option.contains(':')) {
              print('🔍 OPTION CONTAINS COLON: "$option"');
              String sectionName = option.split(':')[0].trim();
              String selectedValue = option.split(':')[1].trim();

              print(
                '🔍 EXTRACTED: sectionName="$sectionName", selectedValue="$selectedValue"',
              );

              // Skip default items that will be re-added automatically for shawarma deal
              bool isDefaultItemToSkip = false;
              if (widget.foodItem.name.toLowerCase() == 'shawarma deal') {
                if (sectionName == 'Shawarma Flavour' ||
                    sectionName == 'Fries') {
                  // Only skip these truly default items, NOT user selections like chips seasoning
                  isDefaultItemToSkip = true;
                  print(
                    '🔍 SKIPPING DEFAULT ITEM: "$sectionName" = "$selectedValue"',
                  );
                }
              }
              print(
                '🔍 isDefaultItemToSkip: $isDefaultItemToSkip for "$sectionName"',
              );

              if (!isDefaultItemToSkip) {
                print(
                  '🔍 PARSING DEAL OPTION: "$sectionName" = "$selectedValue"',
                );

                // Map cart format back to modal format for specific keys
                String modalKey = sectionName;
                print(
                  '🔍 DEAL MODAL KEY MAPPING for "${widget.foodItem.name}": "$sectionName" -> "$modalKey"',
                );

                if (widget.foodItem.name.toLowerCase() == 'shawarma deal') {
                  if (sectionName == 'Drink') {
                    modalKey = 'Drink & seasoning';
                    print('🔍 MAPPED DRINK: "$sectionName" -> "$modalKey"');
                  } else if (sectionName == 'Shawarma 1 options') {
                    modalKey = 'Shawarma 1 - Shawarma Options';
                  } else if (sectionName == 'Shawarma 2 options') {
                    modalKey = 'Shawarma 2 - Shawarma Options';
                  } else if (sectionName == 'Shawarma 3 options') {
                    modalKey = 'Shawarma 3 - Shawarma Options';
                  } else if (sectionName == 'Shawarma 4 options') {
                    modalKey = 'Shawarma 4 - Shawarma Options';
                  } else if (sectionName == 'Chips Seasoning 1') {
                    modalKey = 'Drink & seasoning - Chips Seasoning 1';
                  } else if (sectionName == 'Chips Seasoning 2') {
                    modalKey = 'Drink & seasoning - Chips Seasoning 2';
                  }
                }

                // Check if this is a multi-select option (like Sauces)
                if (sectionName.toLowerCase().contains('sauce')) {
                  // Handle multi-select options
                  if (!_dealMultiSelections.containsKey(modalKey)) {
                    _dealMultiSelections[modalKey] = <String>{};
                  }
                  // Split comma-separated values for multi-select
                  List<String> values =
                      selectedValue.split(',').map((s) => s.trim()).toList();
                  _dealMultiSelections[modalKey]!.addAll(values);
                  print('🔍 ADDED MULTI-SELECT: $_dealMultiSelections');
                } else {
                  // Handle single-select options
                  _dealSelections[modalKey] = selectedValue;
                  print('🔍 ADDED SINGLE-SELECT: $_dealSelections');
                }
              }
            }
          }
        }

        // Special handling for Shawarma Deal editing - bypass general parsing
        if (widget.foodItem.name.toLowerCase() == 'shawarma deal' &&
            item.selectedOptions != null) {
          _parseShawarmaDealeditingOptions(item.selectedOptions!);
        }
        // Convert consolidated cart options back to modal structure for editing
        else if (widget.foodItem.category == 'Deals' &&
            _dealSelections.isNotEmpty) {
          Map<String, String?> originalDealSelections = {};
          Map<String, Set<String>> originalDealMultiSelections = {};

          _dealSelections.forEach((storedKey, storedValue) {
            print(
              '🔍 RESTORE: Processing stored key "$storedKey" = "$storedValue" for "${widget.foodItem.name}"',
            );

            if (storedKey.startsWith('Selected ') && storedValue != null) {
              // Handle any consolidated selections (Selected Shawarmas, Selected Pizzas, etc.)
              List<String> itemList =
                  storedValue.split(',').map((s) => s.trim()).toList();

              // Determine the base type from the stored key
              String baseType = '';
              int maxCount = 4; // Default max count

              if (storedKey.contains('Shawarmas')) {
                baseType = 'Shawarma';
                maxCount = 4;
              } else if (storedKey.contains('Pizzas')) {
                baseType = 'Pizza';
                maxCount = 3;
              } else if (storedKey.contains('Burgers')) {
                baseType = 'Burger';
                maxCount = 4;
              } else if (storedKey.contains('Calzones')) {
                baseType = 'Calzone';
                maxCount = 4;
              }

              // Map back to individual selections
              for (int i = 0; i < itemList.length && i < maxCount; i++) {
                String modalKey = '$baseType ${i + 1}';
                originalDealSelections[modalKey] = itemList[i];
                print(
                  '🔍 MAPPED: "$storedKey" -> "$modalKey" = "${itemList[i]}"',
                );
              }
            } else {
              // Direct mapping - stored keys should match modal keys exactly
              String modalKey = storedKey;

              // Special handling for shawarma deal options stored with " - " format
              if (storedKey.contains(' - Shawarma Options') ||
                  storedKey.contains(' - Sauces (Optional)')) {
                modalKey = storedKey; // Keep the full key for shawarma deal
              } else if (storedKey.contains(' - Chips Seasoning')) {
                modalKey = storedKey; // Keep the full key for chips seasoning
              }

              originalDealSelections[modalKey] = storedValue;
              if (modalKey != storedKey) {
                print(
                  '🔍 MAPPED: "$storedKey" -> "$modalKey" = "$storedValue"',
                );
              }
            }
          });

          // Handle multi-select options
          _dealMultiSelections.forEach((storedKey, storedValues) {
            String modalKey = storedKey;

            // Direct mapping since "Choose " prefixes are removed

            originalDealMultiSelections[modalKey] = Set<String>.from(
              storedValues,
            );
            print(
              '🔍 MAPPED MULTI-SELECT: "$storedKey" -> "$modalKey" = "$storedValues"',
            );
          });

          // Replace the stored selections with the converted ones
          _dealSelections.clear();
          _dealSelections.addAll(originalDealSelections);
          _dealMultiSelections.clear();
          _dealMultiSelections.addAll(originalDealMultiSelections);

          print('🔍 FINAL DEAL SELECTIONS: $_dealSelections');
          print('🔍 FINAL DEAL MULTI-SELECTIONS: $_dealMultiSelections');

          // Set deal category for editing - find the first category that has a selection
          Map<String, List<String>> dealOptions = _getDealOptions(
            widget.foodItem.name,
          );
          List<String> dealCategories = _getDealCategories(dealOptions);

          // Find the first category that has a selection to display
          // Prioritize certain categories for better UX
          String? foundCategory;
          List<String> priorityCategories = [
            'Shawarma',
            'Pizza (12")',
            'Pizza (16")',
          ];

          // First check priority categories
          for (String category in priorityCategories) {
            if (dealCategories.contains(category)) {
              bool hasSingleSelection =
                  _dealSelections.containsKey(category) &&
                  _dealSelections[category] != null;
              bool hasMultiSelection =
                  _dealMultiSelections.containsKey(category) &&
                  _dealMultiSelections[category]!.isNotEmpty;

              print(
                '🔍 TAB PRIORITY CHECK for "${widget.foodItem.name}": category="$category", hasSingleSelection=$hasSingleSelection (${_dealSelections[category]}), hasMultiSelection=$hasMultiSelection',
              );

              if (hasSingleSelection || hasMultiSelection) {
                foundCategory = category;
                break;
              }
            }
          }

          // If no priority category found, check all categories
          if (foundCategory == null) {
            for (String category in dealCategories) {
              bool hasSingleSelection =
                  _dealSelections.containsKey(category) &&
                  _dealSelections[category] != null;
              bool hasMultiSelection =
                  _dealMultiSelections.containsKey(category) &&
                  _dealMultiSelections[category]!.isNotEmpty;

              if (hasSingleSelection || hasMultiSelection) {
                foundCategory = category;
                break;
              }
            }
          }

          // If no category with selection found, use the first category
          if (foundCategory != null) {
            _selectedDealCategory = foundCategory;
          } else if (dealCategories.isNotEmpty) {
            _selectedDealCategory = dealCategories.first;
          }

          print('🔍 SET DEAL CATEGORY: "$_selectedDealCategory"');
        }
      }
      // If we are editing, we don't start in size selection mode, as a size should already be selected or not applicable.
      _isInSizeSelectionMode = false;
      _sizeHasBeenSelected =
          _selectedSize != null ||
          (widget.foodItem.price.keys.length == 1 &&
              widget.foodItem.price.isNotEmpty);
    } else {
      bool requiresSizeSelection =
          ([
                'Pizza',
                'GarlicBread',
                'Shawarma',
                'Wraps',
                'Burgers',
                'Chicken',
                'Wings',
                'Deals',
              ].contains(widget.foodItem.category) &&
              widget.foodItem.price.keys.length > 1);

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

      if (widget.foodItem.category == 'Pizza' ||
          widget.foodItem.category == 'GarlicBread') {
        _selectedBase = "Tomato";
        _selectedCrust = "Normal";

        if (widget.foodItem.defaultToppings != null) {
          _selectedToppings.addAll(widget.foodItem.defaultToppings!);
        }
        if (widget.foodItem.defaultCheese != null) {
          _selectedToppings.addAll(widget.foodItem.defaultCheese!);
        }
      }

      if (_drinkFlavors.containsKey(widget.foodItem.name)) {
        _selectedDrink = widget.foodItem.name;
        _selectedDrinkFlavor = null;
      }

      // Initialize deal category for deals
      if (widget.foodItem.category == 'Deals') {
        Map<String, List<String>> dealOptions = _getDealOptions(
          widget.foodItem.name,
        );
        if (dealOptions.isNotEmpty) {
          // Find the first category with food items (Pizza, Shawarma, Burger)
          List<String> dealCategories = _getDealCategories(dealOptions);
          if (dealCategories.isNotEmpty) {
            _selectedDealCategory = dealCategories.first;
          }
        }
      }
    }

    _calculatedPricePerUnit = _calculatePricePerUnit();
  }

  @override
  void dispose() {
    _reviewNotesController.dispose();
    super.dispose();
  }

  // Special parsing method for Shawarma Deal editing only
  void _parseShawarmaDealeditingOptions(List<String> selectedOptions) {
    print('🔍 SPECIAL SHAWARMA DEAL PARSING');

    // Clear existing selections
    _dealSelections.clear();
    _dealMultiSelections.clear();

    for (String option in selectedOptions) {
      print('🔍 SPECIAL PARSING: "$option"');

      // Skip default items that will be re-added automatically
      if (option.startsWith('Shawarma Flavour:') ||
          option.startsWith('Fries:')) {
        print('🔍 SPECIAL SKIP: "$option"');
        continue;
      }

      if (option.contains(':')) {
        String sectionName = option.split(':')[0].trim();
        String selectedValue = option.split(':')[1].trim();

        // Direct mapping for shawarma deal
        if (sectionName == 'Drink') {
          _dealSelections['Drink & seasoning'] = selectedValue;
          print(
            '🔍 SPECIAL MAPPED DRINK: "$selectedValue" -> "Drink & seasoning"',
          );
        } else if (sectionName == 'Chips Seasoning 1') {
          _dealSelections['Drink & seasoning - Chips Seasoning 1'] =
              selectedValue;
          print('🔍 SPECIAL MAPPED CHIPS 1: "$selectedValue"');
        } else if (sectionName == 'Chips Seasoning 2') {
          _dealSelections['Drink & seasoning - Chips Seasoning 2'] =
              selectedValue;
          print('🔍 SPECIAL MAPPED CHIPS 2: "$selectedValue"');
        } else if (sectionName == 'Shawarma 1 options') {
          _dealSelections['Shawarma 1 - Shawarma Options'] = selectedValue;
        } else if (sectionName == 'Shawarma 2 options') {
          _dealSelections['Shawarma 2 - Shawarma Options'] = selectedValue;
        } else if (sectionName == 'Shawarma 3 options') {
          _dealSelections['Shawarma 3 - Shawarma Options'] = selectedValue;
        } else if (sectionName == 'Shawarma 4 options') {
          _dealSelections['Shawarma 4 - Shawarma Options'] = selectedValue;
        } else if (sectionName.endsWith('sauces (optional)')) {
          // Handle sauces as multi-select
          String shawarmaNum =
              sectionName.split(' ')[0] +
              ' ' +
              sectionName.split(' ')[1]; // "Shawarma 1"
          String modalKey = '$shawarmaNum - Sauces (Optional)';
          if (!_dealMultiSelections.containsKey(modalKey)) {
            _dealMultiSelections[modalKey] = <String>{};
          }
          List<String> values =
              selectedValue.split(',').map((s) => s.trim()).toList();
          _dealMultiSelections[modalKey]!.addAll(values);
          print('🔍 SPECIAL MAPPED SAUCES: $modalKey = $values');
        } else if (sectionName.endsWith('- Sauces (Optional)')) {
          // Handle already correctly formatted sauce options
          if (!_dealMultiSelections.containsKey(sectionName)) {
            _dealMultiSelections[sectionName] = <String>{};
          }
          List<String> values =
              selectedValue.split(',').map((s) => s.trim()).toList();
          _dealMultiSelections[sectionName]!.addAll(values);
          print('🔍 SPECIAL MAPPED FORMATTED SAUCES: $sectionName = $values');
        } else {
          // Default handling for other options
          _dealSelections[sectionName] = selectedValue;
          print('🔍 SPECIAL MAPPED OTHER: $sectionName = $selectedValue');
        }
      }
    }

    print('🔍 SPECIAL FINAL SELECTIONS: $_dealSelections');
    print('🔍 SPECIAL FINAL MULTI-SELECTIONS: $_dealMultiSelections');

    // Set default tab to Shawarma 1 for editing
    _selectedDealCategory = 'Shawarma 1';
    print('🔍 SPECIAL SET DEFAULT TAB: $_selectedDealCategory');
  }

  double _calculatePricePerUnit() {
    debugPrint("--- Calculating Price for ${widget.foodItem.name} ---");
    debugPrint("Food Item Price Map: ${widget.foodItem.price}");
    debugPrint("Selected Size: $_selectedSize");
    debugPrint("Selected Base: $_selectedBase");
    debugPrint("Selected Crust: $_selectedCrust");
    debugPrint("Selected Toppings: $_selectedToppings");
    debugPrint("Selected Sauces: $_selectedSauces");

    double price = 0.0;

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

    debugPrint("Base price: $price");

    if (widget.foodItem.category == 'Pizza' ||
        widget.foodItem.category == 'GarlicBread') {
      // Calculate topping costs
      double toppingCost = 0.0;

      // For all pizzas: Charge for extra toppings
      for (var topping in _selectedToppings) {
        if (!((widget.foodItem.defaultToppings ?? []).contains(topping) ||
            (widget.foodItem.defaultCheese ?? []).contains(topping))) {
          if (_selectedSize == "10 inch") {
            toppingCost += 1.0;
          } else if (_selectedSize == "12 inch") {
            toppingCost += 1.5;
          } else if (_selectedSize == "18 inch") {
            toppingCost += 5.5;
          } else if (_selectedSize == "7 inch") {
            toppingCost += 1.0;
          } else if (_selectedSize == "9 inch") {
            toppingCost += 1.5;
          }
        }
      }

      price += toppingCost;
      debugPrint("After toppings: $price (added: $toppingCost)");

      // Calculate base cost
      double baseCost = 0.0;
      if (_selectedBase != null && _selectedBase != "Tomato") {
        if (_selectedSize == "10 inch") {
          baseCost = 1.0;
        } else if (_selectedSize == "12 inch") {
          baseCost = 1.5;
        } else if (_selectedSize == "18 inch") {
          baseCost = 4.0;
        } else if (_selectedSize == "7 inch") {
          baseCost = 1.0;
        } else if (_selectedSize == "9 inch") {
          baseCost = 1.5;
        }
      }
      price += baseCost;
      debugPrint("After base: $price (added: $baseCost)");

      // Calculate crust cost
      double crustCost = 0.0;
      if (_selectedCrust == "Stuffed") {
        if (_selectedSize == "10 inch") {
          crustCost = 1.5;
        } else if (_selectedSize == "12 inch") {
          crustCost = 2.5;
        } else if (_selectedSize == "18 inch") {
          crustCost = 4.5;
        } else if (_selectedSize == "7 inch") {
          crustCost = 1.5;
        } else if (_selectedSize == "9 inch") {
          crustCost = 2.5;
        }
      }
      price += crustCost;
      debugPrint("After crust: $price (added: $crustCost)");

      // Calculate sauce costs
      double sauceCost = 0.0;
      for (var sauce in _selectedSauces) {
        if (sauce == "Chilli sauce" || sauce == "Garlic Sauce") {
          sauceCost += 0.75;
        } else {
          sauceCost += 0.5;
        }
      }
      price += sauceCost;
      debugPrint("After sauces: $price (added: $sauceCost)");
    } else if ([
      'Shawarma',
      'Wraps',
      'Burgers',
    ].contains(widget.foodItem.category)) {
      // Sauces are now FREE for Burgers, Wraps, and Shawarmas - no sauce cost added
      debugPrint(
        "Sauces are free for ${widget.foodItem.category} - no cost added",
      );

      if (_makeItAMeal) {
        price += 1.9;
        debugPrint("After meal addition: $price");
      }
    }

    debugPrint("Final calculated price: $price");
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

  // NEW: Helper method to check if chip seasoning options should be shown
  bool _shouldShowChipSeasoningOptions() {
    // Show for "Make it a meal" options
    if (_makeItAMeal) return true;

    // Show for chips in sides category
    if (widget.foodItem.category == 'Sides' &&
        (widget.foodItem.name.toLowerCase().contains('chips') ||
            widget.foodItem.name.toLowerCase().contains('fries'))) {
      return true;
    }

    // Show for KidsMeal that contains chips
    if (widget.foodItem.category == 'KidsMeal' &&
        (widget.foodItem.description?.toLowerCase().contains('chips') == true ||
            widget.foodItem.description?.toLowerCase().contains('fries') ==
                true ||
            widget.foodItem.name.toLowerCase().contains('chips') ||
            widget.foodItem.name.toLowerCase().contains('fries'))) {
      return true;
    }

    // Show for other deals but NOT for specific deals that don't need chips seasoning
    if (widget.foodItem.category == 'Deals') {
      String dealName = widget.foodItem.name.toLowerCase();
      if (dealName == 'shawarma deal' ||
          dealName == 'family meal' ||
          dealName == 'combo meal') {
        return false; // These deals don't need chips seasoning
      }
      // For other deals that might have chips, return true
      return true;
    }

    return false;
  }

  void _confirmSelection() {
    if (widget.foodItem.price.keys.length > 1 && _selectedSize == null) {
      CustomPopupService.show(
        context,
        "Please select a size before adding to cart",
        type: PopupType.failure,
      );
      return;
    }

    bool kidsMealNeedsDrink =
        widget.foodItem.category == 'KidsMeal' &&
        widget.foodItem.name.toLowerCase().contains('drink');

    if ((_makeItAMeal || kidsMealNeedsDrink) && _selectedDrink == null) {
      CustomPopupService.show(
        context,
        'Please select a drink for your meal',
        type: PopupType.failure,
      );
      return;
    }

    if ((_drinkFlavors.containsKey(widget.foodItem.name) &&
            _selectedDrinkFlavor == null) ||
        (_makeItAMeal &&
            _selectedDrink != null &&
            _drinkFlavors.containsKey(_selectedDrink!) &&
            _selectedDrinkFlavor == null)) {
      CustomPopupService.show(
        context,
        'Please select a flavour fpr your drink',
        type: PopupType.failure,
      );
      return;
    }

    final List<String> selectedOptions = [];

    // Only show size for non-deal items (deals handle sizing differently)
    if (_selectedSize != null &&
        widget.foodItem.price.keys.length > 1 &&
        widget.foodItem.category != 'Deals') {
      selectedOptions.add('Size: $_selectedSize');
    }

    if (_selectedToppings.isNotEmpty) {
      // For Pizza items, only show user-selected toppings (exclude default toppings)
      if (widget.foodItem.category == 'Pizza' ||
          widget.foodItem.category == 'GarlicBread') {
        List<String> userSelectedToppings =
            _selectedToppings
                .where(
                  (topping) =>
                      !((widget.foodItem.defaultToppings ?? []).contains(
                            topping,
                          ) ||
                          (widget.foodItem.defaultCheese ?? []).contains(
                            topping,
                          )),
                )
                .toList();

        if (userSelectedToppings.isNotEmpty) {
          selectedOptions.add('Toppings: ${userSelectedToppings.join(', ')}');
        }
      } else {
        // For non-Pizza items, show all selected toppings
        selectedOptions.add('Toppings: ${_selectedToppings.join(', ')}');
      }
    }

    if (_selectedBase != null &&
        (widget.foodItem.category == 'Pizza' ||
            widget.foodItem.category == 'GarlicBread')) {
      selectedOptions.add('Base: $_selectedBase');
    }

    if (_selectedCrust != null &&
        (widget.foodItem.category == 'Pizza' ||
            widget.foodItem.category == 'GarlicBread')) {
      selectedOptions.add('Crust: $_selectedCrust');
    }

    if (_selectedSauces.isNotEmpty &&
        !_noSauce &&
        (widget.foodItem.category == 'Pizza' ||
            widget.foodItem.category == 'GarlicBread' ||
            widget.foodItem.category == 'Burgers' ||
            widget.foodItem.category == 'Shawarma' ||
            widget.foodItem.category == 'Wraps')) {
      selectedOptions.add('Sauce Dips: ${_selectedSauces.join(', ')}');
    }

    if (_makeItAMeal) {
      selectedOptions.add('Make it a meal');
      if (_selectedDrink != null) {
        String drinkOption = 'Drink: $_selectedDrink';
        if (_selectedDrinkFlavor != null) {
          drinkOption += ' ($_selectedDrinkFlavor)';
        }
        selectedOptions.add(drinkOption);
      }
    } else if (widget.foodItem.category == 'KidsMeal' &&
        _selectedDrink != null) {
      // Kids Meal drink selection (without "Make it a meal" label)
      String drinkOption = 'Drink: $_selectedDrink';
      if (_selectedDrinkFlavor != null) {
        drinkOption += ' ($_selectedDrinkFlavor)';
      }
      selectedOptions.add(drinkOption);
    } else if (_drinkFlavors.containsKey(widget.foodItem.name) &&
        _selectedDrinkFlavor != null) {
      selectedOptions.add('Flavor: $_selectedDrinkFlavor');
    }

    // NEW: Add chip seasoning option
    if (_selectedChipSeasoning != null && _shouldShowChipSeasoningOptions()) {
      selectedOptions.add('Chips Seasoning: $_selectedChipSeasoning');
    }

    if (['Shawarma', 'Wraps', 'Burgers'].contains(widget.foodItem.category)) {
      if (_saladChoice == 'No') selectedOptions.add('No Salad');
      if (_noSauce && _selectedSauces.isEmpty) selectedOptions.add('No Sauce');
    }

    if (widget.foodItem.category == 'Milkshake') {
      if (_noCream) selectedOptions.add('No Cream');
    }

    if (widget.foodItem.category == 'Deals') {
      // Group multiple selections for cart display while keeping individual entries for editing
      Map<String, List<String>> groupedSelections = {};

      _dealSelections.forEach((sectionName, selectedOption) {
        if (selectedOption != null) {
          // Group similar selections (Pizza 1, Pizza 2, etc.) for DISPLAY only
          if (sectionName == 'Pizza 1' ||
              sectionName == 'Pizza 2' ||
              sectionName == 'Pizza 3') {
            // Add size info to group key for Pizza Offers
            String groupKey = 'Selected Pizzas';
            if (widget.foodItem.name.toLowerCase().contains('pizza offers') &&
                _selectedSize != null) {
              groupKey = 'Selected Pizzas ($_selectedSize)';
            }
            groupedSelections[groupKey] ??= [];
            groupedSelections[groupKey]!.add(selectedOption);

            // DON'T add individual entries - only show grouped ones in cart
          } else if (sectionName == 'Shawarma 1' ||
              sectionName == 'Shawarma 2' ||
              sectionName == 'Shawarma 3' ||
              sectionName == 'Shawarma 4') {
            groupedSelections['Selected Shawarmas'] ??= [];
            groupedSelections['Selected Shawarmas']!.add(selectedOption);

            // DON'T add individual entries - only show grouped ones in cart
          } else if (sectionName.contains(' - Shawarma Options') ||
              sectionName.contains(' - Sauces (Optional)')) {
            // Handle shawarma-specific options and sauces with numbered format
            String numberAndSection = '';
            if (sectionName.startsWith('Shawarma 1 - ')) {
              String cleanSection = sectionName.replaceAll('Shawarma 1 - ', '');
              if (cleanSection == 'Shawarma Options') {
                numberAndSection = 'Shawarma 1 options';
              } else if (cleanSection == 'Sauces (Optional)') {
                numberAndSection = 'Shawarma 1 sauces (optional)';
              }
            } else if (sectionName.startsWith('Shawarma 2 - ')) {
              String cleanSection = sectionName.replaceAll('Shawarma 2 - ', '');
              if (cleanSection == 'Shawarma Options') {
                numberAndSection = 'Shawarma 2 options';
              } else if (cleanSection == 'Sauces (Optional)') {
                numberAndSection = 'Shawarma 2 sauces (optional)';
              }
            } else if (sectionName.startsWith('Shawarma 3 - ')) {
              String cleanSection = sectionName.replaceAll('Shawarma 3 - ', '');
              if (cleanSection == 'Shawarma Options') {
                numberAndSection = 'Shawarma 3 options';
              } else if (cleanSection == 'Sauces (Optional)') {
                numberAndSection = 'Shawarma 3 sauces (optional)';
              }
            } else if (sectionName.startsWith('Shawarma 4 - ')) {
              String cleanSection = sectionName.replaceAll('Shawarma 4 - ', '');
              if (cleanSection == 'Shawarma Options') {
                numberAndSection = 'Shawarma 4 options';
              } else if (cleanSection == 'Sauces (Optional)') {
                numberAndSection = 'Shawarma 4 sauces (optional)';
              }
            }
            selectedOptions.add('$numberAndSection: $selectedOption');
          } else if (sectionName == 'Drink & seasoning') {
            selectedOptions.add('Drink: $selectedOption');
          } else if (sectionName.contains(' - Chips Seasoning 1') ||
              sectionName.contains(' - Chips Seasoning 2')) {
            // Handle chips seasoning from Drink & seasoning tab
            String cleanSectionName = sectionName.replaceAll(
              'Drink & seasoning - ',
              '',
            );
            selectedOptions.add('$cleanSectionName: $selectedOption');
          } else {
            // Keep other selections as individual entries
            selectedOptions.add('$sectionName: $selectedOption');
          }
        }
      });

      // Add grouped selections to the TOP of the options list for display
      List<String> groupedDisplayOptions = [];
      groupedSelections.forEach((groupName, selections) {
        if (groupName == 'Selected Shawarmas' && selections.isNotEmpty) {
          // Special format for shawarmas: show count and flavor name
          String shawarmaName =
              selections
                  .first; // All should be the same (Chicken Shawarma (Pitta))
          groupedDisplayOptions.add(
            'Shawarma Flavour: ${selections.length}X $shawarmaName',
          );
        } else {
          groupedDisplayOptions.add('$groupName: ${selections.join(', ')}');
        }
      });

      // Insert grouped options at the beginning for cart display
      selectedOptions.insertAll(0, groupedDisplayOptions);

      // Add multi-select deal selections to options (sauces)
      _dealMultiSelections.forEach((sectionName, selectedOptionsSet) {
        if (selectedOptionsSet.isNotEmpty) {
          selectedOptions.add('$sectionName: ${selectedOptionsSet.join(', ')}');
        }
      });

      // Add default items for specific deals
      if (widget.foodItem.name.toLowerCase() == 'shawarma deal') {
        selectedOptions.add('Fries: 2x Fries');
      }
    }

    final String userComment = _reviewNotesController.text.trim();

    final cartItem = CartItem(
      foodItem: widget.foodItem,
      quantity: _quantity,
      selectedOptions: selectedOptions.isEmpty ? null : selectedOptions,
      comment: userComment.isNotEmpty ? userComment : null,
      pricePerUnit: _calculatedPricePerUnit,
    );
    widget.onAddToCart(cartItem);

    // Add a small delay before closing to ensure state updates
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        widget.onClose?.call();
      }
    });
  }

  // --- NEW Helper Method for button-based UI ---
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

  // --- NEW Helper Method for Salad option with Yes/No choices ---
  Widget _buildSaladOption() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'Salad',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.normal,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _saladChoice = 'Yes';
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _saladChoice == 'Yes' ? Colors.grey[100] : Colors.black,
                  foregroundColor:
                      _saladChoice == 'Yes' ? Colors.black : Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: const BorderSide(color: Colors.white, width: 1),
                  ),
                  elevation: _saladChoice == 'Yes' ? 4 : 2,
                ),
                child: const Text(
                  'Yes',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.normal),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _saladChoice = 'No';
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _saladChoice == 'No' ? Colors.grey[100] : Colors.black,
                  foregroundColor:
                      _saladChoice == 'No' ? Colors.black : Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: const BorderSide(color: Colors.white, width: 1),
                  ),
                  elevation: _saladChoice == 'No' ? 4 : 2,
                ),
                child: const Text(
                  'No',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.normal),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --- NEW: Kids Meal options widget ---
  Widget _buildKidsMealOptions() {
    bool hasChips =
        widget.foodItem.name.toLowerCase().contains('chips') ||
        widget.foodItem.name.toLowerCase().contains('fries');
    bool hasDrink = widget.foodItem.name.toLowerCase().contains('drink');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Show drinks only if the meal contains 'drink' in name
        if (hasDrink) ...[_buildDrinkSelectionSection()],

        // Show chip seasoning if the meal contains chips/fries
        if (hasChips) ...[
          if (hasDrink) const SizedBox(height: 20),
          _buildChipSeasoningSection(),
        ],
      ],
    );
  }

  // --- NEW: Chip seasoning selection widget ---
  Widget _buildChipSeasoningSection() {
    if (!_shouldShowChipSeasoningOptions()) {
      return const SizedBox.shrink();
    }

    final double modalWidth = min(
      MediaQuery.of(context).size.width * 0.95,
      1000.0,
    );
    const double horizontalPaddingOfParent = 30.0;
    final double availableWidthForWrap = modalWidth - horizontalPaddingOfParent;

    const double itemSpacing = 12.0;
    const int desiredColumns = 4;

    final double idealItemWidth =
        (availableWidthForWrap - (itemSpacing * (desiredColumns - 1))) /
        desiredColumns;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Text(
          'Chips Seasoning:',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 15),
        Wrap(
          spacing: itemSpacing,
          runSpacing: 15,
          alignment: WrapAlignment.start,
          children:
              _chipSeasoningOptions.map((seasoning) {
                final bool isActive = _selectedChipSeasoning == seasoning;
                return SizedBox(
                  width: idealItemWidth,
                  child: _buildOptionButton(
                    title: seasoning,
                    isActive: isActive,
                    onTap: () {
                      setState(() {
                        // Toggle selection - allow deselection
                        _selectedChipSeasoning = isActive ? null : seasoning;
                      });
                    },
                  ),
                );
              }).toList(),
        ),
      ],
    );
  }

  // --- MODIFIED `_buildMealAndExclusionOptions` method ---
  Widget _buildMealAndExclusionOptions() {
    return Center(
      // Wrap the entire content in a Center widget
      child: Column(
        mainAxisSize:
            MainAxisSize
                .min, // Ensure the column only takes up the space it needs
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Make it a Meal
              Expanded(
                child: _buildOptionButton(
                  title: 'Make it a Meal',
                  isActive: _makeItAMeal,
                  onTap: () {
                    setState(() {
                      _makeItAMeal = !_makeItAMeal;
                      if (!_makeItAMeal) {
                        _selectedDrink = null;
                        _selectedDrinkFlavor = null;
                        _selectedChipSeasoning = null; // Reset chip seasoning
                      }
                      _updatePriceDisplay();
                    });
                  },
                ),
              ),
              const SizedBox(width: 15),
              // Salad
              Expanded(child: _buildSaladOption()),
              const SizedBox(width: 15),
              // No Sauce
              Expanded(
                child: _buildOptionButton(
                  title: 'No Sauce',
                  isActive: _noSauce,
                  onTap: () {
                    setState(() {
                      _noSauce = !_noSauce;
                      if (_noSauce) {
                        // Clear all selected sauces when "No Sauce" is selected
                        _selectedSauces.clear();
                      }
                      _updatePriceDisplay();
                    });
                  },
                ),
              ),
            ],
          ),
          if (_makeItAMeal) ...[
            const SizedBox(height: 20),
            _buildDrinkSelectionSection(),
          ],
          // NEW: Add chip seasoning section
          _buildChipSeasoningSection(),
        ],
      ),
    );
  }

  // --- NEW METHOD for drink selection with buttons ---
  Widget _buildDrinkSelectionSection() {
    final double modalWidth = min(
      MediaQuery.of(context).size.width * 0.95,
      1000.0,
    );
    const double horizontalPaddingOfParent = 30.0;
    final double availableWidthForWrap = modalWidth - horizontalPaddingOfParent;

    const double itemSpacing = 12.0;
    const int desiredColumns = 5;

    final double idealItemWidth =
        (availableWidthForWrap - (itemSpacing * (desiredColumns - 1))) /
        desiredColumns;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Choose a Drink:',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 15),
        Wrap(
          spacing: itemSpacing,
          runSpacing: 15,
          alignment: WrapAlignment.start,
          children:
              _allDrinks.map((drink) {
                final bool isActive = _selectedDrink == drink;
                return SizedBox(
                  width: idealItemWidth,
                  child: _buildOptionButton(
                    title: drink,
                    isActive: isActive,
                    onTap: () {
                      setState(() {
                        _selectedDrink = drink;
                        // Reset flavor if the new drink doesn't have flavors or is different
                        if (!_drinkFlavors.containsKey(drink)) {
                          _selectedDrinkFlavor = null;
                        }
                        _updatePriceDisplay();
                      });
                    },
                  ),
                );
              }).toList(),
        ),
        if (_selectedDrink != null &&
            _drinkFlavors.containsKey(_selectedDrink!)) ...[
          const SizedBox(height: 20),
          _buildFlavorSelectionSection(_selectedDrink!),
        ],
      ],
    );
  }

  // --- MODIFIED METHOD for flavors with buttons ---
  Widget _buildFlavorSelectionSection(String drinkName) {
    final List<String> flavors = _drinkFlavors[drinkName] ?? [];

    if (flavors.isEmpty) {
      return const SizedBox.shrink();
    }

    final double modalWidth = min(
      MediaQuery.of(context).size.width * 0.95,
      1000.0,
    );
    const double horizontalPaddingOfParent = 30.0;
    final double availableWidthForWrap = modalWidth - horizontalPaddingOfParent;

    const double itemSpacing = 12.0;
    const int desiredColumns = 5;

    final double idealItemWidth =
        (availableWidthForWrap - (itemSpacing * (desiredColumns - 1))) /
        desiredColumns;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose a flavor for ${drinkName.capitalize()}:',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 15),
        Wrap(
          spacing: itemSpacing,
          runSpacing: 15,

          alignment: WrapAlignment.spaceBetween,
          children:
              flavors.map((flavor) {
                final bool isActive = _selectedDrinkFlavor == flavor;
                return SizedBox(
                  width: idealItemWidth,
                  child: _buildOptionButton(
                    title: flavor,
                    isActive: isActive,
                    onTap: () {
                      setState(() {
                        _selectedDrinkFlavor = flavor;
                      });
                    },
                  ),
                );
              }).toList(),
        ),
      ],
    );
  }

  // --- MODIFIED METHOD for milkshake options with a button ---
  Widget _buildQuantityControlOnly() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.foodItem.category == 'Milkshake') ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: _buildOptionButton(
                  title: 'No Cream',
                  isActive: _noCream,
                  onTap: () {
                    setState(() {
                      _noCream = !_noCream;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        // NEW: Add chip seasoning section for sides and kids meals
        _buildChipSeasoningSection(),
      ],
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
        // Handle sizes like '10 inch', '12 inch', etc.
        final parts = size.split(' ');
        if (parts.isNotEmpty) {
          return parts.first; // e.g., "10"
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

    bool kidsMealNeedsDrinkForValidation =
        widget.foodItem.category == 'KidsMeal' &&
        widget.foodItem.name.toLowerCase().contains('drink');

    bool canConfirmSelection = true;
    if ((widget.foodItem.price.keys.length > 1 && _selectedSize == null) ||
        (_makeItAMeal && _selectedDrink == null) ||
        (kidsMealNeedsDrinkForValidation && _selectedDrink == null) ||
        (_makeItAMeal &&
            _selectedDrink != null &&
            _drinkFlavors.containsKey(_selectedDrink!) &&
            _selectedDrinkFlavor == null) ||
        (kidsMealNeedsDrinkForValidation &&
            _selectedDrink != null &&
            _drinkFlavors.containsKey(_selectedDrink!) &&
            _selectedDrinkFlavor == null)) {
      canConfirmSelection = false;
    }
    if ((_drinkFlavors.containsKey(widget.foodItem.name) &&
        _selectedDrinkFlavor == null)) {
      canConfirmSelection = false;
    }

    // Deal validation - ensure all required selections are made
    if (widget.foodItem.category == 'Deals') {
      Map<String, List<String>> dealOptions = _getDealOptions(
        widget.foodItem.name,
      );

      // Check if all non-optional sections have selections
      for (String sectionName in dealOptions.keys) {
        bool isOptional = sectionName.toLowerCase().contains('optional');

        if (!isOptional) {
          bool isMultiSelect = sectionName.toLowerCase().contains('sauce');

          if (isMultiSelect) {
            // For multi-select sections, check if something is selected
            if (_dealMultiSelections[sectionName] == null ||
                _dealMultiSelections[sectionName]!.isEmpty) {
              canConfirmSelection = false;
              break;
            }
          } else {
            // For single-select sections, check if something is selected
            if (_dealSelections[sectionName] == null) {
              canConfirmSelection = false;
              break;
            }
          }
        }
      }
    }

    debugPrint("Item Category: ${widget.foodItem.category}");
    debugPrint(
      "Price keys length for rendering: ${widget.foodItem.price.keys.length}",
    );
    debugPrint("Is in size selection mode: $_isInSizeSelectionMode");
    debugPrint("Size has been selected: $_sizeHasBeenSelected");

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
      },
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
            // Header with item name, selected size, and quantity controls
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
                  // Left side: Selected size (if any)
                  Expanded(
                    flex: 1,
                    child:
                        _sizeHasBeenSelected &&
                                _selectedSize != null &&
                                !_isInSizeSelectionMode
                            ? Row(
                              children: [
                                // Size label with rectangular black background (now clickable)
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
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize:
                                              _getDisplaySize(
                                                        _selectedSize!,
                                                      ).toLowerCase() ==
                                                      'default'
                                                  ? 12
                                                  : _getDisplaySize(
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

                  Expanded(
                    flex: 1,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (_sizeHasBeenSelected &&
                            !_isInSizeSelectionMode) ...[
                          // Quantity controls
                          InkWell(
                            onTapDown: (_) {
                              setState(() {
                                _isRemoveButtonPressed = true;
                              });
                            },
                            onTapUp: (_) {
                              setState(() {
                                _isRemoveButtonPressed = false;
                              });
                            },
                            onTapCancel: () {
                              setState(() {
                                _isRemoveButtonPressed = false;
                              });
                            },
                            onTap: () {
                              setState(() {
                                if (_quantity > 1) {
                                  _quantity--;
                                }
                                _updatePriceDisplay(); // Update price on quantity change
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
                            onTapDown: (_) {
                              setState(() {
                                _isAddButtonPressed = true;
                              });
                            },
                            onTapUp: (_) {
                              setState(() {
                                _isAddButtonPressed = false;
                              });
                            },
                            onTapCancel: () {
                              setState(() {
                                _isAddButtonPressed = false;
                              });
                            },
                            onTap: () {
                              setState(() {
                                _quantity++;
                                _updatePriceDisplay(); // Update price on quantity change
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
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 60,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),

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
                      if (!_sizeHasBeenSelected) ...[
                        _buildQuantityControlOnly(),
                      ],

                      if (_drinkFlavors.containsKey(widget.foodItem.name)) ...[
                        _buildFlavorSelectionSection(widget.foodItem.name),
                        // NEW: Add chip seasoning for drinks with flavors that might have chips
                        _buildChipSeasoningSection(),
                      ],

                      if (widget.foodItem.category == 'Pizza' ||
                          widget.foodItem.category == 'GarlicBread') ...[
                        _buildOptionCategoryButtons(),
                        _buildSelectedOptionDisplay(),
                      ],

                      if ([
                        'Shawarma',
                        'Wraps',
                        'Burgers',
                      ].contains(widget.foodItem.category)) ...[
                        _buildMealAndExclusionOptions(),
                        const SizedBox(height: 20),
                        _buildSauceOptionsForCategory(),
                      ],

                      if (widget.foodItem.category == 'KidsMeal') ...[
                        _buildKidsMealOptions(),
                      ],

                      if (widget.foodItem.category == 'Milkshake') ...[
                        _buildQuantityControlOnly(),
                      ],

                      if (widget.foodItem.category == 'Deals') ...[
                        _buildDealCategoryButtons(),
                        _buildDealSelectionOptions(),
                        // NEW: Add chip seasoning for deals
                        _buildChipSeasoningSection(),
                      ],

                      const SizedBox(height: 20),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Review Notes',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _reviewNotesController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Colors.grey[100]!,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Colors.grey[100]!,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Colors.white,
                                ),
                              ),
                              hintText: 'Add any special requests or notes...',
                              hintStyle: const TextStyle(color: Colors.white),
                              contentPadding: const EdgeInsets.all(12),
                            ),
                            maxLines: 3,
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ],
                ),
              ),
            ),

            // Footer with total and buttons
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border(top: BorderSide(color: Colors.grey[100]!)),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
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
                            canConfirmSelection
                                ? _confirmSelection
                                : null, // Changed to _confirmSelection
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
                          // Dynamic text based on mode
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          InkWell(
            onTap: () {
              // Close size selection if a size has been selected
              if (_selectedSize != null) {
                setState(() {
                  _isInSizeSelectionMode = false;
                });
              }
            },
            child: Container(
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
          ),
          const SizedBox(width: 10),

          Wrap(
            spacing: 15,
            runSpacing: 15,
            alignment: WrapAlignment.center,
            children:
                widget.foodItem.price.keys.map((sizeKeyFromData) {
                  final bool isActive = _selectedSize == sizeKeyFromData;
                  final String displayedText = _getDisplaySize(sizeKeyFromData);

                  return SizedBox(
                    width: 110,
                    height: 110,
                    child: ElevatedButton(
                      onPressed: () => _onSizeSelected(sizeKeyFromData),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            isActive ? Colors.grey[100] : Colors.black,
                        foregroundColor: isActive ? Colors.black : Colors.white,
                        shape: const CircleBorder(
                          side: BorderSide(color: Colors.white, width: 4),
                        ),
                        padding: EdgeInsets.zero,
                        elevation: isActive ? 6 : 3,
                      ),
                      child: Text(
                        displayedText,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize:
                              displayedText.toLowerCase() == 'default'
                                  ? 16
                                  : displayedText.length > 5
                                  ? 20
                                  : 26,
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

  Widget _buildDealCategoryButtons() {
    Map<String, List<String>> dealOptions = _getDealOptions(
      widget.foodItem.name,
    );
    final List<String> categories = _getDealCategories(dealOptions);

    if (categories.length <= 1) {
      // No tabs needed if only one category
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(categories.length, (index) {
            final category = categories[index];
            final bool isSelected = _selectedDealCategory == category;

            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 4.0,
                  right: index == categories.length - 1 ? 0 : 4.0,
                ),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedDealCategory = category;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.grey[100] : Colors.black,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        category,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected ? Colors.black : Colors.white,
                          fontSize:
                              category.length > 15
                                  ? 14
                                  : category.length > 10
                                  ? 16
                                  : 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildOptionCategoryButtons() {
    final List<String> categories = ['Toppings', 'Base', 'Crust', 'Sauce Dips'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children:
              List.generate(categories.length, (index) {
                final category = categories[index];
                final bool isSelected = _selectedOptionCategory == category;

                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 4.0,
                      right: index == categories.length - 1 ? 0 : 4.0,
                    ),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _selectedOptionCategory = category;
                        });
                      },
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
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildSelectedOptionDisplay() {
    final List<String> reorderedToppings = List.from(_allToppings);
    reorderedToppings.sort((a, b) {
      final isDefaultA =
          (widget.foodItem.defaultToppings ?? []).contains(a) ||
          (widget.foodItem.defaultCheese ?? []).contains(a);
      final isDefaultB =
          (widget.foodItem.defaultToppings ?? []).contains(b) ||
          (widget.foodItem.defaultCheese ?? []).contains(b);
      if (isDefaultA && !isDefaultB) return -1;
      if (!isDefaultA && isDefaultB) return 1;
      return a.compareTo(b);
    });

    switch (_selectedOptionCategory) {
      case 'Toppings':
        return _buildToppingsDisplay(reorderedToppings);
      case 'Base':
        return _buildBaseDisplay();
      case 'Crust':
        return _buildCrustDisplay();
      case 'Sauce Dips':
        return _buildSauceDisplay();
      default:
        return const SizedBox.shrink();
    }
  }

  // --- Original `_buildToppingsDisplay` method (unchanged) ---
  Widget _buildToppingsDisplay(List<String> allToppings) {
    // 1. Get the list of default toppings and cheeses
    final defaultToppingsAndCheese =
        [
          ...(widget.foodItem.defaultToppings ?? []),
          ...(widget.foodItem.defaultCheese ?? []),
        ].toSet().toList();

    // 2. Get the list of all other toppings
    final allOtherToppings =
        allToppings
            .where((topping) => !defaultToppingsAndCheese.contains(topping))
            .toList();

    // 3. Sort the other toppings by string length
    allOtherToppings.sort((a, b) => a.length.compareTo(b.length));

    // 4. Combine the two lists, with default toppings first
    final List<String> sortedToppings = [
      ...defaultToppingsAndCheese,
      ...allOtherToppings,
    ];

    final double modalWidth = min(
      MediaQuery.of(context).size.width * 0.95,
      1000.0,
    );
    final double horizontalPaddingOfParent = 30.0;
    final double availableWidthForWrap = modalWidth - horizontalPaddingOfParent;

    const double itemSpacing = 12.0;
    const int desiredColumns = 5;

    final double idealItemWidth =
        (availableWidthForWrap - (itemSpacing * (desiredColumns - 1))) /
        desiredColumns;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: itemSpacing,
          runSpacing: 15,
          alignment: WrapAlignment.spaceBetween,
          children:
              sortedToppings.map((topping) {
                final bool isActive = _selectedToppings.contains(topping);
                final bool isDefault = defaultToppingsAndCheese.contains(
                  topping,
                );

                return SizedBox(
                  width: idealItemWidth,
                  child: InkWell(
                    onTap: () {
                      // --- DEFAULT TOPPINGS WILL NOT BE UNSELECTED ---
                      if (isDefault) {
                        return; // Do nothing if it's a default topping
                      }
                      setState(() {
                        if (_selectedToppings.contains(topping)) {
                          _selectedToppings.remove(topping);
                        } else {
                          _selectedToppings.add(topping);
                        }
                        _updatePriceDisplay();
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 18,
                        horizontal: 18,
                      ),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isActive ? Colors.grey[100] : Colors.black,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        topping,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isActive ? Colors.black : Colors.white,
                          fontSize: 18,
                          fontWeight:
                              isDefault ? FontWeight.bold : FontWeight.normal,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                );
              }).toList(),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildBaseDisplay() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 15,
          runSpacing: 15,
          alignment: WrapAlignment.start,
          children:
              _allBases.map((base) {
                final bool isActive = _selectedBase == base;
                final bool isTomato = base == "Tomato";

                return InkWell(
                  onTap: () {
                    setState(() {
                      if (isTomato && isActive) {
                        return;
                      }
                      _selectedBase = base;
                      _updatePriceDisplay();
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (isActive || isTomato)
                              ? Colors.grey[100]
                              : Colors.black,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      base,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color:
                            (isActive || isTomato)
                                ? Colors.black
                                : Colors.white,
                        fontSize: 18,
                        fontWeight:
                            isTomato && isActive
                                ? FontWeight.bold
                                : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              }).toList(),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildCrustDisplay() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 15,
          runSpacing: 15,
          alignment: WrapAlignment.start,
          children:
              _allCrusts.map((crust) {
                final bool isActive = _selectedCrust == crust;

                return InkWell(
                  onTap: () {
                    setState(() {
                      _selectedCrust = crust;
                      _updatePriceDisplay();
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      color: isActive ? Colors.grey[100] : Colors.black,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      crust,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isActive ? Colors.black : Colors.white,
                        fontSize: 18,
                      ),
                    ),
                  ),
                );
              }).toList(),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildSauceDisplay() {
    final double modalWidth = min(
      MediaQuery.of(context).size.width * 0.9,
      900.0,
    );
    final double horizontalPaddingOfParent = 40.0;
    final double availableWidthForWrap = modalWidth - horizontalPaddingOfParent;

    const double itemSpacing = 12.0;
    const int desiredColumns = 3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: itemSpacing,
          runSpacing: 15,
          children:
              _allSauces.map((sauce) {
                final bool isActive = _selectedSauces.contains(sauce);
                return SizedBox(
                  width:
                      (availableWidthForWrap -
                          (itemSpacing * (desiredColumns - 1))) /
                      desiredColumns,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        if (_selectedSauces.contains(sauce)) {
                          _selectedSauces.remove(sauce);
                        } else {
                          _selectedSauces.add(sauce);
                        }
                        _updatePriceDisplay();
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                      decoration: BoxDecoration(
                        color: isActive ? Colors.grey[100] : Colors.black,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        sauce,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isActive ? Colors.black : Colors.white,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // Deal-specific selection options with tab system
  Widget _buildDealSelectionOptions() {
    // Get deal-specific options based on the deal name
    Map<String, List<String>> dealOptions = _getDealOptions(
      widget.foodItem.name,
    );

    print('🔍 UI: Building deal options for "${widget.foodItem.name}"');
    print('🔍 UI: Available deal options: ${dealOptions.keys.toList()}');
    print('🔍 UI: Selected deal category: "$_selectedDealCategory"');

    if (dealOptions.isEmpty) {
      // Just show the description for simple deals
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Deal Includes:',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.foodItem.description ?? 'Complete meal deal',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      );
    }

    // Special handling for different deal types with multiple sections within each tab
    if (widget.foodItem.name.toLowerCase() == 'shawarma deal') {
      if (_selectedDealCategory.startsWith('Shawarma ')) {
        return _buildShawarmaTabContent(_selectedDealCategory, dealOptions);
      } else if (_selectedDealCategory == 'Drink & seasoning') {
        return _buildDrinkAndSeasoningTabContent(
          _selectedDealCategory,
          dealOptions,
        );
      } else {
        // For any other tab in shawarma deal, default to Shawarma 1
        return _buildShawarmaTabContent('Shawarma 1', dealOptions);
      }
    }

    // Special handling for Family Meal and Combo Meal
    if (widget.foodItem.name.toLowerCase() == 'family meal' ||
        widget.foodItem.name.toLowerCase() == 'combo meal') {
      return _buildFamilyComboMealTabContent(
        _selectedDealCategory,
        dealOptions,
      );
    }

    // Original logic for both editing and non-editing mode (show only selected category)
    List<String> currentOptions = dealOptions[_selectedDealCategory] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Show options in toppings-style grid layout
        if (currentOptions.isNotEmpty)
          _buildToppingsStyleGrid(currentOptions, _selectedDealCategory)
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'No options available',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
      ],
    );
  }

  // Special content builder for Shawarma tabs with multiple sections
  Widget _buildShawarmaTabContent(
    String tabName,
    Map<String, List<String>> dealOptions,
  ) {
    List<String> shawarmaOptions = dealOptions[tabName] ?? [];

    // Auto-select the default shawarma immediately if not already selected
    if (shawarmaOptions.isNotEmpty && _dealSelections[tabName] == null) {
      _dealSelections[tabName] =
          shawarmaOptions
              .first; // Auto-select Chicken Shawarma (Pitta) immediately
    }

    // Define the options and sauces for each shawarma
    List<String> shawarmaChoices = ['With Salad', 'No Salad'];
    List<String> sauceChoices = [
      'Mayo',
      'Ketchup',
      'Chilli Sauce',
      'Sweet Chilli',
      'Garlic Sauce',
      'No Extra Sauce',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Shawarma selection section (auto-selected, no text label)
        if (shawarmaOptions.isNotEmpty) ...[
          _buildToppingsStyleGrid(shawarmaOptions, tabName),
          const SizedBox(height: 25),
        ],

        // Shawarma Options section
        const Text(
          'Shawarma Options:',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 15),
        _buildToppingsStyleGrid(shawarmaChoices, '$tabName - Shawarma Options'),
        const SizedBox(height: 25),

        // Sauces section
        const Text(
          'Sauces (Optional):',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 15),
        _buildToppingsStyleGrid(sauceChoices, '$tabName - Sauces (Optional)'),
      ],
    );
  }

  // Special content builder for Drink & seasoning tab with multiple sections
  Widget _buildDrinkAndSeasoningTabContent(
    String tabName,
    Map<String, List<String>> dealOptions,
  ) {
    List<String> drinkOptions = dealOptions[tabName] ?? [];

    // Define the seasoning options for chips
    List<String> seasoningChoices = [
      'No Seasoning',
      'White Salt',
      'Red Salt',
      'Vinegar',
      'Salt and Vinegar',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Drink selection section
        if (drinkOptions.isNotEmpty) ...[
          const Text(
            'Select Drink:',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 15),
          _buildToppingsStyleGrid(drinkOptions, tabName),
          const SizedBox(height: 25),
        ],

        // Chips Seasoning 1 section
        const Text(
          'Chips Seasoning 1:',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 15),
        _buildToppingsStyleGrid(
          seasoningChoices,
          '$tabName - Chips Seasoning 1',
        ),
        const SizedBox(height: 25),

        // Chips Seasoning 2 section
        const Text(
          'Chips Seasoning 2:',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 15),
        _buildToppingsStyleGrid(
          seasoningChoices,
          '$tabName - Chips Seasoning 2',
        ),
      ],
    );
  }

  // Special content builder for Family Meal and Combo Meal tabs with multiple sections
  Widget _buildFamilyComboMealTabContent(
    String tabName,
    Map<String, List<String>> dealOptions,
  ) {
    List<String> mainOptions = dealOptions[tabName] ?? [];

    // Define sauce options
    List<String> sauceOptions = [
      'Mayo',
      'Ketchup',
      'Chilli Sauce',
      'Sweet Chilli',
      'Garlic Sauce',
      'No Extra Sauce',
    ];

    // Build content based on tab type
    if (tabName.contains('Pizza')) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pizza selection
          const Text(
            'Select Pizza:',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 15),
          _buildToppingsStyleGrid(mainOptions, tabName),
          const SizedBox(height: 25),

          // Pizza Sauces (Optional)
          const Text(
            'Pizza Sauces (Optional):',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 15),
          _buildToppingsStyleGrid(sauceOptions, '$tabName - Sauces (Optional)'),
        ],
      );
    } else if (tabName.contains('Shawarma')) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Shawarma selection
          const Text(
            'Select Shawarma:',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 15),
          _buildToppingsStyleGrid(mainOptions, tabName),
          const SizedBox(height: 25),

          // Shawarma Options
          const Text(
            'Shawarma Options:',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 15),
          _buildToppingsStyleGrid([
            'With Salad',
            'No Salad',
          ], '$tabName - Options'),
          const SizedBox(height: 25),

          // Shawarma Sauces (Optional)
          const Text(
            'Shawarma Sauces (Optional):',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 15),
          _buildToppingsStyleGrid(sauceOptions, '$tabName - Sauces (Optional)'),
        ],
      );
    } else if (tabName.contains('Burger')) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Burger selection
          const Text(
            'Select Burger:',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 15),
          _buildToppingsStyleGrid(mainOptions, tabName),
          const SizedBox(height: 25),

          // Burger Options
          const Text(
            'Burger Options:',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 15),
          _buildToppingsStyleGrid([
            'With Salad',
            'No Salad',
          ], '$tabName - Options'),
          const SizedBox(height: 25),

          // Burger Sauces (Optional)
          const Text(
            'Burger Sauces (Optional):',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 15),
          _buildToppingsStyleGrid(sauceOptions, '$tabName - Sauces (Optional)'),
        ],
      );
    } else if (tabName.contains('Calzone')) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Calzone selection
          const Text(
            'Select Calzone:',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 15),
          _buildToppingsStyleGrid(mainOptions, tabName),
        ],
      );
    } else if (tabName.contains('Drinks')) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drink selection
          const Text(
            'Select Drink:',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 15),
          _buildToppingsStyleGrid(mainOptions, tabName),
        ],
      );
    }

    // Default fallback
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$tabName:',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 15),
        _buildToppingsStyleGrid(mainOptions, tabName),
      ],
    );
  }

  // Build toppings-style grid for deal options
  Widget _buildToppingsStyleGrid(List<String> options, String dealKey) {
    print('🔍 UI: Building grid for "$dealKey" with options: $options');
    print(
      '🔍 UI: Current selection for "$dealKey": ${_dealSelections[dealKey]}',
    );
    final double modalWidth = min(
      MediaQuery.of(context).size.width * 0.95,
      1000.0,
    );
    final double horizontalPaddingOfParent = 30.0;
    final double availableWidthForWrap = modalWidth - horizontalPaddingOfParent;

    const double itemSpacing = 12.0;
    const int desiredColumns = 5;

    final double idealItemWidth =
        (availableWidthForWrap - (itemSpacing * (desiredColumns - 1))) /
        desiredColumns;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: itemSpacing,
          runSpacing: 15,
          alignment: WrapAlignment.start,
          children:
              options.map((option) {
                // Check if this is a multi-select option (like sauces)
                final bool isMultiSelect = dealKey.toLowerCase().contains(
                  'sauce',
                );

                final bool isSelected;
                if (isMultiSelect) {
                  // For multi-select options, check _dealMultiSelections
                  isSelected =
                      _dealMultiSelections[dealKey]?.contains(option) ?? false;
                } else {
                  // For single-select options, check _dealSelections
                  isSelected = _dealSelections[dealKey] == option;
                }
                print(
                  '🔍 UI OPTION: "$option" for "$dealKey" - isSelected: $isSelected',
                );

                return SizedBox(
                  width: idealItemWidth,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        if (isMultiSelect) {
                          // Handle multi-select options (sauces)
                          if (!_dealMultiSelections.containsKey(dealKey)) {
                            _dealMultiSelections[dealKey] = <String>{};
                          }

                          if (isSelected) {
                            _dealMultiSelections[dealKey]!.remove(option);
                          } else {
                            _dealMultiSelections[dealKey]!.add(option);
                          }
                        } else {
                          // Handle single-select options
                          _dealSelections[dealKey] = isSelected ? null : option;
                        }
                        _updatePriceDisplay();
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 18,
                        horizontal: 18,
                      ),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.grey[100] : Colors.black,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        option,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isSelected ? Colors.black : Colors.white,
                          fontSize:
                              option.length > 20
                                  ? 12
                                  : option.length > 15
                                  ? 14
                                  : 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Poppins',
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                );
              }).toList(),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  List<String> _getDealCategories(Map<String, List<String>> dealOptions) {
    // Return the actual deal keys as tabs (Pizza 1, Pizza (16"), Shawarma, etc.)
    return dealOptions.keys.toList();
  }

  Map<String, List<String>> _getDealOptions(String dealName) {
    // Get dynamic menu items
    final pizzaOptions = _getPizzaFlavoursFromMenu();
    final shawarmaOptions = _getShawarmaOptionsFromMenu();
    final burgerOptions = _getBurgerOptionsFromMenu();
    final calzoneOptions = _getCalzoneOptionsFromMenu();

    switch (dealName.toLowerCase()) {
      case 'family meal':
        return {
          'Pizza (16")': pizzaOptions,
          'Shawarma': shawarmaOptions,
          'Burger': burgerOptions,
          'Calzone': calzoneOptions,
          'Drinks': [
            'Coca Cola (1.5L)',
            'Pepsi (1.5L)',
            '7Up (1.5L)',
            'Fanta (1.5L)',
            'Sprite (1.5L)',
          ],
        };
      case 'combo meal':
        return {
          'Pizza (12")': pizzaOptions,
          'Shawarma': shawarmaOptions,
          'Burger': burgerOptions,
          'Drinks': [
            'Coca Cola (1.5L)',
            'Pepsi (1.5L)',
            '7Up (1.5L)',
            'Fanta (1.5L)',
            'Sprite (1.5L)',
          ],
        };
      case 'pizza offers':
        return {
          'Pizza 1': pizzaOptions,
          'Pizza 2': pizzaOptions,
          'Pizza 3': pizzaOptions,
          'Drink (1.5L)': ['Coca Cola', 'Pepsi', '7Up', 'Fanta', 'Sprite'],
        };
      case 'shawarma deal':
        final shawarmaOptionsForDeal = _getShawarmaOptionsForDeal();
        return {
          'Shawarma 1': shawarmaOptionsForDeal,
          'Shawarma 2': shawarmaOptionsForDeal,
          'Shawarma 3': shawarmaOptionsForDeal,
          'Shawarma 4': shawarmaOptionsForDeal,
          'Drink & seasoning': [
            'Coca Cola (1.5L)',
            'Pepsi (1.5L)',
            '7Up (1.5L)',
            'Fanta (1.5L)',
            'Sprite (1.5L)',
          ],
        };
      default:
        return {};
    }
  }

  Widget _buildSauceOptionsForCategory() {
    final double modalWidth = min(
      MediaQuery.of(context).size.width * 0.95,
      1000.0,
    );
    const double horizontalPaddingOfParent = 30.0;
    final double availableWidthForWrap = modalWidth - horizontalPaddingOfParent;

    const double itemSpacing = 12.0;
    const int desiredColumns = 5;

    final double idealItemWidth =
        (availableWidthForWrap - (itemSpacing * (desiredColumns - 1))) /
        desiredColumns;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sauce Options:',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 24,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 15),
        Wrap(
          spacing: itemSpacing,
          runSpacing: 15,
          alignment: WrapAlignment.start,
          children:
              _allSauces.map((sauce) {
                final bool isSelected = _selectedSauces.contains(sauce);
                return SizedBox(
                  width: idealItemWidth,
                  child: _buildOptionButton(
                    title: sauce,
                    isActive: isSelected,
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedSauces.remove(sauce);
                        } else {
                          _selectedSauces.add(sauce);
                          // Clear "No Sauce" flag when selecting actual sauces
                          _noSauce = false;
                        }
                        _updatePriceDisplay();
                      });
                    },
                  ),
                );
              }).toList(),
        ),
      ],
    );
  }
}
