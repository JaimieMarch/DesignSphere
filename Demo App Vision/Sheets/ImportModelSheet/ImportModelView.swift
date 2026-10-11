import SwiftUI
import XRShareCollaboration
import UniformTypeIdentifiers

struct ImportModelView: View {
    @Binding var isPresented: Bool
    @ObservedObject var controller: CollaborativeSessionController

    @State private var showFilePicker = false
    @State private var importStatus: ImportStatus = .idle
    @State private var errorMessage: String?
    @State private var importedFileName: String?
    @State private var isViewActive = false
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    private enum ImportStatus: Equatable {
        case idle
        case importing
        case success
        case error
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header section
                VStack(spacing: 16) {
                    Image(systemName: statusIcon)
                        .font(.largeTitle)
                        .imageScale(.large)
                        .foregroundStyle(statusColor)
                        .accessibilityHidden(true)

                    Text(statusTitle)
                        .font(.title)
                        .bold()
                        .accessibilityAddTraits(.isHeader)

                    Text(statusDescription)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 20)

                // Action buttons based on status
                VStack(spacing: 12) {
                    if importStatus == .idle || importStatus == .error {
                        Button(action: {
                            showFilePicker = true
                        }) {
                            Label("Choose USDZ File", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityLabel("Choose USDZ file")
                        .accessibilityHint("Open file picker to select a 3D model to import")
                    }

                    if importStatus == .importing {
                        ProgressView()
                            .scaleEffect(1.5)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    }

                    if importStatus == .success {
                        Button(action: {
                            isPresented = false
                        }) {
                            Label("Done", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 32)
            .frame(minWidth: 500)
            .navigationTitle("Import Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
            .onAppear {
                isViewActive = true
            }
            .onDisappear {
                isViewActive = false
            }
            .onChange(of: importStatus) { _, _ in
                AccessibilityNotification.Announcement("\(statusTitle). \(statusDescription)").post()
            }
            // Only attach fileImporter when view is actually active
            // This prevents it from interfering with other UI elements when sheet is hidden
            .background(
                Group {
                    if isViewActive {
                        Color.clear
                            .fileImporter(
                                isPresented: $showFilePicker,
                                allowedContentTypes: [.usdz],
                                allowsMultipleSelection: false
                            ) { result in
                                handleFileImport(result)
                            }
                    }
                }
            )
        }
    }

    private var statusIcon: String {
        switch importStatus {
        case .idle:
            return "square.and.arrow.down"
        case .importing:
            return "arrow.down.circle"
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch importStatus {
        case .idle:
            return .secondary
        case .importing:
            return .blue
        case .success:
            return .green
        case .error:
            return .red
        }
    }

    private var statusTitle: String {
        switch importStatus {
        case .idle:
            return "Import Model"
        case .importing:
            return "Importing..."
        case .success:
            return "Import Successful"
        case .error:
            return "Import Failed"
        }
    }

    private var statusDescription: String {
        switch importStatus {
        case .idle:
            return "Select a USDZ file from your device to add it to your catalog"
        case .importing:
            return "Processing your model file..."
        case .success:
            if let fileName = importedFileName {
                return "'\(fileName)' has been added to your catalog"
            }
            return "Your model has been added to the catalog"
        case .error:
            return errorMessage ?? "An error occurred while importing the model"
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        importStatus = .importing
        errorMessage = nil
        importedFileName = nil

        // VoiceOver users need time to hear the result and dismiss with "Done";
        // a 2 second timer would cut the announcement off.
        let shouldAutoDismiss = !voiceOverEnabled

        Task {
            do {
                let selectedURLs = try result.get()
                guard let sourceURL = selectedURLs.first else {
                    throw ImportError.noFileSelected
                }

                importedFileName = try await ModelImportManager.importModel(
                    from: sourceURL,
                    existingNames: Set(controller.availableModels.map { $0.type.rawValue })
                )

                // Refresh available models on main thread
                await MainActor.run {
                    controller.refreshAvailableModels()
                }

                // Update status to success
                await MainActor.run {
                    importStatus = .success
                }

                // Auto-dismiss after 2 seconds unless VoiceOver is running.
                if shouldAutoDismiss {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await MainActor.run {
                        isPresented = false
                    }
                }

            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    importStatus = .error
                }
            }
        }
    }

    private enum ImportError: LocalizedError {
        case noFileSelected

        var errorDescription: String? { "No file was selected." }
    }
}
