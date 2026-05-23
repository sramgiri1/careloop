import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if UITestScenario.current == .taskComments, let task = uiTestCommentsTask {
            NavigationStack {
                TaskCommentsView(task: task)
                    .environmentObject(appState)
            }
        } else if appState.activeCircle == nil {
            CircleListView()
                .environmentObject(appState)
        } else {
            CircleHomeView()
                .environmentObject(appState)
        }
    }

    private var uiTestCommentsTask: CareTask? {
        let taskId = UITestScenario.pendingTaskId(ProcessInfo.processInfo.arguments) ?? "t2"
        return appState.activeCircle?.tasks?.first { $0.id == taskId }
    }
}
