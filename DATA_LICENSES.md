# Data and component licenses

| Component | Used for | License |
|---|---|---|
| [IPAReader](https://github.com/GMWester/IPAReader) | Text-to-speech from IPA (all platforms, via dart:ffi) | AGPL-3.0 |
| [Wiktionary](https://www.wiktionary.org/) via [Wiktextract / kaikki.org](https://kaikki.org/) | Meanings, pronunciations (IPA), inflected forms, translations, etymologies | CC BY-SA 4.0 / GFDL |
| [eSpeak NG](https://github.com/espeak-ng/espeak-ng) (build time only) | IPA for words that Wiktionary has no pronunciation for (inflected forms etc.), ~100 languages. Speech itself is always IPAReader. | GPL-3.0 (tool; its output is data) |
| [WALS Online](https://wals.info) (Dryer & Haspelmath 2013) | Grammar rules: 192 features for ~2 600 languages, chapter texts, examples | CC BY 4.0 |
| [Grambank](https://grambank.clld.org) (Skirgård et al. 2023) | Grammar rules: 195 features for ~2 400 languages | CC BY 4.0 |
| [Glottolog](https://glottolog.org) | List of all languages, families, ISO 639-3 codes | CC BY 4.0 |
| [Unicode CLDR](https://cldr.unicode.org) | Language names in 424 display languages, alphabets (exemplar characters), scripts | Unicode License v3 |
| Unicode Character Database | Characters of every script and their names | Unicode License v3 |
| [NLLB-200 distilled 600M](https://huggingface.co/facebook/nllb-200-distilled-600M) (optional download) | Neural translation, 200 languages | CC BY-NC 4.0 (non-commercial) |
| [M2M-100 418M](https://huggingface.co/facebook/m2m100_418M) (optional download) | Neural translation, 100 languages | MIT |
| [ONNX Runtime](https://onnxruntime.ai) | Runs the translation model on-device | MIT |

The app itself is licensed under the GNU AGPL v3 (see LICENSE), matching IPAReader.
