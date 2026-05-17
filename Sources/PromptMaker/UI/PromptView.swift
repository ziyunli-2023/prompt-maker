import SwiftUI
import AppKit

struct PromptView: View {
    @ObservedObject var promptStore: PromptStore
    @ObservedObject var historyStore: HistoryStore
    let onDismiss: () -> Void

    @State private var showHistory: Bool = false
    @FocusState private var inputFocused: Bool

    init(promptStore: PromptStore, historyStore: HistoryStore, onDismiss: @escaping () -> Void) {
        self._promptStore = ObservedObject(initialValue: promptStore)
        self._historyStore = ObservedObject(initialValue: historyStore)
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(spacing: 0) {
            mainPane
            if showHistory {
                Divider()
                historyPane
                    .frame(width: 260)
            }
        }
        .frame(minWidth: 640, minHeight: 460)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        .onAppear { inputFocused = true }
    }

    private var mainPane: some View {
        VStack(spacing: 10) {
            header

            inputBlock

            controlsRow

            HStack(spacing: 10) {
                resultColumn(
                    title: "直译",
                    text: $promptStore.translation,
                    onCopy: { copy(promptStore.translation) }
                )
                resultColumn(
                    title: promptStore.optimized.isEmpty ? "优化版" : "优化版（已复制 ✓）",
                    text: $promptStore.optimized,
                    onCopy: { copy(promptStore.optimized) }
                )
            }
        }
        .padding(12)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("PromptMaker")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            Button {
                showHistory.toggle()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 16))
            }
            .buttonStyle(.borderless)
            .help("历史记录")

            Button {
                promptStore.reset()
                inputFocused = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16))
            }
            .buttonStyle(.borderless)
            .help("新建")

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
            }
            .buttonStyle(.borderless)
            .help("收起 (Esc)")
        }
    }

    private var inputBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("输入（中英混写）")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            TextEditor(text: $promptStore.input)
                .focused($inputFocused)
                .font(.system(size: 16))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 90, maxHeight: 140)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .cornerRadius(6)
                .disabled(promptStore.isLoading)
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 10) {
            if let err = promptStore.errorMessage {
                Text(err)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
            Spacer()
            Button {
                Task { await submit() }
            } label: {
                if promptStore.isLoading {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("处理中…").font(.system(size: 14))
                    }
                } else {
                    Text("优化 (⌘↩)").font(.system(size: 14, weight: .medium))
                }
            }
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(promptStore.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || promptStore.isLoading)
        }
    }

    private func resultColumn(title: String, text: Binding<String>, onCopy: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .help("复制")
                .disabled(text.wrappedValue.isEmpty)
            }
            TextEditor(text: text)
                .font(.system(size: 16))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .cornerRadius(6)
        }
    }

    private var historyPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("历史").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    historyStore.clear()
                } label: {
                    Image(systemName: "trash").font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .help("清空历史")
                .disabled(historyStore.entries.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)

            if historyStore.entries.isEmpty {
                Spacer()
                Text("暂无历史")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(historyStore.entries) { entry in
                    Button {
                        promptStore.restore(from: entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.input)
                                .font(.system(size: 13))
                                .lineLimit(2)
                                .foregroundStyle(.primary)
                            Text(entry.timestamp, style: .relative)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
    }

    private func submit() async {
        let trimmed = promptStore.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        promptStore.isLoading = true
        promptStore.errorMessage = nil
        defer { promptStore.isLoading = false }

        let service = ServiceFactory.make()
        do {
            let result = try await service.complete(input: trimmed)
            promptStore.translation = result.translation
            promptStore.optimized = result.optimized
            copy(result.optimized)
            historyStore.add(
                HistoryEntry(
                    id: UUID(),
                    timestamp: Date(),
                    input: trimmed,
                    translation: result.translation,
                    optimized: result.optimized
                )
            )
        } catch {
            promptStore.errorMessage = error.localizedDescription
        }
    }

    private func copy(_ text: String) {
        guard !text.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
