import Foundation
import SwiftData

/**
 The SwiftData persistence record for a ``Preset``. Modeled CloudKit-ready:
 every property has a default and there are no unique constraints, so a
 CloudKit-backed container can be enabled later without a migration.
 */
@Model
public final class StoredPreset {
  /// The preset's stable identity, which the starter presets pin so they are never duplicated.
  public var id = UUID()

  /// The name shown in the preset menu.
  public var name: String = ""

  /// The preset's rules, stored as encoded JSON for forward compatibility.
  public var rulesData = Data()

  /**
   The preset's ``OutputNameFormat`` as its raw template text. Empty for
   records written before formats existed, which read back as
   ``OutputNameFormat/slimmed`` — the name those presets already produced.
   */
  public var nameTemplate: String = ""

  /**
   When this record was last written. Ranks copies of the same preset when
   CloudKit has merged more than one, which it can do because CloudKit cannot
   enforce a unique constraint on ``id``.
   */
  public var modifiedAt = Date.now

  /// Creates a record from already-encoded field values, defaulting every one.
  public init(
    id: UUID = UUID(),
    name: String = "",
    rulesData: Data = Data(),
    nameTemplate: String = "",
    modifiedAt: Date = .now
  ) {
    self.id = id
    self.name = name
    self.rulesData = rulesData
    self.nameTemplate = nameTemplate
    self.modifiedAt = modifiedAt
  }
}

extension StoredPreset {

  /// The decoded rules (backed by ``rulesData``).
  public var rules: SlimRules {
    get { (try? JSONDecoder().decode(SlimRules.self, from: rulesData)) ?? .default }
    set { rulesData = Self.encode(newValue) }
  }

  /// The decoded output-name format (backed by ``nameTemplate``).
  public var naming: OutputNameFormat {
    get { nameTemplate.isEmpty ? .slimmed : OutputNameFormat(template: nameTemplate) }
    set { nameTemplate = newValue.template }
  }

  /// The value-type projection used throughout the UI and engine.
  public var asPreset: Preset {
    Preset(id: id, name: name, rules: rules, naming: naming)
  }

  /// Creates a record for a named preset, encoding `rules` and `naming` into their blobs.
  public convenience init(
    id: UUID = UUID(),
    name: String,
    rules: SlimRules,
    naming: OutputNameFormat = .slimmed,
    modifiedAt: Date = .now
  ) {
    self.init(
      id: id,
      name: name,
      rulesData: Self.encode(rules),
      nameTemplate: naming.template,
      modifiedAt: modifiedAt
    )
  }

  static func encode(_ rules: SlimRules) -> Data {
    (try? JSONEncoder().encode(rules)) ?? Data()
  }
}
