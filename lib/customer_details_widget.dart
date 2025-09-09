import 'package:flutter/material.dart';
import 'package:epos/models/order_models.dart';
import 'package:epos/services/order_api_service.dart';
import 'package:epos/models/customer_search_model.dart';
import 'package:epos/services/custom_popup_service.dart';

class CustomerDetailsWidget extends StatefulWidget {
  final double subtotal;
  final String orderType;
  final Function(CustomerDetails) onCustomerDetailsSubmitted;
  final VoidCallback? onBack;
  final CustomerDetails? initialCustomerData;

  const CustomerDetailsWidget({
    super.key,
    required this.subtotal,
    required this.orderType,
    required this.onCustomerDetailsSubmitted,
    this.onBack,
    this.initialCustomerData,
  });

  @override
  State<CustomerDetailsWidget> createState() => _CustomerDetailsWidgetState();
}

class _CustomerDetailsWidgetState extends State<CustomerDetailsWidget> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _postalCodeController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();

    // Populate fields with initial data
    _populateInitialData();

    // Add listeners to text controllers to update button states
    _nameController.addListener(_updateButtonStates);
    _phoneController.addListener(_updateButtonStates);
    _emailController.addListener(_updateButtonStates);
    _addressController.addListener(_updateButtonStates);
    _cityController.addListener(_updateButtonStates);
    _postalCodeController.addListener(_updateButtonStates);
  }

  // Method to populate fields with initial data
  void _populateInitialData() {
    if (widget.initialCustomerData != null) {
      final data = widget.initialCustomerData!;

      // Populate basic fields
      if (data.name != 'Walk-in Customer') {
        _nameController.text = data.name;
      }
      if (data.phoneNumber != 'N/A') {
        _phoneController.text = data.phoneNumber;
      }
      if (data.email != null) {
        _emailController.text = data.email!;
      }

      // Populate address fields only for delivery orders
      if (widget.orderType.toLowerCase() == 'delivery') {
        if (data.streetAddress != null) {
          _addressController.text = data.streetAddress!;
        }
        if (data.city != null) {
          _cityController.text = data.city!;
        }
        if (data.postalCode != null) {
          _postalCodeController.text = data.postalCode!;
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _postalCodeController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _updateButtonStates() {
    setState(() {
      // This will trigger a rebuild to update button states
    });
  }

  // Check if any customer details are filled
  bool _hasCustomerDetails() {
    return _nameController.text.trim().isNotEmpty ||
        _phoneController.text.trim().isNotEmpty ||
        _emailController.text.trim().isNotEmpty ||
        _addressController.text.trim().isNotEmpty ||
        _cityController.text.trim().isNotEmpty ||
        _postalCodeController.text.trim().isNotEmpty;
  }

  // Helper method to get display text for order type
  String _getDisplayOrderType() {
    String orderType = widget.orderType.toLowerCase();
    switch (orderType) {
      case 'collection':
      case 'takeaway':
        return 'COLLECTION';
      case 'delivery':
        return 'DELIVERY';
      default:
        return widget.orderType.toUpperCase();
    }
  }

  final RegExp _nameRegExp = RegExp(r"^[a-zA-Z\s-']+$");
  final RegExp _emailRegExp = RegExp(
    r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+",
  );

  bool _validateUKPhoneNumber(String phoneNumber) {
    if (phoneNumber.isEmpty) return false;
    String cleanedNumber = phoneNumber.replaceAll(RegExp(r'[()\s-]'), '');
    final RegExp finalUkPhoneRegex = RegExp(r'^(?:(?:\+|00)44|0)\d{9,10}$');
    return finalUkPhoneRegex.hasMatch(cleanedNumber);
  }

  // Helper method to check if field is required based on order type
  bool _isFieldRequired(String fieldType) {
    String orderType = widget.orderType.toLowerCase();
    switch (fieldType) {
      case 'name':
      case 'phone':
        return orderType == 'delivery';
      case 'email':
        return false; // Email is now optional for all order types
      case 'address':
      case 'city':
      case 'postal':
        return orderType == 'delivery';
      default:
        return false;
    }
  }

  // Helper method to get label text with proper asterisk
  String _getFieldLabel(String baseLabel, String fieldType) {
    if (_isFieldRequired(fieldType)) {
      return '$baseLabel *';
    } else {
      return '$baseLabel (Optional)';
    }
  }

  Future<void> _searchCustomer() async {
    FocusScope.of(context).unfocus();

    if (_phoneController.text.isEmpty) {
      if (_isFieldRequired('phone')) {
        _formKey.currentState?.validate();
        return;
      } else {
        CustomPopupService.show(
          context,
          "Please enter a phone number to search for existing customer",
          type: PopupType.failure,
        );
        return;
      }
    }

    if (!_validateUKPhoneNumber(_phoneController.text)) {
      _formKey.currentState?.validate();
      return;
    }

    setState(() {
      _isSearching = true;
    });

    String phoneNumberToSend = _phoneController.text.trim().replaceAll(
      RegExp(r'[()\s-]'),
      '',
    );

    try {
      final CustomerSearchResponse? customer =
          await OrderApiService.searchCustomerByPhoneNumber(phoneNumberToSend);

      if (customer != null) {
        _nameController.text = customer.name;
        _emailController.text = customer.email ?? '';
        _phoneController.text = customer.phoneNumber;

        if (widget.orderType.toLowerCase() == 'delivery') {
          if (customer.address != null) {
            _addressController.text = customer.address!.street;
            _cityController.text = customer.address!.city;
            _postalCodeController.text = customer.address!.postalCode;
          } else {
            _addressController.clear();
            _cityController.clear();
            _postalCodeController.clear();
          }
        } else {
          _addressController.clear();
          _cityController.clear();
          _postalCodeController.clear();
        }

        CustomPopupService.show(
          context,
          'Customer found and details filled',
          type: PopupType.success,
        );
      } else {
        CustomPopupService.show(
          context,
          "Phone number not found. Please enter details manually to proceed",
          type: PopupType.failure,
        );
        _nameController.clear();
        _emailController.clear();
        if (widget.orderType.toLowerCase() == 'delivery') {
          _addressController.clear();
          _cityController.clear();
          _postalCodeController.clear();
        }
      }
    } catch (e) {
      CustomPopupService.show(
        context,
        "Error searching customer ",
        type: PopupType.failure,
      );
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isCollectionOrTakeaway =
        widget.orderType.toLowerCase() == 'collection' ||
        widget.orderType.toLowerCase() == 'takeaway';
    bool hasDetails = _hasCustomerDetails();

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 20.0, bottom: 16.0),
            child: Row(
              children: [
                if (widget.onBack != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 3.0),
                    child: ElevatedButton(
                      onPressed: widget.onBack,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.black.withOpacity(0.1),
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22.5),
                        ),
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(45, 45),
                      ),
                      child: Image.asset(
                        'assets/images/bArrow.png',
                        fit: BoxFit.contain,
                        width: 45,
                        height: 45,
                      ),
                    ),
                  ),
                Expanded(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3D9FF),
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Text(
                        'Customer Details (${_getDisplayOrderType()})',
                        style: const TextStyle(
                          fontSize: 23,
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

          const SizedBox(height: 9),

          if (isCollectionOrTakeaway)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 42.0),
              child: Divider(thickness: 2, color: Colors.grey),
            ),

          const SizedBox(height: 30),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: RawScrollbar(
                controller: _scrollController,
                thumbVisibility: false,
                trackVisibility: false,
                thickness: 10.0,
                radius: const Radius.circular(30),
                interactive: true,
                thumbColor: const Color(0xFFF2D9F9),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          Container(
                            margin: const EdgeInsets.only(bottom: 20),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _phoneController,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontFamily: 'Poppins',
                                    ),
                                    decoration: InputDecoration(
                                      labelText: _getFieldLabel(
                                        'Phone Number',
                                        'phone',
                                      ),
                                      hintText:
                                          'e.g., 07123456789 or +44 7123 456789',
                                      labelStyle: const TextStyle(
                                        fontSize: 16,
                                        fontFamily: 'Poppins',
                                        color: Colors.grey,
                                      ),
                                      hintStyle: const TextStyle(
                                        fontSize: 14,
                                        fontFamily: 'Poppins',
                                        color: Colors.grey,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(15),
                                        borderSide: const BorderSide(
                                          color: Colors.grey,
                                          width: 1,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(15),
                                        borderSide: const BorderSide(
                                          color: Color(0xFFCB6CE6),
                                          width: 2.0,
                                        ),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 20,
                                            vertical: 20,
                                          ),
                                    ),
                                    keyboardType: TextInputType.phone,
                                    validator: (value) {
                                      if (_isFieldRequired('phone') &&
                                          (value == null || value.isEmpty)) {
                                        return 'Please enter phone number';
                                      }
                                      if (value != null &&
                                          value.isNotEmpty &&
                                          !_validateUKPhoneNumber(value)) {
                                        return 'Please enter a valid UK phone number';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                ElevatedButton(
                                  onPressed:
                                      _isSearching ? null : _searchCustomer,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        _isSearching
                                            ? Colors.grey
                                            : Colors.black,
                                    foregroundColor: Colors.white.withOpacity(
                                      0.3,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    minimumSize: const Size(60, 60),
                                    padding: EdgeInsets.zero,
                                  ),
                                  child: Center(
                                    child:
                                        _isSearching
                                            ? const CircularProgressIndicator(
                                              color: Colors.white,
                                            )
                                            : const Icon(
                                              Icons.search,
                                              color: Colors.white,
                                              size: 28,
                                            ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          Container(
                            margin: const EdgeInsets.only(bottom: 20),
                            child: TextFormField(
                              controller: _nameController,
                              style: const TextStyle(
                                fontSize: 18,
                                fontFamily: 'Poppins',
                              ),
                              decoration: InputDecoration(
                                labelText: _getFieldLabel(
                                  'Customer Name',
                                  'name',
                                ),
                                labelStyle: const TextStyle(
                                  fontSize: 16,
                                  fontFamily: 'Poppins',
                                  color: Colors.grey,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15),
                                  borderSide: const BorderSide(
                                    color: Colors.grey,
                                    width: 1,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFCB6CE6),
                                    width: 2.0,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 20,
                                ),
                              ),
                              validator: (value) {
                                if (_isFieldRequired('name') &&
                                    (value == null || value.isEmpty)) {
                                  return 'Please enter customer name';
                                }
                                if (value != null &&
                                    value.isNotEmpty &&
                                    !_nameRegExp.hasMatch(value)) {
                                  return 'Name can only contain letters, spaces, hyphens, or apostrophes';
                                }
                                return null;
                              },
                            ),
                          ),

                          Container(
                            margin: const EdgeInsets.only(bottom: 20),
                            child: TextFormField(
                              controller: _emailController,
                              style: const TextStyle(
                                fontSize: 18,
                                fontFamily: 'Poppins',
                              ),
                              decoration: InputDecoration(
                                labelText: _getFieldLabel('Email', 'email'),
                                labelStyle: const TextStyle(
                                  fontSize: 16,
                                  fontFamily: 'Poppins',
                                  color: Colors.grey,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15),
                                  borderSide: const BorderSide(
                                    color: Colors.grey,
                                    width: 1,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFCB6CE6),
                                    width: 2.0,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 20,
                                ),
                              ),
                              keyboardType: TextInputType.emailAddress,
                              validator: (value) {
                                if (value != null &&
                                    value.isNotEmpty &&
                                    !_emailRegExp.hasMatch(value)) {
                                  return 'Enter a valid email address';
                                }
                                return null;
                              },
                            ),
                          ),

                          if (widget.orderType.toLowerCase() == 'delivery') ...[
                            Container(
                              margin: const EdgeInsets.only(bottom: 20),
                              child: TextFormField(
                                controller: _addressController,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontFamily: 'Poppins',
                                ),
                                decoration: InputDecoration(
                                  labelText: _getFieldLabel(
                                    'Street Address',
                                    'address',
                                  ),
                                  labelStyle: const TextStyle(
                                    fontSize: 16,
                                    fontFamily: 'Poppins',
                                    color: Colors.grey,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(15),
                                    borderSide: const BorderSide(
                                      color: Colors.grey,
                                      width: 1,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(15),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFCB6CE6),
                                      width: 2.0,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 20,
                                  ),
                                ),
                                validator: (value) {
                                  if (_isFieldRequired('address') &&
                                      (value == null || value.isEmpty)) {
                                    return 'Please enter street address';
                                  }
                                  return null;
                                },
                              ),
                            ),

                            Container(
                              margin: const EdgeInsets.only(bottom: 20),
                              child: TextFormField(
                                controller: _cityController,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontFamily: 'Poppins',
                                ),
                                decoration: InputDecoration(
                                  labelText: _getFieldLabel('City', 'city'),
                                  labelStyle: const TextStyle(
                                    fontSize: 16,
                                    fontFamily: 'Poppins',
                                    color: Colors.grey,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(15),
                                    borderSide: const BorderSide(
                                      color: Colors.grey,
                                      width: 1,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(15),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFCB6CE6),
                                      width: 2.0,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 20,
                                  ),
                                ),
                                validator: (value) {
                                  if (_isFieldRequired('city') &&
                                      (value == null || value.isEmpty)) {
                                    return 'Please enter city';
                                  }
                                  return null;
                                },
                              ),
                            ),

                            Container(
                              margin: const EdgeInsets.only(bottom: 20),
                              child: TextFormField(
                                controller: _postalCodeController,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontFamily: 'Poppins',
                                ),
                                decoration: InputDecoration(
                                  labelText: _getFieldLabel(
                                    'Postal Code',
                                    'postal',
                                  ),
                                  labelStyle: const TextStyle(
                                    fontSize: 16,
                                    fontFamily: 'Poppins',
                                    color: Colors.grey,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(15),
                                    borderSide: const BorderSide(
                                      color: Colors.grey,
                                      width: 1,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(15),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFCB6CE6),
                                      width: 2.0,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 20,
                                  ),
                                ),
                                validator: (value) {
                                  if (_isFieldRequired('postal') &&
                                      (value == null || value.isEmpty)) {
                                    return 'Please enter postal code';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 55.0),
            child: Divider(
              height: 0,
              thickness: 3,
              color: const Color(0xFFB2B2B2),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Subtotal',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Poppins',
                      ),
                    ),
                    Text(
                      '£${widget.subtotal.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    if (isCollectionOrTakeaway) ...[
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            final customerDetails = CustomerDetails(
                              name: 'Walk-in Customer',
                              phoneNumber: 'N/A',
                              email: null,
                              streetAddress: null,
                              city: null,
                              postalCode: null,
                            );
                            widget.onCustomerDetailsSubmitted(customerDetails);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white.withOpacity(0.3),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 20),
                          ),
                          child: const Text(
                            'Skip',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],

                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          if (isCollectionOrTakeaway && !hasDetails) {
                            CustomPopupService.show(
                              context,
                              "Please enter customer details to Continue or use Skip button",
                              type: PopupType.success,
                            );
                            return;
                          }

                          if (_formKey.currentState!.validate()) {
                            final customerDetails = CustomerDetails(
                              name:
                                  _nameController.text.trim().isEmpty
                                      ? 'Walk-in Customer'
                                      : _nameController.text.trim(),
                              phoneNumber:
                                  _phoneController.text.trim().isEmpty
                                      ? 'N/A'
                                      : _phoneController.text.trim(),
                              email:
                                  _emailController.text.trim().isEmpty
                                      ? null
                                      : _emailController.text.trim(),
                              streetAddress:
                                  _addressController.text.trim().isEmpty
                                      ? null
                                      : _addressController.text.trim(),
                              city:
                                  _cityController.text.trim().isEmpty
                                      ? null
                                      : _cityController.text.trim(),
                              postalCode:
                                  _postalCodeController.text.trim().isEmpty
                                      ? null
                                      : _postalCodeController.text.trim(),
                            );
                            widget.onCustomerDetailsSubmitted(customerDetails);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white.withOpacity(0.3),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 20),
                        ),
                        child: const Text(
                          'Next',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                            fontFamily: 'Poppins',
                          ),
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
    );
  }
}
