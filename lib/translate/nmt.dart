import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../core/config.dart';
import '../core/paths.dart';
import '../data/downloads.dart';
import '../data/languages.dart';
import 'tokenizer.dart';

/// Offline neural machine translation with ONNX Runtime (encoder-decoder
/// models exported by Hugging Face Optimum: NLLB-200, M2M-100).
class NmtModel {
  NmtModel._(this.spec, this.dir);

  final ModelSpec spec;
  final Directory dir;
  late HfTokenizer tok;
  late OrtSession _enc, _dec;
  OrtSession? _decPast;
  int eos = 2, decoderStart = 2, pad = 1;
  final Map<String, int> _langTokens = {};

  static const _required = ['encoder', 'decoder', 'tokenizer', 'config'];

  /// ONNX Runtime is bundled on Android, Windows and Linux. Microsoft's iOS /
  /// macOS packages are not downloadable at the moment (their CDN was retired),
  /// so Apple platforms use the dictionary-based translation.
  static bool get supportedOnThisPlatform =>
      Platform.isAndroid || Platform.isWindows || Platform.isLinux;

  static String _file(String dir, String role) =>
      '$dir${Platform.pathSeparator}$role${role == 'tokenizer' || role == 'config' ? '.json' : '.onnx'}';

  /// Model shipped in a "full" installer: `offline-data/models/<id>`.
  static String? bundledDir(ModelSpec s) {
    final b = AppPaths.instance.bundledDataDir;
    if (b == null) return null;
    final d = '${b.path}${Platform.pathSeparator}models${Platform.pathSeparator}${s.id}';
    return _required.every((r) => File(_file(d, r)).existsSync()) ? d : null;
  }

  static bool isBundled(ModelSpec s) => bundledDir(s) != null;

  static String modelDir(ModelSpec s) =>
      bundledDir(s) ?? '${AppPaths.instance.modelsDir.path}${Platform.pathSeparator}${s.id}';

  static String _downloadDir(ModelSpec s) =>
      '${AppPaths.instance.modelsDir.path}${Platform.pathSeparator}${s.id}';

  static String _local(ModelSpec s, String role) => _file(modelDir(s), role);

  static bool isInstalled(ModelSpec s) => _required.every((r) => File(_local(s, r)).existsSync());

  /// Downloads all model files (once). Afterwards translation works offline.
  static Future<void> download(ModelSpec s, Progress onProgress, {CancelToken? cancel}) async {
    final roles = s.files.keys.toList();
    var done = 0;
    for (final role in roles) {
      Object? lastErr;
      var ok = false;
      // GitHub mirror (release "model-<id>") first, then Hugging Face.
      final urls = [
        for (final rel in s.files[role]!) ...[
          if (s.mirrorUrl.isNotEmpty) '${s.mirrorUrl}${rel.split('/').last}',
          '${s.baseUrl}$rel',
        ]
      ];
      for (final url in urls) {
        try {
          if (cancel?.cancelled == true) throw DownloadCancelled();
          await downloadFile(url, File(_file(_downloadDir(s), role)), cancel: cancel,
              onProgress: (r, t) => onProgress(done * 1000 + (t > 0 ? r * 1000 ~/ t : 0), roles.length * 1000));
          ok = true;
          break;
        } on DownloadCancelled {
          rethrow;
        } catch (e) {
          lastErr = e;
        }
      }
      if (!ok && role != 'decoderWithPast') throw lastErr ?? StateError('download failed: $role');
      done++;
    }
  }

  static Future<void> delete(ModelSpec s) async {
    final d = Directory(_downloadDir(s));
    if (await d.exists()) await d.delete(recursive: true);
  }

  static Future<NmtModel> load(ModelSpec s) async {
    final m = NmtModel._(s, Directory(modelDir(s)));
    m.tok = HfTokenizer.parse(await File(_local(s, 'tokenizer')).readAsString());
    final cfg = jsonDecode(await File(_local(s, 'config')).readAsString()) as Map<String, dynamic>;
    m.eos = (cfg['eos_token_id'] as int?) ?? 2;
    m.decoderStart = (cfg['decoder_start_token_id'] as int?) ?? m.eos;
    m.pad = (cfg['pad_token_id'] as int?) ?? 1;
    final ort = OnnxRuntime();
    m._enc = await ort.createSession(_local(s, 'encoder'));
    m._dec = await ort.createSession(_local(s, 'decoder'));
    final past = File(_local(s, 'decoderWithPast'));
    if (past.existsSync()) m._decPast = await ort.createSession(past.path);
    final nllb = RegExp(r'^[a-z]{3}_[A-Z][a-z]{3}$');
    final m2m = RegExp(r'^__([a-z]{2,3})__$');
    m.tok.added.forEach((t, id) {
      if (nllb.hasMatch(t)) m._langTokens[t] = id;
      final mm = m2m.firstMatch(t);
      if (mm != null) m._langTokens[mm.group(1)!] = id;
    });
    return m;
  }

  Future<void> close() async {
    await _enc.close();
    await _dec.close();
    await _decPast?.close();
  }

  static const _macro = {
    'zh': 'zho_Hans', 'ar': 'arb_Arab', 'fa': 'pes_Arab', 'ms': 'zsm_Latn', 'sw': 'swh_Latn',
    'et': 'est_Latn', 'lv': 'lvs_Latn', 'uz': 'uzn_Latn', 'mn': 'khk_Cyrl', 'ne': 'npi_Deva',
    'sq': 'als_Latn', 'om': 'gaz_Latn', 'ku': 'kmr_Latn', 'ps': 'pbt_Arab', 'no': 'nob_Latn',
    'nb': 'nob_Latn', 'az': 'azj_Latn', 'qu': 'quy_Latn', 'yi': 'ydd_Hebr', 'gn': 'grn_Latn',
    'ay': 'ayr_Latn', 'kr': 'knc_Latn', 'mg': 'plt_Latn', 'or': 'ory_Orya', 'tw': 'twi_Latn',
    'cmn': 'zho_Hans', 'zh-Hant': 'zho_Hant', 'yue': 'yue_Hant', 'he': 'heb_Hebr', 'iw': 'heb_Hebr',
    'sr': 'srp_Cyrl', 'bs': 'bos_Latn', 'hr': 'hrv_Latn', 'pa': 'pan_Guru', 'ks': 'kas_Arab',
    'sd': 'snd_Arab', 'tl': 'tgl_Latn', 'fil': 'tgl_Latn',
  };

  /// Token id for a language, or null if the model doesn't know it.
  int? langToken(String code) {
    if (spec.langTokenStyle == 'm2m') {
      return _langTokens[code] ?? _langTokens[code.split('-').first];
    }
    final direct = _macro[code];
    if (direct != null && _langTokens.containsKey(direct)) return _langTokens[direct];
    final l = LanguageRepository.instance.byCode(code);
    final iso3 = l?.iso3 ?? (code.length == 3 ? code : null);
    if (iso3 == null) return null;
    final cands = _langTokens.keys.where((k) => k.startsWith('${iso3}_')).toList();
    if (cands.isEmpty) return null;
    for (final sc in l?.scripts ?? const <String>[]) {
      for (final c in cands) {
        if (c.endsWith('_$sc')) return _langTokens[c];
      }
    }
    return _langTokens[cands.first];
  }

  Set<String> supportedCodes(Iterable<String> allCodes) =>
      {for (final c in allCodes) if (langToken(c) != null) c};

  Future<String> translate(String text, String from, String to) async {
    final src = langToken(from), tgt = langToken(to);
    if (src == null || tgt == null) throw UnsupportedError('language not supported by ${spec.name}');
    final out = <String>[];
    for (final para in text.split('\n')) {
      if (para.trim().isEmpty) {
        out.add('');
        continue;
      }
      final parts = <String>[];
      for (final s in splitSentences(para)) {
        parts.add(await _translateSentence(s, src, tgt));
      }
      out.add(parts.join(' '));
    }
    return out.join('\n');
  }

  static List<String> splitSentences(String p) {
    final r = RegExp(r'[^.!?。！？]+[.!?。！？]*\s*');
    final s = [for (final m in r.allMatches(p)) m.group(0)!.trim()].where((x) => x.isNotEmpty).toList();
    return s.isEmpty ? [p] : s;
  }

  Future<String> _translateSentence(String s, int src, int tgt) async {
    var ids = tok.encode(s);
    if (ids.length > 400) ids = ids.sublist(0, 400);
    // NLLB/M2M source format: [src_lang] tokens </s>
    final input = [src, ...ids, eos];
    final n = input.length;
    final inIds = await OrtValue.fromList(Int64List.fromList(input), [1, n]);
    final mask = await OrtValue.fromList(Int64List.fromList(List.filled(n, 1)), [1, n]);
    final encOut = await _enc.run({'input_ids': inIds, 'attention_mask': mask});
    final hidden = encOut[_enc.outputNames.first]!;
    final generated = <int>[decoderStart, tgt];
    final maxLen = (n * 2 + 16).clamp(16, 512);
    Map<String, OrtValue> past = {};
    final toDispose = <OrtValue>[inIds];
    try {
      var step = 0;
      while (generated.length < maxLen) {
        Map<String, OrtValue> outs;
        final usePast = _decPast != null && step > 0;
        final sess = usePast ? _decPast! : _dec;
        final feedIds = usePast ? [generated.last] : generated;
        final idsVal = await OrtValue.fromList(Int64List.fromList(feedIds), [1, feedIds.length]);
        final inputs = <String, OrtValue>{};
        for (final name in sess.inputNames) {
          if (name == 'input_ids') {
            inputs[name] = idsVal;
          } else if (name == 'encoder_attention_mask') {
            inputs[name] = mask;
          } else if (name == 'encoder_hidden_states') {
            inputs[name] = hidden;
          } else if (name.startsWith('past_key_values') && past.containsKey(name)) {
            inputs[name] = past[name]!;
          }
        }
        outs = await sess.run(inputs);
        await idsVal.dispose();
        final logits = outs['logits']!;
        final flat = await logits.asFlattenedList();
        final shape = logits.shape;
        final vocab = shape.last;
        final offset = flat.length - vocab;
        var best = -1;
        var bestV = double.negativeInfinity;
        for (var i = 0; i < vocab; i++) {
          final v = (flat[offset + i] as num).toDouble();
          if (v > bestV && i != pad && !_blocksRepeat(generated, i)) {
            bestV = v;
            best = i;
          }
        }
        await logits.dispose();
        // Keep new key/value caches; dispose the replaced ones.
        final newPast = <String, OrtValue>{};
        outs.forEach((k, v) {
          if (k.startsWith('present')) {
            newPast[k.replaceFirst('present', 'past_key_values')] = v;
          } else if (k != 'logits') {
            v.dispose();
          }
        });
        for (final e in past.entries) {
          if (newPast.containsKey(e.key)) {
            await e.value.dispose();
          } else {
            newPast[e.key] = e.value; // encoder cache stays
          }
        }
        past = newPast;
        step++;
        if (best < 0 || best == eos) break;
        generated.add(best);
      }
    } finally {
      for (final v in past.values) {
        await v.dispose();
      }
      for (final v in encOut.values) {
        await v.dispose();
      }
      await mask.dispose();
      for (final v in toDispose) {
        await v.dispose();
      }
    }
    return tok.decode(generated.sublist(2), skip: {eos, pad, decoderStart});
  }

  /// no_repeat_ngram_size = 3
  static bool _blocksRepeat(List<int> g, int next) {
    if (g.length < 3) return false;
    final a = g[g.length - 2], b = g[g.length - 1];
    for (var i = 0; i + 2 < g.length; i++) {
      if (g[i] == a && g[i + 1] == b && g[i + 2] == next) return true;
    }
    return false;
  }
}
