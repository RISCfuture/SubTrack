/**
 How loudly something wrong reads.

 One vocabulary for the whole app, so a single condition cannot change severity
 depending on which window it is shown in. The tiers are about consequence, not
 about which control is reporting: a problem is something the app cannot do as
 things stand, a warning is a plan or setting at fault that editing would fix,
 and a note is a remark worth making about something otherwise fine.

 Ordered lowest first, so rolling several states up into one indicator is
 `max()` rather than a second statement of the same policy.
 */
public enum Severity: Sendable, Comparable {

  /// A remark about something that is not wrong — an output that would be silent, say.
  case note

  /// A plan or setting at fault, which editing would fix.
  case warning

  /// Something that cannot produce what was asked for as things stand.
  case problem
}
