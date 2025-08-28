// lib/services/notification_audio_service.dart

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class NotificationAudioService {
  static final NotificationAudioService _instance = NotificationAudioService._internal();
  factory NotificationAudioService() => _instance;
  NotificationAudioService._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();

  /// Play notification sound for new orders
  Future<void> playNewOrderSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/order-success.mp3'));
      if (kDebugMode) {
        print('🔊 Playing new order notification sound');
      }
    } catch (e) {
      if (kDebugMode) {
        print('🔇 Failed to play new order sound: $e');
      }
    }
  }

  /// Play notification sound for cancelled orders
  Future<void> playCancelOrderSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/order-success.mp3'));
      if (kDebugMode) {
        print('🔊 Playing cancel order notification sound');
      }
    } catch (e) {
      if (kDebugMode) {
        print('🔇 Failed to play cancel order sound: $e');
      }
    }
  }

  /// Stop any currently playing notification sound
  Future<void> stopSound() async {
    try {
      await _audioPlayer.stop();
    } catch (e) {
      if (kDebugMode) {
        print('🔇 Failed to stop notification sound: $e');
      }
    }
  }

  /// Dispose of the audio player resources
  void dispose() {
    _audioPlayer.dispose();
  }
}