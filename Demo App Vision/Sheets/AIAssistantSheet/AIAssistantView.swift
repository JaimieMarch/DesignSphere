import SwiftUI
import XRShareCollaboration

@available(visionOS 26.0, *)
struct AIAssistantView: View {
    @ObservedObject var controller: CollaborativeSessionController
    @Binding var isPresented: Bool

    private let advisor = DesignAdvisor()
    @ObservedObject private var downloads = RemoteDownloadProgress.shared

    @State private var suggestions: [CollaborativeSessionController.ModelDescriptor] = []
    @State private var headline = ""
    @State private var placedIDs: Set<String> = []
    @State private var prompt = ""
    @State private var isThinking = false

    private var hasPlacedModels: Bool { !controller.placedModelDescriptors.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            if DesignAssistantLLM.isAvailable {
                naturalLanguageField
            }
            quickActions
            Divider().opacity(0.4)
            suggestionsArea
            Spacer(minLength: 0)
        }
        .padding(28)
    }

    // MARK: - Natural language (on-device LLM, when available)

    private var naturalLanguageField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Describe what you want").font(.headline)
            HStack(spacing: 10) {
                TextField("e.g. a cozy minimalist reading nook", text: $prompt)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submitPrompt)
                Button(action: submitPrompt) {
                    if isThinking {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                }
                .buttonStyle(.plain)
                .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty || isThinking)
                .accessibilityLabel("Ask the assistant")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Design Assistant", systemImage: "sparkles")
                    .font(.title2.weight(.semibold))
                Text("Furnish a room in one tap, or complete what you've started — all from your catalog.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { isPresented = false } label: {
                Image(systemName: "xmark").font(.headline).frame(width: 30, height: 30)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Close assistant")
        }
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Furnish a room").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(DesignAdvisor.RoomType.allCases) { room in
                    Button { furnish(room) } label: {
                        Label(room.title, systemImage: room.icon)
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.bordered)
                }
            }

            Button { completeSpace() } label: {
                Label("Complete my space", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasPlacedModels)
            .accessibilityHint(hasPlacedModels ? "Suggests pieces that pair with what you've placed" : "Place a model first")
        }
    }

    // MARK: - Suggestions

    @ViewBuilder
    private var suggestionsArea: some View {
        if suggestions.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.secondary)
                Text(headline.isEmpty ? "Pick a room above to get started." : headline)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(headline).font(.headline)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
                        ForEach(suggestions) { descriptor in
                            suggestionCard(descriptor)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
    }

    private func suggestionCard(_ descriptor: CollaborativeSessionController.ModelDescriptor) -> some View {
        let isPlaced = placedIDs.contains(descriptor.id)
        return VStack(spacing: 6) {
            ModelPreviewView(modelType: descriptor.type,
                             size: CGSize(width: 110, height: 90),
                             showBackground: false)
                .frame(height: 90)
            Text(descriptor.name)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(10)
        .frame(width: 150, height: 150)
        .glassBackground(cornerRadius: 16)
        .overlay(alignment: .topTrailing) {
            if isPlaced {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .padding(8)
            } else if let fraction = downloads.fraction(for: descriptor.id) {
                ProgressView(value: fraction)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .padding(8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { place(descriptor) }
        .accessibilityLabel(descriptor.name)
        .accessibilityHint(isPlaced ? "Added" : "Tap to add to your space")
    }

    // MARK: - Actions

    private func furnish(_ room: DesignAdvisor.RoomType) {
        suggestions = advisor.roomSet(for: room, from: controller.availableModels)
        headline = suggestions.isEmpty ? "No catalog models for that room yet." : "A \(room.title.lowercased()) set — tap any piece to place it"
        placedIDs = []
    }

    private func completeSpace() {
        let placed = controller.placedModelDescriptors
        let categoryByID = Dictionary(
            controller.availableModels.map { ($0.id, $0.category.rawValue) },
            uniquingKeysWith: { first, _ in first }
        )
        let placedCategories = placed.compactMap { categoryByID[$0.type.id] }
        let placedTypeIDs = Set(placed.map { $0.type.id })
        suggestions = advisor.complements(
            placedCategories: placedCategories,
            placedIDs: placedTypeIDs,
            from: controller.availableModels
        )
        headline = suggestions.isEmpty ? "Looks complete — try a room set above." : "Pieces that pair with your space"
        placedIDs = []
    }

    private func place(_ descriptor: CollaborativeSessionController.ModelDescriptor) {
        guard !placedIDs.contains(descriptor.id) else { return }
        controller.addModel(descriptor)
        placedIDs.insert(descriptor.id)
    }

    private func submitPrompt() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        isThinking = true
        Task {
            let interpretation = await DesignAssistantLLM.interpret(text)
            applyInterpretation(interpretation, request: text)
            isThinking = false
        }
    }

    private func applyInterpretation(_ interpretation: DesignAssistantLLM.Interpretation?, request: String) {
        placedIDs = []
        if let room = interpretation?.room {
            suggestions = advisor.roomSet(for: room, from: controller.availableModels)
            headline = "Ideas for “\(request)”"
        } else if let keys = interpretation?.categoryKeys, !keys.isEmpty {
            suggestions = advisor.models(inCategories: keys, from: controller.availableModels)
            headline = "Ideas for “\(request)”"
        } else {
            suggestions = []
            headline = "I couldn't turn that into suggestions — try a room above."
        }
    }
}
