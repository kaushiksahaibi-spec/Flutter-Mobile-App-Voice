import 'dart:async';

import 'package:flutter/material.dart';

import 'services/stt_service.dart';
import 'widgets/mic_button.dart';

void main() {
  runApp(const VoiceRecgApp());
}

class VoiceRecgApp extends StatelessWidget {
  const VoiceRecgApp({super.key});

  @override
  Widget build(BuildContext context) {
    final lightScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6750A4),
      brightness: Brightness.light,
    );
    final darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6750A4),
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: 'On-device Voice Notes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: lightScheme,
        scaffoldBackgroundColor: lightScheme.surface,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: darkScheme,
        scaffoldBackgroundColor: darkScheme.surface,
      ),
      home: const HomeScreen(),
    );
  }
}

enum _AppPhase { initializing, ready, listening, finalizing, unavailable }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Duration _recordingDuration = SttService.listenFor;

  final SttService _stt = SttService();

  _AppPhase _phase = _AppPhase.initializing;
  String _transcript = '';
  String _partial = '';
  String? _errorMessage;

  StreamSubscription<SttUpdate>? _sessionSub;
  Timer? _countdownTicker;
  int _secondsRemaining = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _countdownTicker?.cancel();
    _sessionSub?.cancel();
    _stt.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final ok = await _stt.initialize();
    if (!mounted) return;
    setState(() {
      if (ok) {
        _phase = _AppPhase.ready;
      } else {
        _phase = _AppPhase.unavailable;
        _errorMessage =
            'Speech recognition is not available on this device, or '
            'the microphone / speech recognition permission was denied.\n\n'
            'Open Settings, grant the permissions, and relaunch the app.';
      }
    });
  }

  Future<void> _onMicTap() async {
    if (_phase != _AppPhase.ready) return;

    setState(() {
      _phase = _AppPhase.listening;
      _transcript = '';
      _partial = '';
      _errorMessage = null;
      _secondsRemaining = _recordingDuration.inSeconds;
    });

    _startCountdown();

    await _sessionSub?.cancel();
    _sessionSub = _stt.listenOnce().listen(
      _onUpdate,
      onError: (Object e) {
        _handleError(e.toString());
      },
      onDone: () {
        _stopCountdown();
        if (!mounted) return;
        if (_phase == _AppPhase.listening || _phase == _AppPhase.finalizing) {
          setState(() => _phase = _AppPhase.ready);
        }
      },
    );
  }

  void _onUpdate(SttUpdate update) {
    if (!mounted) return;
    switch (update.phase) {
      case SttPhase.listening:
        setState(() {
          _phase = _AppPhase.listening;
          _partial = update.partialText;
        });
        break;
      case SttPhase.finalizing:
        setState(() {
          _phase = _AppPhase.finalizing;
          _partial = update.partialText;
        });
        break;
      case SttPhase.idle:
        _stopCountdown();
        setState(() {
          _phase = _AppPhase.ready;
          _transcript = update.finalText ?? update.partialText.trim();
          _partial = '';
        });
        break;
      case SttPhase.error:
        _handleError(update.errorMessage ?? 'Unknown error');
        break;
    }
  }

  void _handleError(String message) {
    _stopCountdown();
    if (!mounted) return;
    setState(() {
      _phase = _AppPhase.ready;
      _errorMessage = message;
      _partial = '';
    });
    _showSnack(_shortenForSnack(message));
  }

  String _shortenForSnack(String message) {
    final firstLine = message.split('\n').first.trim();
    return firstLine.isEmpty ? message : firstLine;
  }

  void _startCountdown() {
    _countdownTicker?.cancel();
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        _secondsRemaining = (_secondsRemaining - 1).clamp(0, 999);
      });
      if (_secondsRemaining <= 0) t.cancel();
    });
  }

  void _stopCountdown() {
    _countdownTicker?.cancel();
    _countdownTicker = null;
    _secondsRemaining = 0;
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  MicButtonState get _micState {
    switch (_phase) {
      case _AppPhase.initializing:
      case _AppPhase.unavailable:
        return MicButtonState.disabled;
      case _AppPhase.listening:
        return MicButtonState.listening;
      case _AppPhase.finalizing:
        return MicButtonState.processing;
      case _AppPhase.ready:
        return MicButtonState.idle;
    }
  }

  String get _statusLine {
    switch (_phase) {
      case _AppPhase.initializing:
        return 'Initializing speech engine…';
      case _AppPhase.unavailable:
        return 'Speech recognition unavailable';
      case _AppPhase.ready:
        return _transcript.isEmpty
            ? 'Tap the mic and speak in English for ${_recordingDuration.inSeconds} seconds.'
            : 'Tap the mic to record again.';
      case _AppPhase.listening:
        return 'Listening… $_secondsRemaining s';
      case _AppPhase.finalizing:
        return 'Finalizing transcript…';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('On-device Voice Notes'),
        centerTitle: true,
        backgroundColor: colors.surface,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      MicButton(
                        state: _micState,
                        onPressed: _phase == _AppPhase.ready
                            ? _onMicTap
                            : null,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _statusLine,
                        textAlign: TextAlign.center,
                        style: textTheme.titleMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      if (_phase == _AppPhase.listening &&
                          _partial.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            _partial,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyMedium?.copyWith(
                              color: colors.primary,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 4,
                child: _TranscriptCard(
                  transcript: _transcript,
                  errorMessage: _errorMessage,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(
                  _stt.supportsOnDevice
                      ? 'On-device · Android SpeechRecognizer · iOS SFSpeechRecognizer'
                      : 'Platform default recognizer (offline English '
                            'pack not installed — install it for fully '
                            'on-device transcription)',
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TranscriptCard extends StatelessWidget {
  const _TranscriptCard({required this.transcript, this.errorMessage});

  final String transcript;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final hasError = errorMessage != null;
    final hasContent = transcript.isNotEmpty;

    final headerColor = hasError ? colors.error : colors.primary;
    final headerLabel = hasError ? 'Error' : 'Transcript';

    final body = hasError
        ? errorMessage!
        : (hasContent
              ? transcript
              : 'Your transcribed speech will appear here.');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasError ? Icons.error_outline : Icons.text_snippet_outlined,
                size: 18,
                color: headerColor,
              ),
              const SizedBox(width: 8),
              Text(
                headerLabel,
                style: textTheme.labelLarge?.copyWith(color: headerColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                body,
                style: textTheme.bodyLarge?.copyWith(
                  color: hasContent || hasError
                      ? colors.onSurface
                      : colors.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
