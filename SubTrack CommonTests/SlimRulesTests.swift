import Foundation
import Testing

import SubTrack_Common

@Suite
struct SlimRulesTests {

  /// Decodes a rules blob written by an earlier build.
  private func decode(_ json: String) throws -> SlimRules {
    try JSONDecoder().decode(SlimRules.self, from: Data(json.utf8))
  }

  @Test
  func `repairs preset passed as profile`() throws {
    let rules = try decode(
      """
      {"languages":["eng"],"preserveNoLanguages":false,"includeOtherAudio":false,
       "videoPreferredCodecs":["hevc","h264"],"videoConversionCodec":"hevc",
       "videoConversionOptions":["-profile:v","veryslow"],
       "audioPreferredCodecs":["aac"],"audioConversionCodec":"truehd",
       "audioConversionOptions":[],"subtitlePreferredCodecs":["subrip"]}
      """
    )
    #expect(rules.videoConversionOptions == ["-preset", "veryslow"])
  }

  @Test
  func `leaves real profile alone`() throws {
    let rules = try decode(
      """
      {"languages":["eng"],"preserveNoLanguages":false,"includeOtherAudio":false,
       "videoPreferredCodecs":["hevc"],"videoConversionCodec":"hevc",
       "videoConversionOptions":["-profile:v","main10"],
       "audioPreferredCodecs":["aac"],"audioConversionCodec":"truehd",
       "audioConversionOptions":[],"subtitlePreferredCodecs":["subrip"]}
      """
    )
    #expect(rules.videoConversionOptions == ["-profile:v", "main10"])
  }

  @Test
  func `adds AV1 to the unedited default codec list`() throws {
    let rules = try decode(
      """
      {"languages":["eng"],"preserveNoLanguages":false,"includeOtherAudio":false,
       "videoPreferredCodecs":["hevc","h264"],"videoConversionCodec":"hevc",
       "videoConversionOptions":[],
       "audioPreferredCodecs":["aac"],"audioConversionCodec":"truehd",
       "audioConversionOptions":[],"subtitlePreferredCodecs":["subrip"]}
      """
    )
    #expect(rules.videoPreferredCodecs == ["av1", "hevc", "h264"])
  }

  @Test
  func `leaves an edited codec list alone`() throws {
    let rules = try decode(
      """
      {"languages":["eng"],"preserveNoLanguages":false,"includeOtherAudio":false,
       "videoPreferredCodecs":["h264"],"videoConversionCodec":"hevc",
       "videoConversionOptions":[],
       "audioPreferredCodecs":["aac"],"audioConversionCodec":"truehd",
       "audioConversionOptions":[],"subtitlePreferredCodecs":["subrip"]}
      """
    )
    #expect(rules.videoPreferredCodecs == ["h264"])
  }

  /**
   A blob missing a key must keep every other stored value rather than
   collapsing the whole record to `SlimRules.default`.
   */
  @Test
  func `a missing key falls back without discarding the rest`() throws {
    let rules = try decode(
      """
      {"languages":["jpn","eng"],"preserveNoLanguages":true,"includeOtherAudio":true,
       "videoPreferredCodecs":["h264"],"videoConversionCodec":"hevc",
       "videoConversionOptions":[],
       "audioPreferredCodecs":["aac"],"audioConversionCodec":"truehd",
       "audioConversionOptions":[]}
      """
    )
    #expect(rules.languages == ["jpn", "eng"])
    #expect(rules.preserveNoLanguages)
    #expect(rules.includeOtherAudio)
    #expect(rules.subtitlePreferredCodecs == SlimRules.default.subtitlePreferredCodecs)
  }

  /// AV1 sources are copied rather than transcoded, so no AV1 decoder is needed.
  @Test
  func `AV1 video is copied`() throws {
    let container = try JSONDecoder().decode(
      Container.self,
      from: Data(
        """
        {
          "streams": [
            {"index":0,"codec_name":"av1","codec_type":"video","width":1440,"height":1080,
             "disposition":{"default":1},"tags":{}},
            {"index":1,"codec_name":"aac","codec_type":"audio","sample_rate":"48000","channels":2,
             "bits_per_sample":0,"disposition":{"default":1},"tags":{"language":"eng"}}
          ],
          "format":{"filename":"/m.mkv","duration":"60.0","size":"1000"}
        }
        """.utf8
      )
    )
    let operations = try SlimRules.default.makeConverter(container: container).operations()
    let video = try #require(operations.first { $0.streamType == .video })
    #expect(video.kind == .copy)
  }

  @Test
  func `repairs an experimental audio transcode target`() throws {
    let rules = try decode(
      """
      {"languages":["eng"],"preserveNoLanguages":false,"includeOtherAudio":false,
       "videoPreferredCodecs":["hevc"],"videoConversionCodec":"hevc",
       "videoConversionOptions":[],
       "audioPreferredCodecs":["aac"],"audioConversionCodec":"truehd",
       "audioConversionOptions":[],"subtitlePreferredCodecs":["subrip"]}
      """
    )
    #expect(rules.audioConversionCodec == "eac3")
  }

  @Test
  func `leaves a usable audio transcode target alone`() throws {
    let rules = try decode(
      """
      {"languages":["eng"],"preserveNoLanguages":false,"includeOtherAudio":false,
       "videoPreferredCodecs":["hevc"],"videoConversionCodec":"hevc",
       "videoConversionOptions":[],
       "audioPreferredCodecs":["aac"],"audioConversionCodec":"flac",
       "audioConversionOptions":[],"subtitlePreferredCodecs":["subrip"]}
      """
    )
    #expect(rules.audioConversionCodec == "flac")
  }
}
