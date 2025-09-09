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
- **Dart**: SDK ^3.7.2

### Utility Widgets
- **DebouncedButton** (`lib/widgets/debounced_button.dart`) - Button with built-in debouncing to prevent multiple rapid clicks
- **PostalCodesTableWidget** (`lib/widgets/postal_codes_table_widget.dart`) - Table widget for displaying delivery postal code analytics
- **OfflineStatusWidget** (`lib/widgets/offline_status_widget.dart`) - Visual indicator for connection status
- **LiveUpdatingPill** (`lib/widgets/live_updating_pill.dart`) - Dynamic status pill component
- **ReceiptPreviewDialog** (`lib/widgets/receipt_preview_dialog.dart`) - Preview dialog for receipt formatting
- **ItemsTableWidget** (`lib/widgets/items_table_widget.dart`) - Table widget for displaying item lists
- **PaidOutsTableWidget** (`lib/widgets/paidouts_table_widget.dart`) - Table widget for paid out transaction management

## Architecture

### Provider State Management
The app uses Flutter Provider for state management with a complex dependency graph that must be maintained carefully:

**Critical Provider Dependencies (in main.dart:44-189):**
1. **OrderCountsProvider** - Base provider for order counts (non-lazy)
2. **ActiveOrdersProvider** - Depends on OrderCountsProvider, manages active orders (non-lazy)
3. **EposOrdersProvider** - Depends on ActiveOrdersProvider, handles EPOS-specific orders (non-lazy)
4. **Additional Providers**: 
- **OrderProvider** (WebsiteOrdersProvider) - Website order management
- **FoodItemDetailsProvider** - Menu item details and state
- **Page4StateProvider** - Main ordering screen state (cart, categories, search)
- **SalesReportProvider** - Sales analytics and reporting
- **PaidOutProvider** - Paid out transactions management
- **ItemAvailabilityProvider** - Menu item availability tracking
- **OfflineProvider** - Offline functionality coordination
- **DriverOrderProvider** - Driver delivery order management with live polling

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
- **CartPersistenceService** (`lib/services/cart_persistence_service.dart`) - Cart state persistence across sessions
- **CustomPopupService** (`lib/services/custom_popup_service.dart`) - Custom modal and popup management
- **DriverApiService** (`lib/services/driver_api_service.dart`) - Driver-specific API operations
- **NotificationAudioService** (`lib/services/notification_audio_service.dart`) - Audio notification management
- **OfflineOrderManager** (`lib/services/offline_order_manager.dart`) - Advanced offline order handling

### Multi-Brand Support
Brand configuration is handled in `lib/config/brand_info.dart`:
- Current brand is set via `_currentBrand` constant ('TVP', 'Dallas', 'SuperSub', 'TEST')
- Default headers include brand identification for API calls
- Headers include both 'brand' and 'x-client-id' fields
- Currently set to 'TVP' brand in the codebase

### Data Models & Hive Integration
- **FoodItem** (`lib/models/food_item.dart`) - Menu item structure with pricing, availability
- **Order** (`lib/models/order.dart`) - Order data structure for API communication
- **OfflineOrder** (`lib/models/offline_order.dart`) - Hive model for offline orders (requires code generation)
- **CartItem** (`lib/models/cart_item.dart`) - Shopping cart items with options and comments
- **CustomerSearchModel** (`lib/models/customer_search_model.dart`) - Customer lookup functionality
- **OrderModels** (`lib/models/order_models.dart`) - Order-related data structures
- **PaidoutModels** (`lib/models/paidout_models.dart`) - Paid out transaction data structures
- **PrinterDevice** (`lib/models/printer_device.dart`) - Thermal printer device configuration

**Hive Setup:**
- Uses TypeId 0, 1, 2 for OfflineOrder, OfflineCartItem, OfflineFoodItem
- Generated files (*.g.dart) are auto-created via build_runner
- Requires running `dart run build_runner build` when models change
- Offline orders automatically sync when connectivity returns

### Main Navigation Flow
1. **Main** (`lib/main.dart`) → Loads menu items via ApiService and initializes all providers
2. **MainAppWrapper** (`lib/main_app_wrapper.dart`) → App-wide wrapper with WebSocket connectivity and comprehensive order notification system
3. **Page3** (`lib/page3.dart`) → Service selection screen (Dine In, Take Away, Delivery)
4. **Page4** (`lib/page4.dart`) → Main ordering interface with menu categories and cart
5. **Website Orders Screen** (`lib/website_orders_screen.dart`) → Driver/delivery order management
6. **Sales Report Screen** (`lib/sales_report_screen.dart`) → Analytics and reporting interface
7. **Admin Portal Screen** (`lib/admin_portal_screen.dart`) → Administrative functions and management
8. **Driver Management Screen** (`lib/driver_management_screen.dart`) → Driver assignment and tracking
9. **Edit Items Screen** (`lib/edit_items_screen.dart`) → Menu item management and configuration
10. **Settings Screen** (`lib/settings_screen.dart`) → Application configuration

### Backend Integration
- **Primary URL**: `https://corsproxy.io/?https://thevillage-backend.onrender.com`
- **Alternative Proxy**: Multiple fallback proxies for reliability (cors-anywhere, allorigins, etc.)
- **WebSocket Integration**: Real-time order updates via `socket_io_client`
- **CORS Handling**: Uses CORS proxy services to bypass browser restrictions
- **Brand Headers**: All requests automatically include brand identification via `BrandInfo.getDefaultHeaders()`
- **Failover Logic**: Automatic retry with alternative proxy services if primary fails

### Offline Functionality
- **Local Storage**: Hive database with boxes: offline_orders, order_counter, connectivity_status
- **Automatic Sync**: OfflineProvider manages sync when connectivity returns
- **Order Queuing**: Offline orders queued with retry logic and attempt tracking
- **Services**: OfflineStorageService, ConnectivityService, OfflineOrderManager for comprehensive offline support
- **Sync Status**: Real-time sync status tracking with error logging and recovery

### Printing Support
- **Bluetooth Printing**: Thermal printer integration via `print_bluetooth_thermal`
- **USB Serial Printing**: Direct printer connection via `usb_serial`
- **Receipt Generation**: Customizable formatting using `esc_pos_utils_plus`
- **Preview System**: Receipt preview dialogs before printing
- **Mock Mode**: Testing mode available with ENABLE_MOCK_MODE flag
- **Duplicate Prevention**: Global tracking to prevent duplicate receipt printing

### Testing & Quality
- Uses `flutter_lints` package for static analysis (analysis_options.yaml)
- Basic widget test setup in `test/widget_test.dart`
- Test currently expects counter functionality (needs updating for actual app)
- Run tests with `flutter test`
- Linting with `flutter analyze`
- Static analysis configuration follows Flutter recommended practices

### Key Dependencies
**Core Framework & State Management:**
- **Provider** (^6.1.5) - State management with complex dependency injection
- **flutter** & **cupertino_icons** (^1.0.8) - UI framework and icons

**Database & Storage:**
- **Hive** (^2.2.3) + **hive_flutter** (^1.1.0) - Local NoSQL database for offline functionality
- **path_provider** (^2.1.5) - File system path access

**Networking & Communication:**
- **http** (^1.4.0) - HTTP client for REST API requests
- **socket_io_client** (^3.1.2) - Real-time WebSocket communication
- **connectivity_plus** (^6.1.5) - Network connectivity monitoring

**Printing & Receipt Generation:**
- **print_bluetooth_thermal** (^1.1.0) - Bluetooth thermal printer support
- **flutter_blue_plus** (^1.35.5) - Bluetooth device discovery and connection
- **usb_serial** (^0.5.2) - USB serial printer support
- **esc_pos_utils_plus** (^2.0.4) - ESC/POS receipt formatting
- **printing** (^5.14.2) - Document printing capabilities
- **pdf** (^3.11.3) - PDF generation for receipts

**UI & User Experience:**
- **google_fonts** (^6.3.0) - Custom font loading (Poppins family)
- **fl_chart** (^1.0.0) - Interactive charts for sales reporting
- **flutter_html** (^3.0.0) - HTML content rendering
- **screenshot** (^3.0.0) - Screen capture functionality
- **audioplayers** (^6.1.0) - Audio notifications for orders

**Utilities:**
- **uuid** (^4.5.1) - Unique identifier generation
- **intl** (^0.20.2) - Internationalization and date formatting
- **timezone** (^0.10.1) - Time zone handling utilities
- **phone_numbers_parser** (^9.0.3) - Phone number validation
- **permission_handler** (^12.0.1) - Device permissions management

**Development Tools:**
- **flutter_lints** (^5.0.0) - Static analysis and code quality
- **hive_generator** (^2.0.1) + **build_runner** (^2.4.13) - Code generation for Hive models

**Dependency Overrides:**
- **image** (^4.5.4) - Image processing utilities
- **rxdart** (^0.28.0) - Reactive extensions for Dart

## Important Files to Understand
**Core Application Files:**
- `lib/main.dart` - App initialization and critical provider setup with dependency chain
- `lib/main_app_wrapper.dart` - App-wide wrapper with WebSocket connectivity and order notifications
- `lib/config/brand_info.dart` - Multi-brand configuration and API headers

**Main Screens:**
- `lib/page3.dart` - Service selection screen (Dine In, Take Away, Delivery)
- `lib/page4.dart` - Main ordering interface with cart management
- `lib/website_orders_screen.dart` - Driver/delivery order management
- `lib/admin_portal_screen.dart` - Administrative functions
- `lib/edit_items_screen.dart` - Menu item management and configuration
- `lib/sales_report_screen.dart` - Analytics and reporting

**Services:**
- `lib/services/api_service.dart` - Backend communication with CORS proxy and failover
- `lib/services/order_api_service.dart` - WebSocket order management
- `lib/services/thermal_printer_service.dart` - Receipt printing management
- `lib/services/offline_storage_service.dart` - Hive database management
- `lib/services/notification_audio_service.dart` - Audio notification system

**Data Models:**
- `lib/models/offline_order.dart` - Hive models requiring code generation
- `lib/models/order.dart` - Main order data structure
- `lib/models/food_item.dart` - Menu item structure
- `lib/models/paidout_models.dart` - Paid out transaction models

**Configuration:**
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
1. **OrderCountsProvider** (base, no dependencies)
2. **ActiveOrdersProvider** (depends on OrderCountsProvider)
3. **EposOrdersProvider** (depends on ActiveOrdersProvider)
4. All other providers can depend on these three

**Warning**: Breaking this chain will cause provider recreation and complete state loss across the application.

### Notification System (MainAppWrapper)
**Advanced Order Notification Features:**
- **Duplicate Prevention**: Multiple layers of protection using global tracking maps
- **Status Change Detection**: Monitors order status transitions for cancellation notifications
- **Global Dismissed Tracking**: Orders dismissed once never reappear during session
- **Processing Locks**: Prevents duplicate processing within 30-second windows
- **Automatic Cleanup**: Removes old processed orders from memory every 5 minutes
- **Receipt Integration**: Automatic receipt printing with duplicate prevention

### Brand Switching
To switch brands, modify `_currentBrand` in `lib/config/brand_info.dart`. Available options:
- 'TVP'
- 'Dallas' 
- 'SuperSub'
- 'TEST' (current default)

All API calls automatically include brand headers via `BrandInfo.getDefaultHeaders()`.