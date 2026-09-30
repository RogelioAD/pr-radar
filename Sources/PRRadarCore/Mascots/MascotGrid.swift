import Foundation

/// How the mascot room lays the cast out: one shelf per cohort, four to a row.
///
/// Four because that is what every cohort holds, so the grid reads as a set
/// of complete rows rather than as a list that happens to wrap. A cohort with
/// a count that is not a multiple of four leaves a ragged last line; the cast
/// is pinned to keep that from happening by accident.
public enum MascotGrid {
    public static let columns = 4

    /// One section of the room.
    public struct Shelf: Identifiable, Sendable {
        public let cohort: MascotCohort
        public let members: [Mascot]
        public var id: String { cohort.rawValue }

        /// The members split into rows of `columns`.
        public var rows: [[Mascot]] {
            stride(from: 0, to: members.count, by: columns).map {
                Array(members[$0..<min($0 + columns, members.count)])
            }
        }
    }

    /// The shelves with anybody on them, oldest cohort first.
    ///
    /// An empty shelf is dropped rather than drawn as a heading over nothing.
    /// That is mostly about the custom one: for everybody who has not forked
    /// the app it holds nobody, and a section titled with your own name and
    /// containing nothing reads as something being broken.
    public static var shelves: [Shelf] {
        MascotCohort.ordered.compactMap { cohort in
            let members = Mascot.cohort(cohort)
            return members.isEmpty ? nil : Shelf(cohort: cohort, members: members)
        }
    }

    /// A stable id for one shelf's measured height.
    public static func shelfID(_ cohort: MascotCohort) -> String { "shelf.\(cohort.rawValue)" }
}
