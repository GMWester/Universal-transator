/// Dart binding for GMWester/IPAReader (https://github.com/GMWester/IPAReader):
/// speech synthesis that reads raw IPA and pronounces exactly what is written.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const int _iprOk = 0;

/// Mirrors `ipr_voice` in ipareader.h.
final class IprVoice extends Struct {
  @Array(32)
  external Array<Uint8> name;
  @Float()
  external double pitch;
  @Float()
  external double pitchRange;
  @Float()
  external double formantScale;
  @Array(5)
  external Array<Float> formantShift;
  @Float()
  external double bandwidthScale;
  @Float()
  external double openQuotient;
  @Float()
  external double spectralTilt;
  @Float()
  external double breathiness;
  @Float()
  external double jitter;
  @Float()
  external double shimmer;
  @Float()
  external double vibratoDepth;
  @Float()
  external double vibratoRate;
  @Float()
  external double speed;
  @Float()
  external double volume;
  @Float()
  external double fricationGain;
}

/// Mirrors `ipr_options` in ipareader.h.
final class IprOptions extends Struct {
  @Int32()
  external int sampleRate;
  @Float()
  external double speed;
  @Float()
  external double pitchShift;
  @Float()
  external double volume;
  @Float()
  external double wordGapMs;
  @Int32()
  external int flags;
}

typedef _VoiceBuiltinC = Int32 Function(Pointer<Utf8>, Pointer<IprVoice>);
typedef _VoiceBuiltinD = int Function(Pointer<Utf8>, Pointer<IprVoice>);
typedef _VoiceParseC = Int32 Function(Pointer<Utf8>, Pointer<IprVoice>);
typedef _VoiceParseD = int Function(Pointer<Utf8>, Pointer<IprVoice>);
typedef _OptsDefaultC = Void Function(Pointer<IprOptions>);
typedef _OptsDefaultD = void Function(Pointer<IprOptions>);
typedef _SynthC = Int32 Function(Pointer<Utf8>, Pointer<IprVoice>,
    Pointer<IprOptions>, Pointer<Pointer<Int16>>, Pointer<Size>);
typedef _SynthD = int Function(Pointer<Utf8>, Pointer<IprVoice>,
    Pointer<IprOptions>, Pointer<Pointer<Int16>>, Pointer<Size>);
typedef _WavEncC = Int32 Function(
    Pointer<Int16>, Size, Int32, Pointer<Pointer<Uint8>>, Pointer<Size>);
typedef _WavEncD = int Function(
    Pointer<Int16>, int, int, Pointer<Pointer<Uint8>>, Pointer<Size>);
typedef _FreeC = Void Function(Pointer<Void>);
typedef _FreeD = void Function(Pointer<Void>);
typedef _StrC = Pointer<Utf8> Function();
typedef _StrErrC = Pointer<Utf8> Function(Int32);
typedef _StrErrD = Pointer<Utf8> Function(int);
typedef _AnalyzeC = Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Size);
typedef _AnalyzeD = int Function(Pointer<Utf8>, Pointer<Utf8>, int);
typedef _IntC = Int32 Function();
typedef _IntD = int Function();

DynamicLibrary _open() {
  const name = 'ipareader_ffi';
  if (Platform.isMacOS || Platform.isIOS) {
    try {
      return DynamicLibrary.open('$name.framework/$name');
    } catch (_) {
      return DynamicLibrary.process();
    }
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$name.so');
  }
  if (Platform.isWindows) return DynamicLibrary.open('$name.dll');
  throw UnsupportedError('IPAReader: unsupported platform');
}

class _Lib {
  _Lib(DynamicLibrary l)
      : voiceBuiltin =
            l.lookupFunction<_VoiceBuiltinC, _VoiceBuiltinD>('ipr_voice_builtin'),
        voiceParse =
            l.lookupFunction<_VoiceParseC, _VoiceParseD>('ipr_voice_parse'),
        optionsDefault =
            l.lookupFunction<_OptsDefaultC, _OptsDefaultD>('ipr_options_default'),
        synth = l.lookupFunction<_SynthC, _SynthD>('ipr_synth'),
        wavEncode = l.lookupFunction<_WavEncC, _WavEncD>('ipr_wav_encode'),
        free = l.lookupFunction<_FreeC, _FreeD>('ipr_free'),
        version = l.lookupFunction<_StrC, _StrC>('ipr_version'),
        strerror = l.lookupFunction<_StrErrC, _StrErrD>('ipr_strerror'),
        analyze = l.lookupFunction<_AnalyzeC, _AnalyzeD>('ipr_analyze'),
        unknownCount = l.lookupFunction<_IntC, _IntD>('ipr_unknown_count');

  final _VoiceBuiltinD voiceBuiltin;
  final _VoiceParseD voiceParse;
  final _OptsDefaultD optionsDefault;
  final _SynthD synth;
  final _WavEncD wavEncode;
  final _FreeD free;
  final _StrC version;
  final _StrErrD strerror;
  final _AnalyzeD analyze;
  final _IntD unknownCount;
}

_Lib? _libCache;
_Lib get _lib => _libCache ??= _Lib(_open());

class IpaReaderException implements Exception {
  IpaReaderException(this.code, this.message);
  final int code;
  final String message;
  @override
  String toString() => 'IpaReaderException($code): $message';
}

/// Settings for one synthesis call. All values are plain data so they can be
/// sent to a background isolate.
class IpaSpeechSettings {
  const IpaSpeechSettings({
    this.voice = 'female',
    this.voiceFileText,
    this.sampleRate = 22050,
    this.speed = 1.0,
    this.pitchShift = 0.0,
    this.volume = 1.0,
    this.wordGapMs = 0.0,
    this.monotone = false,
  });

  /// Built-in voice name: `male` or `female`.
  final String voice;

  /// Optional voice-file text (`key = value` lines) that overrides [voice].
  final String? voiceFileText;
  final int sampleRate;
  final double speed;
  final double pitchShift;
  final double volume;
  final double wordGapMs;
  final bool monotone;
}

/// IPA text to speech.
class IpaReader {
  IpaReader._();

  static String get version => _lib.version().toDartString();

  /// Synthesizes [ipa] and returns a complete WAV file (16-bit mono PCM).
  /// Runs synchronously; prefer [synthWavAsync] from UI code.
  static Uint8List synthWav(String ipa,
      [IpaSpeechSettings settings = const IpaSpeechSettings()]) {
    final lib = _lib;
    return using((arena) {
      final voice = arena<IprVoice>();
      final opts = arena<IprOptions>();
      var rc = settings.voiceFileText != null
          ? lib.voiceParse(
              settings.voiceFileText!.toNativeUtf8(allocator: arena), voice)
          : lib.voiceBuiltin(settings.voice.toNativeUtf8(allocator: arena), voice);
      if (rc != _iprOk) {
        rc = lib.voiceBuiltin('female'.toNativeUtf8(allocator: arena), voice);
      }
      lib.optionsDefault(opts);
      opts.ref
        ..sampleRate = settings.sampleRate
        ..speed = settings.speed
        ..pitchShift = settings.pitchShift
        ..volume = settings.volume
        ..wordGapMs = settings.wordGapMs
        ..flags = settings.monotone ? 2 : 0;
      final pcm = arena<Pointer<Int16>>();
      final n = arena<Size>();
      rc = lib.synth(ipa.toNativeUtf8(allocator: arena), voice, opts, pcm, n);
      if (rc != _iprOk) {
        throw IpaReaderException(rc, lib.strerror(rc).toDartString());
      }
      final wav = arena<Pointer<Uint8>>();
      final wavLen = arena<Size>();
      rc = lib.wavEncode(pcm.value, n.value, settings.sampleRate, wav, wavLen);
      lib.free(pcm.value.cast());
      if (rc != _iprOk) {
        throw IpaReaderException(rc, lib.strerror(rc).toDartString());
      }
      final out = Uint8List.fromList(wav.value.asTypedList(wavLen.value));
      lib.free(wav.value.cast());
      return out;
    });
  }

  /// Synthesizes on a background isolate.
  static Future<Uint8List> synthWavAsync(String ipa,
          [IpaSpeechSettings settings = const IpaSpeechSettings()]) =>
      Isolate.run(() => synthWav(ipa, settings));

  /// Text description of how IPAReader analysed the input (debugging).
  static String analyze(String ipa) {
    final lib = _lib;
    return using((arena) {
      final s = ipa.toNativeUtf8(allocator: arena);
      final need = lib.analyze(s, nullptr, 0);
      if (need <= 0) return '';
      final buf = arena<Uint8>(need + 1).cast<Utf8>();
      lib.analyze(s, buf, need + 1);
      return buf.toDartString();
    });
  }

  /// Number of characters not recognised by the last call on this thread.
  static int get unknownCount => _lib.unknownCount();
}
