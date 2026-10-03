import Subprocess

extension TerminationStatus {

  /**
   The number the run ended on — the exit status where the tool chose it, and
   the signal number where something else did.

   The FFmpeg tools report what went wrong on standard error, so the number is
   a label on that explanation rather than the explanation itself, and one
   field is enough to carry it.
   */
  var code: Code {
    switch self {
      case .exited(let code), .signaled(let code): code
    }
  }
}
