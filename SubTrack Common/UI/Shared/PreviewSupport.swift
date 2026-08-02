#if DEBUG
  import Foundation
  import SwiftData

  /**
   Shared fixtures for SwiftUI previews across the app's queue-facing views.

   Every preview that needs a live ``AppEnvironment`` builds one here from an
   in-memory `ModelContainer`, so no file re-rolls the container/environment
   boilerplate. ``populate(_:with:)`` seeds the selected queue with items forced
   into their exact live states — bypassing the snapshot round-trip that would
   otherwise collapse the transient `waiting`/`probing`/`running` states (and
   drop the `failed`/`incompatible` reasons) to a settled `ready`.
   */
  @MainActor
  enum PreviewSupport {

    /**
     An in-memory ``AppEnvironment`` with an empty seeded queue.

     Uses the process's single shared preview container (``ModelContainer/subTrackApp()``)
     rather than making its own — a preview is hosted in the app, and SwiftData
     traps if a second container is created for these models in one process.
     Because that one container is shared across every preview in the session,
     its queue records are cleared first so each preview starts from a clean
     slate instead of accumulating queues from earlier renders (built-in presets
     are left intact; they re-seed idempotently).
     */
    static func environment(
      fullCodecSet: Bool = true,
      isAppStoreBuild: Bool = false,
      updates: (any UpdateChecking)? = nil
    ) -> AppEnvironment {
      let container = ModelContainer.subTrackApp()
      try? container.mainContext.delete(model: StoredQueueItem.self)
      try? container.mainContext.delete(model: StoredQueue.self)
      return AppEnvironment(
        modelContainer: container,
        featureFlags: FeatureFlags(fullCodecSet: fullCodecSet, isAppStoreBuild: isAppStoreBuild),
        updates: updates
      )
    }

    /// An in-memory ``AppEnvironment`` whose selected queue holds `items`.
    static func environment(
      items: [ItemSpec],
      fullCodecSet: Bool = true,
      isAppStoreBuild: Bool = false
    ) -> AppEnvironment {
      let env = environment(fullCodecSet: fullCodecSet, isAppStoreBuild: isAppStoreBuild)
      populate(env, with: items)
      return env
    }

    /**
     Seeds `env`'s selected queue with one live ``QueueItem`` per spec. Items are
     hydrated as settled placeholders (so the coordinator owns them) and then
     forced into each spec's exact state, letting a preview show `probing`,
     `running` progress, and the `failed`/`incompatible` reasons that don't
     survive persistence.
     */
    @discardableResult
    static func populate(
      _ env: AppEnvironment,
      with specs: [ItemSpec],
      queueName: String = "Preview"
    )
      -> QueueCoordinator
    {
      let queue = env.workspace.newQueue(name: queueName)
      queue.hydrate(
        QueueSnapshot(
          id: queue.id,
          name: queueName,
          items: specs.enumerated().map { offset, spec in
            let source = URL(filePath: "\(spec.folder)/\(spec.name)")
            return QueueItemSnapshot(
              sortIndex: offset,
              sourcePath: source.path(percentEncoded: false),
              outputPath: OutputNameFormat.slimmed
                .outputURL(for: source, position: offset + 1, in: nil)
                .path(percentEncoded: false),
              status: .ready
            )
          }
        )
      )
      env.workspace.selectQueue(queue.id)
      for (item, spec) in zip(queue.items, specs) { spec.apply(to: item) }
      return queue
    }

    // MARK: - Item specs

    /**
     One representative item per ``QueueItemState``, with plausible sizes and a
     probed container — enough to exercise every status/color/glyph branch in
     the queue table and activity log at once.
     */
    static func everyStatusItems() -> [ItemSpec] {
      [
        ItemSpec(name: "Waiting.mkv", status: .waiting, sourceByteCount: 2_400_000_000),
        ItemSpec(name: "Probing.mkv", status: .probing, sourceByteCount: 3_100_000_000),
        ItemSpec(
          name: "Ready.mkv",
          status: .ready,
          sourceByteCount: 1_800_000_000,
          container: container()
        ),
        ItemSpec(
          name: "Encoding.mkv",
          status: .running,
          progress: 0.42,
          sourceByteCount: 4_000_000_000,
          writtenByteCount: 1_580_000_000,
          container: container()
        ),
        ItemSpec(
          name: "Done.mkv",
          status: .done,
          sourceByteCount: 1_200_000_000,
          outputByteCount: 760_000_000,
          tracksRemoved: 2,
          container: container()
        ),
        ItemSpec(name: "Cancelled.mkv", status: .cancelled, sourceByteCount: 900_000_000),
        ItemSpec(name: "Missing.mkv", status: .missing),
        ItemSpec(
          name: "Incompatible.mkv",
          status: .incompatible("The “libx265” encoder isn’t available in the current FFmpeg"),
          sourceByteCount: 2_000_000_000,
          container: container()
        ),
        ItemSpec(
          name: "Failed.mkv",
          status: .failed("ffmpeg exited with code 1"),
          sourceByteCount: 1_500_000_000
        )
      ]
    }

    // MARK: - Containers

    /**
     A decoded ``Container`` fixture built from a canned `ffprobe` JSON payload —
     the only way to obtain one, since `Container` is decode-only. Defaults to a
     typical film: one H.264 video track, English and French audio, and English
     subtitles.
     */
    static func container(
      filename: String = "/Movies/Sample.mkv",
      durationSec: Double = 3600,
      sizeBytes: Int = 4_000_000_000,
      video: [VideoTrack] = [VideoTrack(codec: "h264", width: 1920, height: 1080)],
      audio: [AudioTrack] = [
        AudioTrack(codec: "ac3", language: "eng", channels: 6),
        AudioTrack(codec: "aac", language: "fra", channels: 2)
      ],
      subtitles: [SubtitleTrack] = [SubtitleTrack(codec: "subrip", language: "eng")]
    ) -> Container {
      // A stream's `index` is its position in the file, and `ffprobe` lists them
      // video, then audio, then subtitles.
      let streams =
        video.enumerated().map { offset, track in
          streamDictionary(for: track, index: offset)
        }
        + audio.enumerated().map { offset, track in
          streamDictionary(
            for: track,
            index: video.count + offset,
            isDefault: video.isEmpty && offset == 0
          )
        }
        + subtitles.enumerated().map { offset, track in
          streamDictionary(for: track, index: video.count + audio.count + offset)
        }

      return decodeContainer(
        from: [
          "streams": streams,
          "format": [
            "filename": filename, "duration": String(durationSec), "size": String(sizeBytes)
          ]
        ]
      )
    }

    private static func streamDictionary(for track: VideoTrack, index: Int) -> [String: Any] {
      [
        "index": index, "codec_type": "video", "codec_name": track.codec,
        "width": track.width, "height": track.height, "pix_fmt": "yuv420p",
        "disposition": ["default": 1],
        "tags": ["BPS": String(track.bitsPerSecond)]
      ]
    }

    private static func streamDictionary(for track: AudioTrack, index: Int, isDefault: Bool)
      -> [String: Any]
    {
      [
        "index": index, "codec_type": "audio", "codec_name": track.codec,
        "sample_rate": "48000", "channels": track.channels, "bits_per_sample": 0,
        "disposition": dispositions(track.roles, isDefault: isDefault),
        "tags": tags(
          language: track.language,
          bitsPerSecond: track.bitsPerSecond,
          title: track.title
        )
      ]
    }

    private static func streamDictionary(for track: SubtitleTrack, index: Int) -> [String: Any] {
      [
        "index": index, "codec_type": "subtitle", "codec_name": track.codec,
        "disposition": dispositions(track.roles),
        "tags": tags(
          language: track.language,
          bitsPerSecond: track.bitsPerSecond,
          title: track.title
        )
      ]
    }

    /// A stream's disposition flags in the shape `ffprobe` reports them: every flag, set or clear.
    private static func dispositions(_ roles: Set<Disposition>, isDefault: Bool = false)
      -> [String: UInt8]
    {
      var flags = Dictionary(uniqueKeysWithValues: roles.map { ($0.rawValue, UInt8(1)) })
      flags["default"] = isDefault || roles.contains(.default) ? 1 : 0
      return flags
    }

    /// A stream's tags, carrying its own name only when the fixture gives it one.
    private static func tags(language: String, bitsPerSecond: Int, title: String?)
      -> [String: String]
    {
      var tags = ["language": language, "BPS": String(bitsPerSecond)]
      if let title { tags["title"] = title }
      return tags
    }

    /**
     Decodes an `ffprobe`-shaped payload the way the engine does.

     A malformed fixture is a mistake in this file, not a runtime condition, so
     it stops the preview — but it says what went wrong. A bare `try!` here traps
     with no message, and a preview that dies without one is extremely hard to
     trace back to its cause.
     */
    private static func decodeContainer(from payload: [String: Any]) -> Container {
      do {
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(Container.self, from: data)
      } catch {
        preconditionFailure("PreviewSupport.container built an undecodable fixture: \(error)")
      }
    }

    // MARK: - Subtypes

    /**
     A declarative description of one preview queue item, applied onto a live
     ``QueueItem`` after hydration.
     */
    struct ItemSpec {
      var name: String

      /**
       The folder the source sits in, so a preview can stage two files that
       share a name but not a path.
       */
      var folder: String = "/Movies"
      var status: QueueItemState = .ready
      var progress: Double = 0
      var sourceByteCount: Int?
      var outputByteCount: Int?
      var writtenByteCount: Int?
      var tracksRemoved: Int?
      var container: Container?
      var selection: FileTrackSelection?

      @MainActor
      func apply(to item: QueueItem) {
        item.status = status
        item.progress = progress
        item.sourceByteCount = sourceByteCount
        item.outputByteCount = outputByteCount
        item.writtenByteCount = writtenByteCount
        item.tracksRemoved = tracksRemoved
        item.container = container
        item.selection = selection
      }
    }

    /**
     Every track carries a `BPS` tag, the bit rate the output-size estimate is
     derived from — without one a preview row can only show an em dash.
     */
    struct VideoTrack {
      var codec: String
      var width: Int
      var height: Int
      var bitsPerSecond: Int = 8_000_000
    }

    struct AudioTrack {
      var codec: String
      var language: String
      var channels: Int
      var bitsPerSecond: Int = 320_000

      /// The track's own name ("Director's Commentary"), shown as its Title fact.
      var title: String?

      /**
       What the track is tagged as being for — `comment`, `dub`, and the rest.
       Leave `default` out of it: the fixture puts that on the first audio track
       itself, the way a container does.
       */
      var roles: Set<Disposition> = []
    }

    struct SubtitleTrack {
      var codec: String
      var language: String
      var bitsPerSecond: Int = 1_000

      /// The track's own name ("English (SDH)"), shown as its Title fact.
      var title: String?

      /// What the track is tagged as being for — `forced`, `hearing_impaired`, and the rest.
      var roles: Set<Disposition> = []
    }
  }

  extension FFmpegCapabilities {
    /// A representative full build for previewing the loaded formats sheet.
    static let previewSample = FFmpegCapabilities(
      version: FFmpegVersionInfo(
        version: "6.1.1",
        bannerLine: "ffmpeg version 6.1.1 Copyright (c) 2000-2023 the FFmpeg developers",
        configuration: "--enable-gpl --enable-libx264 --enable-libx265 --enable-videotoolbox",
        libraryVersions: ["libavcodec 60.31.102"]
      ),
      containers: [
        FFmpegContainer(
          name: "mov,mp4,m4a,3gp",
          summary: "QuickTime / MOV",
          canDemux: true,
          canMux: true
        ),
        FFmpegContainer(
          name: "matroska,webm",
          summary: "Matroska / WebM",
          canDemux: true,
          canMux: true
        ),
        FFmpegContainer(
          name: "mpegts",
          summary: "MPEG-TS (MPEG-2 Transport Stream)",
          canDemux: true,
          canMux: true
        )
      ],
      videoCodecs: [
        FFmpegCodec(
          name: "h264",
          summary: "H.264 / AVC",
          mediaType: .video,
          canEncode: true,
          canDecode: true
        ),
        FFmpegCodec(
          name: "hevc",
          summary: "H.265 / HEVC",
          mediaType: .video,
          canEncode: true,
          canDecode: true
        ),
        FFmpegCodec(
          name: "av1",
          summary: "Alliance for Open Media AV1",
          mediaType: .video,
          canEncode: false,
          canDecode: true
        )
      ],
      audioCodecs: [
        FFmpegCodec(
          name: "aac",
          summary: "AAC (Advanced Audio Coding)",
          mediaType: .audio,
          canEncode: true,
          canDecode: true
        ),
        FFmpegCodec(
          name: "ac3",
          summary: "ATSC A/52A (AC-3)",
          mediaType: .audio,
          canEncode: true,
          canDecode: true
        ),
        FFmpegCodec(
          name: "flac",
          summary: "FLAC (Free Lossless Audio Codec)",
          mediaType: .audio,
          canEncode: true,
          canDecode: true
        )
      ],
      subtitleCodecs: [
        FFmpegCodec(
          name: "subrip",
          summary: "SubRip subtitle",
          mediaType: .subtitle,
          canEncode: true,
          canDecode: true
        ),
        FFmpegCodec(
          name: "mov_text",
          summary: "MOV text",
          mediaType: .subtitle,
          canEncode: true,
          canDecode: true
        )
      ]
    )

    /**
     An LGPL build (the Mac App Store story): x264/x265 can be *decoded* but not
     encoded — encoding is only available through the VideoToolbox encoders — so
     the encode glyphs honestly show as unavailable for those codecs.
     */
    static let previewLGPLSample = FFmpegCapabilities(
      version: FFmpegVersionInfo(
        version: "6.1.1",
        bannerLine: "ffmpeg version 6.1.1 Copyright (c) 2000-2023 the FFmpeg developers",
        configuration: "--enable-videotoolbox --enable-audiotoolbox --disable-gpl",
        libraryVersions: ["libavcodec 60.31.102"]
      ),
      containers: [
        FFmpegContainer(
          name: "mov,mp4,m4a,3gp",
          summary: "QuickTime / MOV",
          canDemux: true,
          canMux: true
        ),
        FFmpegContainer(
          name: "matroska,webm",
          summary: "Matroska / WebM",
          canDemux: true,
          canMux: true
        ),
        FFmpegContainer(
          name: "mpegts",
          summary: "MPEG-TS (MPEG-2 Transport Stream)",
          canDemux: true,
          canMux: true
        )
      ],
      videoCodecs: [
        FFmpegCodec(
          name: "h264",
          summary: "H.264 / AVC",
          mediaType: .video,
          canEncode: false,
          canDecode: true
        ),
        FFmpegCodec(
          name: "h264_videotoolbox",
          summary: "H.264 (VideoToolbox)",
          mediaType: .video,
          canEncode: true,
          canDecode: false
        ),
        FFmpegCodec(
          name: "hevc",
          summary: "H.265 / HEVC",
          mediaType: .video,
          canEncode: false,
          canDecode: true
        ),
        FFmpegCodec(
          name: "hevc_videotoolbox",
          summary: "H.265 (VideoToolbox)",
          mediaType: .video,
          canEncode: true,
          canDecode: false
        ),
        FFmpegCodec(
          name: "av1",
          summary: "Alliance for Open Media AV1",
          mediaType: .video,
          canEncode: false,
          canDecode: true
        )
      ],
      audioCodecs: [
        FFmpegCodec(
          name: "aac",
          summary: "AAC (Advanced Audio Coding)",
          mediaType: .audio,
          canEncode: true,
          canDecode: true
        ),
        FFmpegCodec(
          name: "ac3",
          summary: "ATSC A/52A (AC-3)",
          mediaType: .audio,
          canEncode: false,
          canDecode: true
        ),
        FFmpegCodec(
          name: "flac",
          summary: "FLAC (Free Lossless Audio Codec)",
          mediaType: .audio,
          canEncode: true,
          canDecode: true
        )
      ],
      subtitleCodecs: [
        FFmpegCodec(
          name: "subrip",
          summary: "SubRip subtitle",
          mediaType: .subtitle,
          canEncode: true,
          canDecode: true
        ),
        FFmpegCodec(
          name: "mov_text",
          summary: "MOV text",
          mediaType: .subtitle,
          canEncode: true,
          canDecode: true
        )
      ]
    )
  }
#endif
