# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Flutter-based EPOS (Electronic Point of Sale) system designed for restaurants/food service businesses. The app handles order management, inventory tracking, payment processing, and receipt generation with support for multiple brands (TVP, Dallas, SuperSub).

## Development Commands

### Flutter Commands
- `flutter pub get` - Install dependencies
- `flutter run` - Run the app in debug mode
- `flutter test` - Run unit tests
- `flutter analyze` - Run static analysis (uses flutter_lints package)
- `flutter build apk` - Build Android APK
- `flutter build appbundle` - Build Android App Bundle

### Code Generation (for Hive database models)
- `dart run build_runner build` - Generate Hive adapters
- `dart run build_runner build --delete-conflicting-outputs` - Regenerate adapters

### Environment Requirements
- **Flutter SDK**: ^3.7.2
- **Dart**: Compatible with Flutter 3.7.2+

### Additional Services
- **CartPersistenceService** (`lib/services/cart_persistence_service.dart`) - Cart state persistence across sessions
- **CustomPopupService** (`lib/services/custom_popup_service.dart`) - Custom modal and popup management
- **DriverApiService** (`lib/services/driver_api_service.dart`) - Driver-specific API operations
- **OfflineOrderManager** (`lib/services/offline_order_manager.dart`) - Advanced offline order handling
- **ReceiptGeneratorService** (`lib/services/receipt_generator_service.dart`) - Receipt formatting and generation

## Architecture

### Provider State Management
The app uses Flutter Provider for state management with a complex dependency graph that must be maintained carefully:

**Critical Provider Dependencies (in main.dart:41-178):**
1. **OrderCountsProvider** - Base provider for order counts (non-lazy)
2. **ActiveOrdersProvider** - Depends on OrderCountsProvider, manages active orders (non-lazy)
3. **EposOrdersProvider** - Depends on ActiveOrdersProvider, handles EPOS-specific orders (non-lazy)
4. **Additional Providers**: 
- **OrderProvider** (WebsiteOrdersProvider) - Website order management
- **FoodItemDetailsProvider** - Menu item details and state
- **Page4StateProvider** - Main ordering screen state (cart, categories, search)
- **SalesReportProvider** - Sales analytics and reporting
- **ItemAvailabilityProvider** - Menu item availability tracking
- **OfflineProvider** - Offline functionality coordination
- **DriverOrderProvider** - Driver delivery order management

**Provider Setup Rules:**
- All providers are set to `lazy: false` to prevent state loss
- ChangeNotifierProxyProvider update methods always return existing provider to prevent recreation
- Provider creation includes extensive debug logging

### Key Services
- **ApiService** (`lib/services/api_service.dart`) - Main API communication with backend using CORS proxy
- **OrderApiService** (`lib/services/order_api_service.dart`) - Order-specific API operations with WebSocket support
- **ThermalPrinterService** (`lib/services/thermal_printer_service.dart`) - Receipt printing via Bluetooth/USB
- **OfflineStorageService** (`lib/services/offline_storage_service.dart`) - Local data persistence using Hive
- **ConnectivityService** (`lib/services/connectivity_service.dart`) - Network connectivity monitoring
- **UKTimeService** (`lib/services/uk_time_service.dart`) - Time zone handling for orders

### Multi-Brand Support
Brand configuration is handled in `lib/config/brand_info.dart`:
- Current brand is set via `_currentBrand` constant ('TVP', 'Dallas', 'SuperSub')
- Default headers include brand identification for API calls
- Headers include both 'brand' and 'x-client-id' fields

### Data Models & Hive Integration
- **FoodItem** (`lib/models/food_item.dart`) - Menu item structure with pricing, availability
- **Order** (`lib/models/order.dart`) - Order data structure for API communication
- **OfflineOrder** (`lib/models/offline_order.dart`) - Hive model for offline orders (requires code generation)
- **CartItem** (`lib/models/cart_item.dart`) - Shopping cart items with options and comments
- **CustomerSearchModel** (`lib/models/customer_search_model.dart`) - Customer lookup functionality
- **OrderModels** (`lib/models/order_models.dart`) - Order-related data structures
- **PrinterDevice** (`lib/models/printer_device.dart`) - Thermal printer device configuration

**Hive Setup:**
- Uses TypeId 0, 1, 2 for OfflineOrder, OfflineCartItem, OfflineFoodItem
- Generated files (*.g.dart) are auto-created via build_runner
- Requires running `dart run build_runner build` when models change
- Offline orders automatically sync when connectivity returns

### Main Navigation Flow
1. **Main** (`lib/main.dart`) → Loads menu items via ApiService and initializes all providers
2. **MainAppWrapper** (`lib/main_app_wrapper.dart`) → App-wide wrapper with WebSocket connectivity and new order notifications
3. **Page3** (`lib/page3.dart`) → Service selection screen (Dine In, Take Away, Delivery)
4. **Page4** (`lib/page4.dart`) → Main ordering interface with menu categories and cart
5. **Website Orders Screen** - Driver/delivery order management
6. **Sales Report Screen** - Analytics and reporting interface

### Backend Integration
- Base URL: `https://corsproxy.io/?https://thevillage-backend.onrender.com`
- Alternative proxy available for failover
- WebSocket integration via `socket_io_client` for real-time order updates
- All requests include brand headers from BrandInfo.getDefaultHeaders()

### Offline Functionality
- Local storage using Hive database with three boxes: offline_orders, order_counter, connectivity_status
- Automatic sync when connectivity returns via OfflineProvider
- Order queuing for offline scenarios with retry logic
- Sync status tracking with attempt counting and error logging

### Printing Support
- Thermal printer integration via Bluetooth (`print_bluetooth_thermal`)
- USB serial printer support (`usb_serial`)
- Receipt generation with customizable formatting using `esc_pos_utils_plus`
- Mock mode available for testing (ENABLE_MOCK_MODE flag)

### Testing & Quality
- Uses `flutter_lints` package for static analysis (analysis_options.yaml)
- Basic widget test setup in `test/widget_test.dart`
- Test currently expects counter functionality (needs updating for actual app)
- Run tests with `flutter test`
- Linting with `flutter analyze`

### Key Dependencies
- **Provider** (^6.1.5) - State management
- **Hive** (^2.2.3) + hive_flutter (^1.1.0) - Local database
- **socket_io_client** (^3.1.2) - Real-time WebSocket communication
- **print_bluetooth_thermal** (^1.1.0) - Bluetooth receipt printing
- **connectivity_plus** (^6.1.5) - Network connectivity monitoring
- **esc_pos_utils_plus** (^2.0.4) - Receipt formatting
- **fl_chart** (^1.0.0) - Sales reporting charts
- **http** (^1.4.0) - HTTP client for API requests
- **flutter_lints** (^5.0.0) - Static analysis and linting

## Important Files to Understand
- `lib/main.dart` - App initialization and critical provider setup with dependency chain
- `lib/main_app_wrapper.dart` - App-wide wrapper with WebSocket and connectivity handling
- `lib/page3.dart` - Service selection screen
- `lib/page4.dart` - Main ordering interface with cart management
- `lib/config/brand_info.dart` - Multi-brand configuration and API headers
- `lib/models/offline_order.dart` - Hive models requiring code generation
- `lib/services/api_service.dart` - Backend communication with CORS proxy setup
- `pubspec.yaml` - Dependencies and project configuration

## Development Guidelines

### Code Generation Workflow
When modifying Hive models:
1. Make changes to model files (e.g., `lib/models/offline_order.dart`)
2. Run `dart run build_runner build --delete-conflicting-outputs`
3. Verify generated `.g.dart` files are updated
4. Test offline functionality after changes

### Provider Modification Guidelines
**CRITICAL**: When modifying providers, maintain the exact dependency chain order in `main.dart`:
1. OrderCountsProvider (base, no dependencies)
2. ActiveOrdersProvider (depends on OrderCountsProvider)
3. EposOrdersProvider (depends on ActiveOrdersProvider)
4. All other providers can depend on these three

Breaking this chain will cause provider recreation and state loss.

### Brand Switching
To switch brands, modify `_currentBrand` in `lib/config/brand_info.dart`. Available options:
- 'TVP' (default)
- 'Dallas' 
- 'SuperSub'

All API calls automatically include brand headers via `BrandInfo.getDefaultHeaders()`.