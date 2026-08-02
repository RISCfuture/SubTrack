import Foundation
import Testing

@testable import SubTrack_Common

/**
 A film whose Japanese dub carries the source's `default` flag and whose second
 English track is commentary. The flag sitting on a track the output will not
 lead with is the whole reason the run rewrites it.
 */
private let probeJSON = """
  {
    "streams": [
      {"index":0,"codec_name":"hevc","codec_type":"video","width":1920,"height":1080,
       "pix_fmt":"yuv420p10le","field_order":"progressive","disposition":{"default":1},
       "tags":{"language":"eng"}},
      {"index":1,"codec_name":"dts","codec_type":"audio","sample_rate":"48000","channels":6,
       "bits_per_sample":0,"disposition":{"default":1,"dub":1},"tags":{"language":"jpn"}},
      {"index":2,"codec_name":"ac3","codec_type":"audio","sample_rate":"48000","channels":6,
       "bits_per_sample":0,"disposition":{},"tags":{"language":"eng"}},
      {"index":3,"codec_name":"ac3","codec_type":"audio","sample_rate":"48000","channels":2,
       "bits_per_sample":0,"disposition":{"comment":1},
       "tags":{"language":"eng","ENCODER":"Lavc60.3.100 ac3","BPS":"192000"}},
      {"index":4,"codec_name":"subrip","codec_type":"subtitle","disposition":{"forced":1},
       "tags":{"language":"eng"}}
    ],
    "format":{"filename":"/movies/Film.mkv","duration":"3600.0","size":"4000000000"}
  }
  """

@Suite
struct OutputTrackTests {
  private let container: Container

  /// English only, commentary included: the Japanese dub is dropped, both English tracks kept.
  private var rules: SlimRules {
    var rules = SlimRules.default
    rules.languages = ["eng"]
    rules.includeOtherAudio = true
    return rules
  }

  /// What the rules alone come to.
  private var rulesPlan: TrackPlan {
    TrackPlan(container: container, selection: nil, rules: rules)
  }

  /**
   An override keeping the Japanese dub *behind* the English track — the only
   way a kept audio track can carry the source's `default` and still not lead
   the output.
   */
  private var overridePlan: TrackPlan {
    let selection = FileTrackSelection(choices: [
      TrackChoice(streamIndex: 0, streamType: .video, action: .copy),
      TrackChoice(streamIndex: 2, streamType: .audio, action: .copy),
      TrackChoice(streamIndex: 1, streamType: .audio, action: .copy),
      TrackChoice(streamIndex: 3, streamType: .audio, action: .drop),
      TrackChoice(streamIndex: 4, streamType: .subtitle, action: .copy)
    ])
    return TrackPlan(container: container, selection: selection, rules: rules)
  }

  init() throws {
    container = try JSONDecoder().decode(Container.self, from: Data(probeJSON.utf8))
  }

  /**
   Output positions count only the tracks the run writes, in the order it
   writes them. A dropped track keeps its row but takes no number, so the
   numbering closes up over it rather than leaving a gap the output won't have.
   */
  @Test
  func numbersOnlyTheTracksTheRunWrites() {
    let tracks = rulesPlan.outputTracks

    #expect(tracks.count == container.managedStreams.count)
    #expect(tracks.first { $0.track.id == 1 }?.number == nil, "The Japanese dub is dropped.")
    #expect(tracks.compactMap(\.number) == [1, 2, 3, 4])
  }

  /**
   The output's first audio track is its default, whatever the source said —
   and demoting the others takes off that one flag alone. A track kept for what
   it is has to still say what it is.
   */
  @Test
  func marksTheFirstAudioDefaultAndDemotesTheRestIntact() throws {
    let tracks = overridePlan.outputTracks
    let english = try #require(tracks.first { $0.track.id == 2 })
    let japanese = try #require(tracks.first { $0.track.id == 1 })

    #expect(english.dispositions == [.default], "The output leads with English.")
    #expect(japanese.dispositions == [.dub], "Demotion takes the default flag and nothing else.")
  }

  /**
   Only audio is rewritten, and only where there is an output track to rewrite:
   a forced subtitle stays forced, and a dropped track is described as the
   source has it.
   */
  @Test
  func leavesEveryOtherTrackAsTheSourceHasIt() throws {
    let tracks = rulesPlan.outputTracks
    let subtitle = try #require(tracks.first { $0.track.type == .subtitle })
    let dropped = try #require(tracks.first { $0.track.id == 1 })

    #expect(subtitle.dispositions == [.forced])
    #expect(dropped.dispositions == [.default, .dub])
  }

  /**
   The detail pane's last section is the container's tags exactly as the probe
   read them. Nothing is filtered, because a release's own tags are the facts
   no list of named rows can predict.
   */
  @Test
  func listsEveryTagTheProbeRead() throws {
    let commentary = try #require(rulesPlan.outputTracks.first { $0.track.id == 3 })
    let facts = commentary.detailSections.flatMap(\.facts)

    for (name, value) in commentary.track.stream.tags {
      #expect(
        facts.contains { $0.name == name && $0.value == value },
        "The detail pane dropped the “\(name)” tag."
      )
    }
  }

  /**
   A converted track names the arguments its transcode runs under — the one
   part of the plan that is neither the codec nor visible anywhere else.
   */
  @Test
  func namesTheArgumentsATranscodeRunsUnder() throws {
    let selection = FileTrackSelection(choices: [
      TrackChoice(
        streamIndex: 0,
        streamType: .video,
        action: .convert(codec: "hevc", options: ["-preset", "veryslow"])
      )
    ])
    let plan = TrackPlan(container: container, selection: selection, rules: rules)
    let video = try #require(plan.outputTracks.first { $0.track.id == 0 })
    let facts = video.detailSections.flatMap(\.facts)

    #expect(facts.contains { $0.value == "-preset veryslow" })
    #expect(facts.contains { $0.value.contains("hevc") }, "The target codec should be named.")
  }
}
