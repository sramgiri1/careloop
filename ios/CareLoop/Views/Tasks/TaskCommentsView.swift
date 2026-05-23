import SwiftUI

struct TaskCommentsView: View {
    @EnvironmentObject private var appState: AppState
    let task: CareTask

    @State private var comments: [TaskComment] = []
    @State private var draft    = ""
    @State private var loading  = true
    @State private var posting  = false
    @State private var error:   String?

    private let teal = Color(red: 0.16, green: 0.80, blue: 0.72)
    private let dark = Color(red: 0.10, green: 0.16, blue: 0.24)
    private let mid  = Color(red: 0.43, green: 0.50, blue: 0.60)
    private let bg   = Color(red: 0.95, green: 0.96, blue: 0.99)

    private var canDelete: Bool { appState.userRole == .admin }
    private var currentUserId: String? { appState.currentUser?.id }

    var body: some View {
        VStack(spacing: 0) {
            commentList
            Divider()
            composerBar
        }
        .background(bg.ignoresSafeArea())
        .navigationTitle("Comments")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: – Comment list

    private var commentList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if comments.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 36))
                            .foregroundStyle(mid)
                        Text("No comments yet")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(dark)
                        Text("Be the first to leave a note.")
                            .font(.system(size: 13))
                            .foregroundStyle(mid)
                    }
                    .padding(.top, 80)
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(comments) { comment in
                            commentRow(comment)
                                .id(comment.id)
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
                if let error {
                    Text(error)
                        .font(.footnote).foregroundStyle(.red)
                        .padding(.horizontal, 16).padding(.bottom, 8)
                }
            }
            .accessibilityIdentifier("task-comments-screen")
            .onChange(of: comments) { _ in
                if let last = comments.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    @ViewBuilder
    private func commentRow(_ comment: TaskComment) -> some View {
        let isOwn = comment.authorId == currentUserId
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(isOwn ? teal.opacity(0.15) : mid.opacity(0.12))
                .frame(width: 34, height: 34)
                .overlay(
                    Text(initials(comment.author?.name ?? "?"))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(isOwn ? teal : mid)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.author?.name ?? "Unknown")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(dark)
                    Text(timeLabel(comment.createdAt))
                        .font(.system(size: 12))
                        .foregroundStyle(mid)
                    Spacer()
                    if isOwn || canDelete {
                        Button {
                            Task { await deleteComment(comment) }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundStyle(mid.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete comment")
                        .accessibilityIdentifier("task-comment-delete-\(comment.id)")
                    }
                }
                Text(comment.body)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(dark)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityIdentifier("task-comment-row-\(comment.id)")
    }

    // MARK: – Composer

    private var composerBar: some View {
        HStack(spacing: 10) {
            TextField("Add a comment…", text: $draft, axis: .vertical)
                .font(.system(size: 14, design: .rounded))
                .lineLimit(1...4)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityIdentifier("task-comment-field")

            Button {
                Task { await post() }
            } label: {
                if posting {
                    ProgressView().scaleEffect(0.75)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? mid.opacity(0.3) : teal)
                }
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || posting)
            .accessibilityIdentifier("task-comment-send-button")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: – Helpers

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        guard !parts.isEmpty else { return "?" }
        let first = parts[0].prefix(1)
        let second = parts.count > 1 ? parts[1].prefix(1) : Substring("")
        return (first + second).uppercased()
    }

    private func timeLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: – Actions

    private func load() async {
        guard let circleId = appState.activeCircle?.id else {
            loading = false
            return
        }
        if UITestScenario.current != nil {
            comments = []
            loading = false
            return
        }
        do {
            comments = try await APIClient.shared.fetchComments(circleId: circleId, taskId: task.id)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func post() async {
        guard let circleId = appState.activeCircle?.id else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        posting = true
        error = nil
        if UITestScenario.current != nil {
            comments.append(TaskComment(
                id: "ui-comment-\(UUID().uuidString)",
                body: text,
                createdAt: Date(),
                authorId: currentUserId ?? "ui-user",
                author: CommentAuthor(id: currentUserId ?? "ui-user", name: appState.currentUser?.name ?? "CareLoop User")
            ))
            draft = ""
            posting = false
            return
        }
        do {
            let comment = try await APIClient.shared.postComment(circleId: circleId, taskId: task.id, body: text)
            comments.append(comment)
            draft = ""
        } catch {
            self.error = error.localizedDescription
        }
        posting = false
    }

    private func deleteComment(_ comment: TaskComment) async {
        guard let circleId = appState.activeCircle?.id else { return }
        error = nil
        if UITestScenario.current != nil {
            comments.removeAll { $0.id == comment.id }
            return
        }
        do {
            try await APIClient.shared.deleteComment(circleId: circleId, taskId: task.id, commentId: comment.id)
            comments.removeAll { $0.id == comment.id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
