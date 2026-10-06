import Subprocess

extension TerminationStatus {

  /**
   The number the run ended on — the exit status where the tool chose it, and
   the signal number where something else did.

   The FFmpeg tools report what went wrong on standard error, so the number is
   a label on that explanation rather than the explanation itself, and one
   field is enough to carry it.

   An exit status is the 8-bit value a shell shows. Darwin's `waitid` hands
   back 24 bits of what the tool passed to `exit`, so FFmpeg's `exit(-22)`
   would otherwise read as 16777194 rather than 234.
   */
  var code: Code {
    switch self {
      case .exited(let code): code & 0xFF
      case .signaled(let signal): signal
    }
  }
}
