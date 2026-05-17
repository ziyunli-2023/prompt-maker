import Foundation
import SwiftUI

@MainActor
final class PromptStore: ObservableObject {
    @Published var input: String = ""
    @Published var translation: String = ""
    @Published var optimized: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    func reset() {
        input = ""
        translation = ""
        optimized = ""
        errorMessage = nil
    }

    func restore(from entry: HistoryEntry) {
        input = entry.input
        translation = entry.translation
        optimized = entry.optimized
        errorMessage = nil
    }
}
