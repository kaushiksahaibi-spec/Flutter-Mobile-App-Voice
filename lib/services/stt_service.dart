import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Live status the [SttService] emits while a session is in flight.
enum SttPhase { idle, listening, finalizing, error }

/// A streaming snapshot of the current recognition session.
class SttUpdate {
  const SttUpdate({
    required this.phase,
    this.partialText = '',
    this.finalText,
    this.errorMessage,
  });

  final SttPhase phase;
  final String partialText;
  final String? finalText;
  final String? errorMessage;
}

/// Wraps `speech_to_text` to drive the platform-native on-device speech
/// engines:
///   * Android (API 31+): `SpeechRecognizer.createOnDeviceSpeechRecognizer`
///   * iOS 13+: `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`
///
/// On Android API 24-30 the system doesn't expose the dedicated
/// on-device factory, so the underlying plugin falls back to the
/// standard `SpeechRecognizer` (which uses the device's installed
/// recognition service — typically Google's, which can run offline if
/// the English language pack is installed).
class SttService {
  SttService({SpeechToText? speech}) : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  bool _initialized = false;
  bool _onDeviceSupported = true;

  /// Latest plugin-level error. We capture it in [_initialize] because
  /// `speech_to_text` only allows registering the `onError` callback
  /// once, at initialize time — so we forward errors through this
  /// broadcast stream and surface them inside [listenOnce].
  final StreamController<SpeechRecognitionError> _errors =
      StreamController<SpeechRecognitionError>.broadcast();

  /// Maximum length of a single capture (matches product spec: 6 s).
  static const Duration listenFor = Duration(seconds: 6);

  bool get isAvailable => _speech.isAvailable;

  /// True when this device is expected to run recognition fully on-device.
  /// Android 12+ (API 31) is required for the dedicated
  /// `createOnDeviceSpeechRecognizer` factory; iOS 13+ supports
  /// `requiresOnDeviceRecognition` for installed locales.
  bool get supportsOnDevice => _onDeviceSupported;

  /// Initialize the underlying engine. Must be called once. Also asks
  /// for the runtime permissions both platforms need.
  Future<bool> initialize() async {
    if (_initialized) return _speech.isAvailable;

    if (!await _ensurePermissions()) return false;

    _initialized = await _speech.initialize(
      debugLogging: kDebugMode,
      onError: (error) {
        if (kDebugMode) {
          debugPrint(
            '[SttService] error: ${error.errorMsg} '
            '(permanent=${error.permanent})',
          );
        }
        if (!_errors.isClosed) _errors.add(error);
      },
      onStatus: (status) {
        if (kDebugMode) debugPrint('[SttService] status: $status');
      },
    );
    return _initialized && _speech.isAvailable;
  }

  /// Listens for up to [listenFor] and yields incremental updates,
  /// terminating with a final [SttUpdate] (phase = [SttPhase.idle] for
  /// success, [SttPhase.error] for failure).
  Stream<SttUpdate> listenOnce({String localeId = 'en_US'}) async* {
    if (!_initialized || !_speech.isAvailable) {
      yield const SttUpdate(
        phase: SttPhase.error,
        errorMessage: 'Speech recognition is not available on this device.',
      );
      return;
    }

    final updates = StreamController<SttUpdate>();
    var lastPartial = '';
    var settled = false;

    void settle(SttUpdate u) {
      if (settled) return;
      settled = true;
      if (!updates.isClosed) {
        updates.add(u);
        updates.close();
      }
    }

    void emit(SttUpdate u) {
      if (settled || updates.isClosed) return;
      updates.add(u);
    }

    void onResult(SpeechRecognitionResult result) {
      lastPartial = result.recognizedWords;
      if (result.finalResult) {
        final clean = lastPartial.trim();
        if (clean.isEmpty) {
          settle(
            const SttUpdate(
              phase: SttPhase.error,
              errorMessage:
                  'No speech was detected. Please try again and speak '
                  'clearly into the microphone.',
            ),
          );
        } else {
          settle(
            SttUpdate(
              phase: SttPhase.idle,
              partialText: lastPartial,
              finalText: clean,
            ),
          );
        }
      } else {
        emit(SttUpdate(phase: SttPhase.listening, partialText: lastPartial));
      }
    }

    final errorSub = _errors.stream.listen((error) async {
      if (settled) return;

      // Transparent fallback: if on-device recognition failed because
      // no offline language model is installed on the device (Android
      // error 13 = ERROR_LANGUAGE_UNAVAILABLE, or the same on iOS when
      // requiresOnDeviceRecognition can't be honoured), retry the
      // session once using the platform default recognizer. The next
      // session will skip on-device entirely.
      if (_onDeviceSupported && _isOfflineModelMissing(error)) {
        _onDeviceSupported = false;
        if (kDebugMode) {
          debugPrint(
            '[SttService] offline model unavailable (${error.errorMsg}); '
            'retrying without onDevice...',
          );
        }
        try {
          if (_speech.isListening) await _speech.cancel();
        } catch (_) {/* ignore */}
        try {
          await _startListening(
            onResult: onResult,
            localeId: localeId,
            onDevice: false,
          );
          // Session continues with the default recognizer; do not
          // settle yet.
          return;
        } catch (retryErr) {
          if (kDebugMode) {
            debugPrint('[SttService] retry also failed: $retryErr');
          }
          // fall through and surface the original error
        }
      }

      try {
        if (_speech.isListening) await _speech.cancel();
      } catch (_) {/* ignore */}
      settle(
        SttUpdate(
          phase: SttPhase.error,
          partialText: lastPartial,
          errorMessage: _humanizeError(error),
        ),
      );
    });
    updates.onCancel = () => errorSub.cancel();

    try {
      await _startListening(
        onResult: onResult,
        localeId: localeId,
        onDevice: _onDeviceSupported,
      );
    } catch (e) {
      // Some Android API levels reject onDevice=true with an
      // UnsupportedOperationException. Retry once without forcing
      // on-device so the user still gets a result.
      if (_onDeviceSupported) {
        _onDeviceSupported = false;
        if (kDebugMode) {
          debugPrint(
            '[SttService] on-device listen failed ($e); retrying with '
            'the platform default recognizer.',
          );
        }
        try {
          await _startListening(
            onResult: onResult,
            localeId: localeId,
            onDevice: false,
          );
        } catch (e2) {
          settle(
            SttUpdate(
              phase: SttPhase.error,
              errorMessage: 'Could not start listening: $e2',
            ),
          );
        }
      } else {
        settle(
          SttUpdate(
            phase: SttPhase.error,
            errorMessage: 'Could not start listening: $e',
          ),
        );
      }
    }

    // Hard ceiling: if for any reason the platform doesn't fire a
    // final result by listenFor + 1.5 s grace, settle with whatever
    // we have so the UI doesn't hang forever.
    Future.delayed(listenFor + const Duration(milliseconds: 1500), () async {
      if (settled) return;
      try {
        if (_speech.isListening) await _speech.stop();
      } catch (_) {/* ignore */}
      final clean = lastPartial.trim();
      if (clean.isNotEmpty) {
        settle(
          SttUpdate(
            phase: SttPhase.idle,
            partialText: lastPartial,
            finalText: clean,
          ),
        );
      } else {
        settle(
          const SttUpdate(
            phase: SttPhase.error,
            errorMessage:
                'No speech was detected. Please try again and speak '
                'clearly into the microphone.',
          ),
        );
      }
    });

    yield* updates.stream;
  }

  Future<void> _startListening({
    required void Function(SpeechRecognitionResult) onResult,
    required String localeId,
    required bool onDevice,
  }) async {
    await _speech.listen(
      onResult: onResult,
      listenFor: listenFor,
      // If the user pauses, the platform default would close the session
      // after a brief silence. We want the full 6-second window, so we
      // set pauseFor to the same value.
      pauseFor: listenFor,
      localeId: localeId,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        onDevice: onDevice,
        listenMode: ListenMode.dictation,
        autoPunctuation: true,
      ),
    );
  }

  /// Manually cancel an in-flight session.
  Future<void> cancel() async {
    if (_speech.isListening) {
      await _speech.cancel();
    }
  }

  Future<void> dispose() async {
    if (!_errors.isClosed) await _errors.close();
  }

  Future<bool> _ensurePermissions() async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) return false;

    if (Platform.isIOS) {
      final speech = await Permission.speech.request();
      if (!speech.isGranted) return false;
    }
    return true;
  }

  /// True when the platform reported "the requested locale is not
  /// available offline / on-device" — i.e. the offline language pack
  /// for the selected locale is not installed.
  bool _isOfflineModelMissing(SpeechRecognitionError error) {
    final msg = error.errorMsg;
    return msg == 'error_language_unavailable' ||
        msg == 'error_language_not_supported';
  }

  String _humanizeError(SpeechRecognitionError error) {
    switch (error.errorMsg) {
      case 'error_no_match':
      case 'error_speech_timeout':
        return 'No speech was detected. Please try again and speak '
            'clearly into the microphone.';
      case 'error_audio_error':
        return 'Audio capture failed. Make sure no other app is using '
            'the microphone, then try again.';
      case 'error_network':
      case 'error_network_timeout':
        return 'The recognizer required network access but it is '
            'unavailable. Install the offline English language pack '
            '(Settings → System → Languages → Add a language) or check '
            'your connection.';
      case 'error_recognizer_busy':
        return 'The speech recognizer is busy. Please try again in a '
            'moment.';
      case 'error_insufficient_permissions':
        return 'Microphone or speech recognition permission was denied.';
      case 'error_language_not_supported':
      case 'error_language_unavailable':
        // We auto-fall-back to the platform default recognizer the
        // first time this fires, so this message only surfaces when
        // BOTH the on-device path AND the default recognizer rejected
        // English. Walk the user through installing the offline pack.
        return 'English speech recognition is not available on this '
            'device.\n\n'
            'On Android: open Settings → System → Languages → '
            'Voice → "Offline speech recognition" and download '
            '"English (United States)".\n\n'
            'On iOS: enable Settings → General → Keyboard → '
            'Enable Dictation, then dictate once into any text field '
            'so iOS downloads the offline model.';
      default:
        return 'Speech recognition error: ${error.errorMsg}';
    }
  }
}
