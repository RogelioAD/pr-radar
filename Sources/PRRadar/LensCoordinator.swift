import Foundation
import PRRadarCore

/// Reads review language back in plain English, for everything currently on
/// screen.
///
/// The third coordinator, and much the smallest, because it is the only one
/// that cannot do any harm. `AutoReviewCoordinator` posts under your name and
/// `ResolveCoordinator` wrote to your checkout; this one produces text that is
/// shown and never sent. That shapes every decision below:
///
/// - **It fails silently.** A run that times out, exits non-zero or comes back
///   unreadable leaves the original words on screen. There is no failed state
///   on a row, no retry button and no error chip, because the fallback is not a
///   degraded experience — it is the app as it was before this feature.
/// - **It is interruptible and restartable at no cost.** Nothing lands
///   anywhere, so a cancelled run is simply a run that did not finish.
/// - **It never runs by itself.** Switching the lens on runs it; a poll that
///   brings in new text runs it for that text only. Nothing else does.
@MainActor
final class LensCoordinator {

    private let state: AppState
    private var task: Task<Void, Never>?
    /// Which run the current `task` is.
    ///
    /// Bumped whenever a run starts or is stopped, and checked before a
    /// finishing run touches anything. Without it a run that was cancelled and
    /// replaced still cleared `task` and `lensTranslating` on its way out —
    /// so toggling the lens off and on again while a batch was in flight left
    /// the new run with no handle, a spinner that had already stopped, and a
    /// press that appeared to do nothing.
    private var generation = 0

    /// Generous for what it is. A batch of twenty short rewrites through Haiku
    /// is seconds, and the ceiling exists for a hung process rather than a slow
    /// one — but a lens run competing with a review on a busy machine can wait
    /// a while for its turn at the CLI.
    private static let timeout: TimeInterval = 180

    /// How many batches run at once.
    ///
    /// Two, which is a throttle rather than a tuning. Each is a separate
    /// `claude` process and the drawer is a menu-bar app; four of them starting
    /// at once because somebody opened the lens on a busy day is a visible
    /// stutter for a feature that is meant to feel like turning on a light.
    private static let concurrency = 3

    init(state: AppState) {
        self.state = state
    }

    // MARK: - The switch

    /// Turns the lens on or off, and translates what is missing when on.
    func toggle() {
        state.lensOn.toggle()
        if state.lensOn {
            translateVisible()
        } else {
            // Nothing is thrown away. The readings stay cached, so switching
            // back is instant and free — and the run in flight is stopped,
            // because nobody is looking at what it would produce.
            stop()
        }
    }

    /// Reads whatever is on screen and has no reading yet.
    ///
    /// Safe to call on every poll: the store answers "already read" for
    /// everything it has seen, so a fetch that brought back nothing new costs
    /// one set lookup per visible item and starts no process at all.
    func translateVisible() {
        guard state.lensOn, state.claudePath != nil else { return }

        // What is on screen first, then everything else. The second list is
        // still worth asking for — a reading is cached by its text, so having
        // it ready is what makes opening a row afterwards instant — but it must
        // never be what the reader is waiting behind.
        let visible = state.lensStore.missing(from: state.lensVisibleSources)
        let rest = state.lensStore.missing(from: state.lensSources)
            .filter { !visible.contains($0) }
        let missing = visible + rest
        guard !missing.isEmpty else { return }

        // A run already going is left alone rather than restarted. Its batches
        // were chosen from a list that is a subset of this one — the store only
        // grows — so restarting would re-ask for everything already in flight.
        guard task == nil else { return }

        generation += 1
        let mine = generation
        task = Task { [weak self] in
            await self?.run(missing, generation: mine)
            // Only if this is still the current run. A cancelled one that
            // finishes late must not clear its successor's handle.
            guard let self, self.generation == mine else { return }
            self.task = nil
            self.state.lensTranslating = false
        }
    }

    func stop() {
        generation += 1
        task?.cancel()
        task = nil
        state.lensTranslating = false
    }

    // MARK: - Running

    private func run(_ sources: [String], generation mine: Int) async {
        guard let claude = state.claudePath else { return }
        state.lensTranslating = true

        let batches = LensInvocation.batches(of: sources)
        let model = Prefs.lensModel
        let budget = Prefs.lensBudget
        let paths = state.helperPaths()

        // Windowed rather than a flat `withTaskGroup` over every batch: the
        // group would start all of them at once, and the throttle is the point.
        var index = 0
        while index < batches.count {
            if Task.isCancelled || generation != mine { return }
            let window = batches[index..<min(index + Self.concurrency, batches.count)]

            let results = await withTaskGroup(
                of: [(source: String, plain: String)].self
            ) { group -> [[(source: String, plain: String)]] in
                for batch in window {
                    group.addTask {
                        await Self.translate(batch, claude: claude, model: model,
                                             budget: budget, extraPaths: paths)
                    }
                }
                var collected: [[(source: String, plain: String)]] = []
                for await result in group { collected.append(result) }
                return collected
            }

            if Task.isCancelled || generation != mine { return }
            // Filed as each window lands rather than all at the end, so a long
            // run fills the drawer in as it goes instead of changing nothing
            // for a minute and then everything at once.
            var store = state.lensStore
            for result in results {
                for reading in result { store.store(reading.plain, for: reading.source) }
            }
            state.lensStore = store

            index += Self.concurrency
        }
    }

    /// One batch, in its own process.
    ///
    /// `nonisolated` and static: it touches no app state, which is what lets
    /// several run at once without the main actor serialising them.
    private nonisolated static func translate(
        _ sources: [String], claude: String, model: String,
        budget: Double, extraPaths: [String]
    ) async -> [(source: String, plain: String)] {
        let request = LensRequest(sources: sources, model: model, budgetUSD: budget)
        guard let result = try? await ProcessRunner.run(
            executable: claude,
            arguments: LensInvocation.arguments(for: request),
            environment: ProcessRunner.environment(extraPaths: extraPaths),
            timeout: Self.timeout)
        else { return [] }

        return LensParser.parse(exitCode: result.exitCode, stdout: result.stdout,
                                timedOut: result.timedOut, sources: sources)
    }
}
