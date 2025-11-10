import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart';

/// Cross-platform wrapper that loads the hosted admin portal.
class AdminPanelWebViewScreen extends StatefulWidget {
  const AdminPanelWebViewScreen({super.key});

  @override
  State<AdminPanelWebViewScreen> createState() =>
      _AdminPanelWebViewScreenState();
}

class _AdminPanelWebViewScreenState extends State<AdminPanelWebViewScreen> {
  static final Uri _adminUri = Uri.parse('https://supersubs.uk/admin');

  WebViewController? _mobileController;
  WebviewController? _windowsController;
  StreamSubscription<LoadingState>? _windowsLoadingSub;
  StreamSubscription<HistoryChanged>? _windowsHistorySub;

  double _mobileProgress = 0.0;
  bool _isWindowsLoading = false;
  bool _windowsInitialized = false;
  bool _canGoBack = false;
  bool _canGoForward = false;
  String? _errorMessage;

  late final bool _useWindowsWebView;
  late final bool _useWebViewFlutter;

  @override
  void initState() {
    super.initState();
    _useWindowsWebView = !kIsWeb && Platform.isWindows;
    _useWebViewFlutter =
        !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

    if (_useWindowsWebView) {
      unawaited(_initWindowsController());
    } else if (_useWebViewFlutter) {
      _initMobileController();
    } else {
      _errorMessage =
          'Admin panel embedding is not supported on this platform. Please open https://supersubs.uk/admin in your browser.';
    }
  }

  Future<void> _initWindowsController() async {
    final controller = WebviewController();
    _windowsController = controller;
    try {
      await controller.initialize();
      await controller.setBackgroundColor(Colors.white);
      await controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);

      _windowsLoadingSub = controller.loadingState.listen((state) {
        if (!mounted) return;
        setState(() {
          _isWindowsLoading = state == LoadingState.loading;
        });
      });
      _windowsHistorySub = controller.historyChanged.listen((history) {
        if (!mounted) return;
        setState(() {
          _canGoBack = history.canGoBack;
          _canGoForward = history.canGoForward;
        });
      });

      await controller.loadUrl(_adminUri.toString());
      if (!mounted) return;
      setState(() {
        _windowsInitialized = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Unable to initialize embedded browser. Please ensure the Microsoft Edge WebView2 runtime is installed.\nDetails: $e';
      });
    }
  }

  void _initMobileController() {
    final controller =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.white)
          ..setNavigationDelegate(
            NavigationDelegate(
              onProgress: (progress) {
                if (!mounted) return;
                setState(() {
                  _mobileProgress = progress / 100;
                });
              },
              onPageFinished: (_) => _updateMobileNavigationState(),
              onPageStarted: (_) => _updateMobileNavigationState(),
              onWebResourceError: (error) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Failed to load page (${error.errorType?.name}).',
                    ),
                  ),
                );
              },
            ),
          )
          ..loadRequest(_adminUri);
    _mobileController = controller;
    unawaited(_updateMobileNavigationState());
  }

  Future<void> _updateMobileNavigationState() async {
    final controller = _mobileController;
    if (controller == null) return;
    final back = await controller.canGoBack();
    final forward = await controller.canGoForward();
    if (!mounted) return;
    setState(() {
      _canGoBack = back;
      _canGoForward = forward;
    });
  }

  bool get _isWebViewReady =>
      (_useWindowsWebView &&
          _windowsInitialized &&
          _windowsController != null) ||
      (_useWebViewFlutter && _mobileController != null);

  Future<bool> _handleWillPop() async {
    if (_useWindowsWebView && _canGoBack) {
      await _windowsController?.goBack();
      return false;
    }
    final controller = _mobileController;
    if (_useWebViewFlutter && controller != null) {
      if (await controller.canGoBack()) {
        await controller.goBack();
        return false;
      }
    }
    return true;
  }

  Future<void> _handleReload() async {
    if (_useWindowsWebView) {
      await _windowsController?.reload();
    } else {
      await _mobileController?.reload();
    }
  }

  Future<void> _handleBackNavigation() async {
    if (!_canGoBack) return;
    if (_useWindowsWebView) {
      await _windowsController?.goBack();
    } else {
      await _mobileController?.goBack();
      unawaited(_updateMobileNavigationState());
    }
  }

  Future<void> _handleForwardNavigation() async {
    if (!_canGoForward) return;
    if (_useWindowsWebView) {
      await _windowsController?.goForward();
    } else {
      await _mobileController?.goForward();
      unawaited(_updateMobileNavigationState());
    }
  }

  Widget _buildBody() {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_useWindowsWebView) {
      if (!_windowsInitialized || _windowsController == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return Webview(_windowsController!);
    }

    final controller = _mobileController;
    if (controller != null) {
      return WebViewWidget(controller: controller);
    }

    return const SizedBox.shrink();
  }

  Widget _buildProgressBar() {
    final showMobile =
        !_useWindowsWebView && _mobileProgress > 0 && _mobileProgress < 1;
    final showWindows = _useWindowsWebView && _isWindowsLoading;

    if (!showMobile && !showWindows) {
      return const SizedBox.shrink();
    }

    return LinearProgressIndicator(
      value: showMobile ? _mobileProgress : null,
      backgroundColor: Colors.grey.shade300,
      color: Colors.greenAccent,
    );
  }

  @override
  void dispose() {
    _windowsLoadingSub?.cancel();
    _windowsHistorySub?.cancel();
    _windowsController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Supersubs Admin'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              tooltip: 'Reload',
              onPressed: _isWebViewReady ? _handleReload : null,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Back',
              onPressed:
                  _isWebViewReady && _canGoBack ? _handleBackNavigation : null,
              icon: const Icon(Icons.arrow_back_ios_new),
            ),
            IconButton(
              tooltip: 'Forward',
              onPressed:
                  _isWebViewReady && _canGoForward
                      ? _handleForwardNavigation
                      : null,
              icon: const Icon(Icons.arrow_forward_ios),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(3),
            child: _buildProgressBar(),
          ),
        ),
        body: _buildBody(),
      ),
    );
  }
}
