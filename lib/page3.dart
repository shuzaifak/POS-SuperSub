// lib/page3.dart

import 'package:flutter/material.dart';
import 'models/food_item.dart';
import 'package:epos/active_orders_list.dart';
import 'package:epos/custom_bottom_nav_bar.dart';
import 'package:epos/services/thermal_printer_service.dart';
import 'package:epos/services/custom_popup_service.dart';

class Page3 extends StatefulWidget {
  final List<FoodItem> foodItems;

  const Page3({super.key, required this.foodItems});

  @override
  State<Page3> createState() => _Page3State();
}

class _Page3State extends State<Page3> {
  int _selectedBottomNavItem = 4;
  bool _canOpenDrawer = false;
  bool _isDrawerOpening = false;

  @override
  void initState() {
    super.initState();
    _checkDrawerAvailability();
  }

  // Method to handle bottom nav item selection
  void _onBottomNavItemSelected(int index) {
    setState(() {
      _selectedBottomNavItem = index;
    });
  }

  // Cash drawer methods
  Future<void> _checkDrawerAvailability() async {
    try {
      bool canOpen = await ThermalPrinterService().canOpenDrawer();
      if (mounted) {
        setState(() {
          _canOpenDrawer = canOpen;
        });
      }
    } catch (e) {
      print('Error checking drawer availability: $e');
    }
  }

  Future<void> _openCashDrawer() async {
    if (_isDrawerOpening || !_canOpenDrawer) return;

    setState(() {
      _isDrawerOpening = true;
    });

    try {
      bool success = await ThermalPrinterService().openCashDrawer(
        reason: "Manual open from main screen",
      );

      if (mounted) {
        CustomPopupService.show(
          context,
          success ? '💰 Cash drawer opened' : '❌ Failed to open cash drawer',
          type: success ? PopupType.success : PopupType.failure,
        );
      }
    } catch (e) {
      print('Error opening cash drawer: $e');
      if (mounted) {
        CustomPopupService.show(
          context,
          '❌ Cash drawer error: $e',
          type: PopupType.failure,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDrawerOpening = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        // <--- Left section (2/3 of the screen) - Service Selection
                        flex: 2,
                        child: Column(
                          children: [
                            const SizedBox(height: 30),

                            // surge logo
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 30),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3D9FF),
                                  borderRadius: BorderRadius.circular(60),
                                ),
                                child: Image.asset(
                                  'assets/images/sLogo.png',
                                  height: 95,
                                  width: 350,
                                ),
                              ),
                            ),

                            // Service options
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 75,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        _buildServiceOption(
                                          'Collection',
                                          'TakeAway.png',
                                          'takeaway',
                                          0,
                                        ),
                                        _buildServiceOption(
                                          'Dine In',
                                          'DineIn.png',
                                          'dinein',
                                          1,
                                        ),
                                        _buildServiceOption(
                                          'Delivery',
                                          'Delivery.png',
                                          'delivery',
                                          2,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20.0),
                        child: const VerticalDivider(
                          width: 3,
                          thickness: 3,
                          color: const Color(0xFFB2B2B2),
                        ),
                      ),

                      Expanded(
                        // <--- Right section (1/3 of the screen) - Active Orders List
                        flex: 1,
                        child: Container(
                          color: Colors.white,
                          child: const ActiveOrdersList(),
                        ),
                      ),
                    ],
                  ),
                ),
                // <--- CUSTOM BOTTOM NAVIGATION BAR
                CustomBottomNavBar(
                  selectedIndex: _selectedBottomNavItem,
                  onItemSelected: _onBottomNavItemSelected,
                  showDivider: true, // Set to true if you want the top divider
                ),
              ],
            ),
          ),

          // Cash drawer button positioned in top-right corner
          if (_canOpenDrawer)
            Positioned(
              top: 20,
              right: 20,
              child: GestureDetector(
                onTap: _isDrawerOpening ? null : _openCashDrawer,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color:
                        _isDrawerOpening
                            ? Colors.grey
                            : const Color(0xFF4CAF50),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: (_isDrawerOpening
                                ? Colors.grey
                                : const Color(0xFF4CAF50))
                            .withOpacity(0.3),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Center(
                    child:
                        _isDrawerOpening
                            ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 3,
                              ),
                            )
                            : const Icon(
                              Icons.money,
                              color: Colors.white,
                              size: 32,
                            ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildServiceOption(
    String title,
    String imageName,
    String orderType,
    int initialBottomNavItemIndex,
  ) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          print(
            "Page3: Service option '$title' tapped. Navigating to Page4 with orderType: $orderType.",
          );
          Navigator.pushNamed(
            context,
            '/page4',
            arguments: {
              'initialSelectedServiceImage': imageName,
              'selectedOrderType': orderType,
            },
          );
        },
        child: Column(
          children: [
            Image.asset(
              'assets/images/$imageName',
              width: title.toLowerCase() == 'delivery' ? 225 : 170,
              height: title.toLowerCase() == 'delivery' ? 225 : 170,
              fit: BoxFit.contain,
              color: const Color(0xFF575858),
            ),
            // Align spacing for labels
            SizedBox(height: title.toLowerCase() == 'delivery' ? 0 : 50),

            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 170),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2D9F9),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Center(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                      fontFamily: 'Poppins',
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
}
