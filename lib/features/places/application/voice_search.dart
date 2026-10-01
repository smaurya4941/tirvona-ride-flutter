import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Why a voice search could not start.
class VoiceSearchUnavailable implements Exception {
  const VoiceSearchUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Speech-to-text for the "Where to?" box: words stream in while the rider
/// speaks; [onDone] fires once when listening ends for any reason.
abstract interface class VoiceSearch {
  /// Starts listening. Throws [VoiceSearchUnavailable] when the microphone
  /// permission is refused or the phone has no speech recogniser.
  Future<void> listen({
    required void Function(String words, {required bool isFinal}) onWords,
    required void Function() onDone,
  });

  Future<void> stop();
}

/// The device recogniser (Google speech services on Android), Indian
/// English first so place names like "Sector 18" come out right.
class DeviceVoiceSearch implements VoiceSearch {
  final _speech = SpeechToText();
  bool _ready = false;
  void Function()? _onDone;

  Future<bool> _init() async {
    if (_ready) return true;
    _ready = await _speech.initialize(
      onStatus: (status) {
        if (status == SpeechToText.doneStatus ||
            status == SpeechToText.notListeningStatus) {
          _finish();
        }
      },
      onError: (_) => _finish(),
    );
    return _ready;
  }

  void _finish() {
    final done = _onDone;
    _onDone = null;
    done?.call();
  }

  @override
  Future<void> listen({
    required void Function(String words, {required bool isFinal}) onWords,
    required void Function() onDone,
  }) async {
    if (!await _init()) {
      throw const VoiceSearchUnavailable(
        'Voice search needs microphone access and Google speech services. '
        'Allow the microphone in Settings, or type the place instead.',
      );
    }
    _onDone = onDone;
    await _speech.listen(
      onResult: (result) =>
          onWords(result.recognizedWords, isFinal: result.finalResult),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenFor: const Duration(seconds: 15),
        pauseFor: const Duration(seconds: 3),
        localeId: 'en_IN',
      ),
    );
  }

  @override
  Future<void> stop() async {
    if (_speech.isListening) await _speech.stop();
    _finish();
  }
}

final voiceSearchProvider = Provider<VoiceSearch>((ref) {
  final voice = DeviceVoiceSearch();
  ref.onDispose(() => unawaited(voice.stop()));
  return voice;
});
