import Subprocess
import Testing

@testable import SubTrack_Common

@Suite
struct TerminationStatusCodeTests {

  /**
   Darwin's `waitid` reports the low 24 bits of the value a tool passed to
   `exit`, so FFmpeg's `exit(-22)` arrives as 16777194. The code is the 8-bit
   status a shell shows for the same run.
   */
  @Test(arguments: [(Int32(0x00FF_FFEA), Int32(234)), (1, 1)])
  func `an exit is reported as its 8-bit status`(raw: Int32, expected: Int32) {
    #expect(TerminationStatus.exited(raw).code == expected)
  }

  @Test
  func `a signal is reported as its number`() {
    #expect(TerminationStatus.signaled(9).code == 9)
  }
}
