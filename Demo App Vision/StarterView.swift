import SwiftUI
import XRShareCollaboration

@available(visionOS 26.0, *)
struct StarterView: View {
    @ObservedObject var controller: CollaborativeSessionController

    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
#if os(visionOS)
    @State private var isImmersiveOpen = false
#endif

    @State private var hasInitializedSession = false
    @State private var isActivatingSharePlay = false
    @State private var sharePlayError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    
                    sharePlayCard
                    sessionStatsCard
                    availableModelsCard
                    currentAddedModelsCard
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 40)
            }
            .navigationTitle("Demo App")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if controller.isConnected {
                        Text("Connected")
                            .font(.footnote)
                            .foregroundStyle(.green)
                    } else {
                        Text("Offline")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
            }
            }
        }
#if os(visionOS)
        .onAppear {
            isImmersiveOpen = false
        }
#endif
        // Start a local session when app is launched
        .task {
            await prepareExperience()
        }
        // Error alert for any shareplay errors
        .alert("SharePlay", isPresented: Binding(
            get: { sharePlayError != nil },
            set: { if !$0 { sharePlayError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            if let message = sharePlayError {
                Text(message)
            }
        }
    }

// MARK: - Section for SharePlay
    
    /// Section with the shareplay button to start a shared session
    private var sharePlayCard: some View {
        
        SectionCard(title: "SharePlay") {
            VStack(alignment: .leading, spacing: 12) {
                
                Text("Start a SharePlay session")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                
                // Can start a shareplay session from the local session
                HStack(spacing: 16) {
                    SharePlayLauncher(isActivating: $isActivatingSharePlay, errorMessage: $sharePlayError) {
                        controller.startSharePlayHosting(named: "Shared Session")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)

                    Spacer()
                }
            }
        }
    }

    
    
// MARK: - Session Stats Section
    
    /// Card that displays the participants, number of placed models and loading status of the session
    private var sessionStatsCard: some View {
        
        SectionCard(title: "Session Overview") {
            HStack(spacing: 20) {
                StatCard(icon: "person.2.fill", title: "Participants", value: "\(controller.participantCount)")
                
                StatCard(icon: "cube.box.fill", title: "Models", value: "\(controller.placedModelSummaries.count)")
                
                StatCard(icon: "arrow.down.circle.fill", title: "Loading", value:
                            progressText)
            }
        }
    }
    
    

// MARK: - Available Models To Add Section
    
    /// Card that displays the list of available models to add to the session
    private var availableModelsCard: some View {
        SectionCard(title: "Available Models") {
            if controller.availableModels.isEmpty {
                Text("No USDZ assets were found in the app bundle.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                
                VStack(spacing: 12) {
                    
                    ForEach(controller.availableModels) { descriptor in
                        
                        ModelListRow(descriptor: descriptor) {
                            
                            controller.addModel(descriptor)
                        }
                        if descriptor.id != controller.availableModels.last?.id {
                            Divider().background(.secondary.opacity(0.2))
                        }
                    }
            }
        }
        }
    }

    /// UI for for rows with each model and a add button
    private struct ModelListRow: View {
        let descriptor: CollaborativeSessionController.ModelDescriptor
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(descriptor.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    
                    // Add single model
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
                .contentShape(Rectangle())
        }
            .buttonStyle(.plain)
        }
    }

    
// MARK: - Current Added Models Section
    
    /// Card that displays the list of currently added models to the session and button to remove them
    private var currentAddedModelsCard: some View {
        
        SectionCard(title: "Current Added Models") {
            
            if controller.placedModelSummaries.isEmpty {
                Text("No models placed yet, add one from above")
                
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                
                
                
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(controller.placedModelSummaries, id: \.self) { name in
                        HStack {
                            Label(name, systemImage: "cube.fill")
                                .font(.body)
                            Spacer()
                            
                            // Delete single model
                            Button(role: .destructive) {
                                controller.removeModel(named: name)
                            } label: {
                                Image(systemName: "trash")
                            }
                            
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                    
                    // Delete all models
                    Button(role: .destructive, action: controller.removeAllModels) {
                        Label("Delete all models", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
    }
    }

// MARK: - Helpers
    
    @MainActor

    // Starts up the local session
    private func prepareExperience() async {
        // Just run once, subsequent runs will just make sure immersive space is open
        guard hasInitializedSession == false else {
            
            await ensureImmersiveSpaceOpened()
            
            return
            }
    
        controller.startLocalSession()
        
        hasInitializedSession = true
        
        // Load and cache the models
        await controller.preloadIfNeeded()
        
        // Make sure immersive space is open
        await ensureImmersiveSpaceOpened()
    }

    
    
    private func ensureImmersiveSpaceOpened() async {
#if os(visionOS)
        guard isImmersiveOpen == false else { return }
        let result = await openImmersiveSpace(id: "CollaborativeSpace")
        if case .opened = result {
            await MainActor.run {
                isImmersiveOpen = true
            }
        }
#endif
    }
    
    
    private var progressText: String {
        let percentage = Int(controller.loadingProgress * 100)
        return controller.loadingProgress >= 1.0 ? "Ready" : "\(percentage)%"
    }
}

/// Used for the Session Stats section
private struct StatCard: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title2.bold())

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
}


/// Used by the other sections
private struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.title3.bold())
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
}


