extension Array where Element: Hashable {

  /**
   Returns a new array with duplicate elements removed, preserving order.

   The first occurrence of each element is kept; subsequent duplicates
   are removed.

   - Returns: A new array containing only the unique elements from this array,
     in their original order of first appearance.
   */
  func removingDuplicates() -> Array {
    var seen = Set<Element>()
    return self.filter { element in
      if seen.contains(element) { return false }
      seen.insert(element)
      return true
    }
  }
}
