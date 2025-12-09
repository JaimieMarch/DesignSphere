

import SwiftUI

struct NavigationOrnament: View {
    // Bind to the parent view’s active screen
    // Updates floww both ways: parent -> ornament, ornament -> parent
    @Binding var currentScreen: StarterView.ScreenTab
    // Triggered whenever the user attempts to switch tabs
    var onTabWillChange: ((StarterView.ScreenTab) -> Void)?
    
    // Default selected tab
    @State private var selectedTab: Int = 0

    // Prevents update loops between selectedTab and currentScreen
    @State private var isChangingTab = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(StarterView.ScreenTab.allCases, id: \.rawValue) { screen in
                // Placeholder views
                Color.clear
                    .tabItem {
                        Label(screen.label, systemImage: screen.icon)
                    }
                    .tag(screen.rawValue)
            }
        }
        // Set ornament dimensions
        .frame(width: 80, height: 450)
        // Init local state from the binding
        .onAppear {
            selectedTab = currentScreen.rawValue
        }
        // User selects a new tab
        .onChange(of: selectedTab) { oldValue, newValue in
            guard !isChangingTab else { return }
            handleTabChange(oldValue, newValue)
        }
        // Parent view changes the current screen
        .onChange(of: currentScreen) { oldValue, newValue in
            if selectedTab != newValue.rawValue {
                // turn on the boolean
                // this stops onChange(selectedTab)
                isChangingTab = true
                selectedTab = newValue.rawValue
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isChangingTab = false
                }
            }
        }
    }
    
    // send event to parent
    private func handleTabChange(_ oldValue: Int, _ newValue: Int) {
        if let screenTab = StarterView.ScreenTab(rawValue: newValue) {
            if oldValue != newValue {
                onTabWillChange?(screenTab)
            }
        }
    }
}
