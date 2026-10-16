import Foundation
import FocusJudge

extension SessionController {
    /// Only the task and user-authored project context cross this boundary. No readings, OCR, titles or session facts.
    public func requestNextActions(timeoutNanoseconds: UInt64 = 15_000_000_000) {
        guard isActive else { return }
        cancelNextActions(); stuckShown = true
        guard aiAvailable else { nextActions = .failed; return }
        nextActions = .working
        let version = nextActionsGeneration, task = taskName, context = projectForNote?.context ?? ""
        let assistant = assistant
        nextActionsTask = Task { [weak self] in
            let result = await assistant.nextActions(task: task, context: context)
            guard let self, !Task.isCancelled, self.isActive, self.nextActionsGeneration == version, self.taskName == task else { return }
            self.nextActionsTimeout?.cancel()
            let filtered = result.map { FocusJudge.NextActionFilter.actions($0, task: task, context: context) } ?? []
            self.nextActions = filtered.isEmpty ? .failed : .ready(filtered)
        }
        nextActionsTimeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: timeoutNanoseconds) } catch { return }
            guard let self, self.nextActionsGeneration == version, self.nextActions.isWorking else { return }
            self.nextActionsGeneration += 1; self.nextActionsTask?.cancel(); self.nextActions = .failed
        }
    }
    public func cancelNextActions() {
        nextActionsGeneration += 1; nextActionsTask?.cancel(); nextActionsTimeout?.cancel()
        nextActions = .idle; stuckShown = false
    }
    public func waitForNextActions() async { await nextActionsTask?.value }
    public func chooseNextAction(_ action: String) {
        guard let actions = nextActions.value, actions.contains(action) else { return }
        changeTask(to: action)
    }
}
