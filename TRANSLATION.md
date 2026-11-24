# Translating SubTrack

Guidance for anyone, human or agent, translating SubTrack's interface, Help book or App
Store listing. Where it conflicts with Apple's per-locale style guide, this file wins; where
it is silent, the style guide does.

## Locales

| Locale | Language | App Store folder |
| --- | --- | --- |
| `de` | German | `de-DE` |
| `fr` | French | `fr-FR` |
| `es` | Spanish (Spain) | `es-ES` |
| `it` | Italian | `it` |

## Who reads it

Mac users who rip their own Blu-ray and UHD discs: technically fluent, at home with codec
names, and usually native speakers of the language they are keeping a dub in. Write the way
Apple writes Finder and the Music app in that language — plain, brief, never marketing.

## Never translate

- **Names:** SubTrack, FFmpeg, `ffmpeg`, `ffprobe`, FFmpeg.org, Finder, Mac App Store,
  VideoToolbox, LGPL.
- **Codecs and formats**, exactly as written: AAC, AC-3, E-AC-3, DTS, TrueHD, FLAC, ALAC,
  Opus, H.264, HEVC, x264, x265, SubRip (SRT), Advanced SubStation (ASS), MP4 Timed Text,
  Blu-ray, UHD, MKV, MP4, PGS.
- **Units and symbols:** kbps, Hz, kHz, `-bit`, `ch`, `p`, `i`. Keep a space or none exactly
  as the source does.
- **File names and examples:** `Movie.mkv`, and any name-format token or path.
- **The command-line tool's name and anything shown as a command.**

Language names are formatted by `Locale` at run time and never appear in the catalog.

## Terms

SubTrack's own concepts. Use these consistently; once a term is chosen for a locale, every
string, the Help book and the App Store listing use it.

| English | Meaning | de | fr | es | it |
| --- | --- | --- | --- | --- | --- |
| slim, slimmed, slimming | SubTrack's action: copy a file without the tracks the rules drop | verschlanken, verschlankt | alléger, allégé, allègement | aligerar, aligerado, aligeramiento | alleggerire, alleggerito, alleggerimento |
| queue | an ordered list of files waiting to be slimmed, with its own rules | Warteschlange | file d’attente | cola | coda |
| preset | a saved, named set of rules | Voreinstellung | préréglage | preajuste | preimpostazione |
| rules | which tracks to keep, by language, role and codec | Regeln | règles | reglas | regole |
| track | one audio, subtitle or video stream in a file | Spur | piste | pista | traccia |
| override | a per-file choice of tracks that replaces the rules for that file | anpassen, Anpassung | personnaliser, personnalisation | personalizar, personalización | personalizzare, personalizzazione |
| source | the original file | Quelle | source | origen | sorgente |
| destination | the folder the slimmed file is written to | Ziel | destination | destino | destinazione |
| untagged | a track with no language tag | ohne Sprachangabe (als Sprache: Keine Angabe) | sans langue | sin idioma | senza lingua |
| commentary | a commentary audio track | Kommentar | commentaire | comentario | commento |
| dubbed | a dub in a language other than the original | synchronisiert | doublé | doblado | doppiato |
| forced | forced subtitles (shown only for foreign dialogue) | erzwungen | forcés | forzados | forzati |
| hearing impaired | subtitles or audio for deaf and hard-of-hearing viewers (SDH) | für Hörgeschädigte | pour sourds et malentendants | para personas sordas | per non udenti |
| visually impaired | audio description | Audiodeskription | audiodescription | audiodescripción | audiodescrizione |
| inspect, re-scan | read a file's tracks with `ffprobe` | analysieren, Analyse, erneut analysieren | analyser, analyse, réanalyser | analizar, análisis, volver a analizar | analizzare, analisi, rianalizzare |
| transcode, transcode target | re-encode a track into another codec; the codec it becomes | umcodieren, Umcodierung, Zielcodec | transcoder, transcodage, codec cible | transcodificar, transcodificación, códec de destino | transcodificare, transcodifica, codec di destinazione |
| encode, decode | FFmpeg's encode and decode capabilities; also the Encoding settings tab and queue status | codieren, decodieren, Codierung | encoder, décoder, encodage, décodage | codificar, decodificar, codificación, decodificación | codificare, decodificare, codifica, decodifica |
| inspector | the right-hand pane with the Rules, Override and Preview tabs | Inspektor | inspecteur | inspector | Inspector |
| run | one pass of a queue from Start until it finishes | Durchlauf | exécution | ejecución | esecuzione |
| Activity Log | the window that lists runs and problems | Aktivitätsprotokoll | Journal d’activité | Registro de actividad | Registro attività |
| token | a placeholder in the output-name format, such as `{name}`, that stands for each file's own details | Platzhalter | balise | marcador | segnaposto |
| download version, App Store version | SubTrack's two editions: from the website (fuller FFmpeg) and from the Mac App Store | Download-Version, App-Store-Version | version téléchargeable, version App Store | versión descargable, versión de App Store | versione scaricabile, versione App Store |
| home folder | the user's macOS home folder | Benutzerordner | dossier de départ | carpeta de inicio | cartella Inizio |

Where a cell gives a verb and a noun, buttons and menu items take the verb and tabs,
headers and labels the noun: the Override tab is Anpassung, personnalisation, personalización,
personalizzazione.

A dash means no term has been decided. Decide it before the first translation batch for that
locale, write it into this table, and use it from then on.

Track roles (Commentary, Dubbed, Forced, Hearing impaired, Karaoke, Lyrics, Clean effects,
Captions, Descriptions, Non-diegetic, Original) are the dispositions FFmpeg reports. Translate
them as short adjectives or nouns that fit a column header, consistently in every place they
appear.

## Style

- **Buttons and menu items** are verbs; **column headers and labels** are nouns. A key like
  “Preview” or “Override” is both in different places — read the call site.
- **Strings that name another control** (“Read how SubTrack works”, “Choose Reset to Rules”)
  must use that control's translated title exactly.
- **Ellipsis:** keep a trailing “…” wherever the source has one; it means the command opens a
  dialog.
- **Help links** (“Help with presets”) are accessibility labels for the help buttons. Keep them
  short and parallel across the set.
- **Error messages** follow the project's `LocalizedError` shape: `errorDescription` is a
  general statement (“Couldn’t read the video file.”), `failureReason` the specifics. Keep each
  a complete sentence with a full stop.

## Help book

`Help/SubTrack.help/Contents/Resources/en.lproj/` is the source. A translation is a sibling
`<locale>.lproj/` folder with every page, the same file names, the same `<a name="…">` anchors
and the same `<meta name="robots" content="index, anchor">` tags; `build-help-book.sh` indexes
each `.lproj` it finds. Translate text, `<title>` and `alt` attributes; leave markup, class
names, anchors and `href`s alone. Until screenshots are captured in that language, point each
`images/…` reference at `../en.lproj/images/…`.

## App Store listing

`fastlane/metadata/en-US/` is the source; each locale gets its own folder named as in the
locale table. Translate `name.txt`, `subtitle.txt`, `promotional_text.txt`, `description.txt`
and `keywords.txt`; copy the URL files unchanged. App Store limits: name and subtitle 30
characters, promotional text 170, keywords 100 bytes as a comma-separated list with no spaces
after commas, description 4,000. Keywords are search terms people in that market type, not a
translation of the English list. `promo/copy.en-US.json` holds the screenshot captions; each
locale gets a `copy.<App Store folder>.json`, with each line short enough for the caption it
replaces.
