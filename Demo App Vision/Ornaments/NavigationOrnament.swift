// Tabview ornament (the one on the left) is the navigation view

import SwiftUI

struct NavigationOrnament: View {
    // connect this file to starterview
    @Binding var currentScreen: StarterView.ScreenTab
    // gets called when a new tab is selected
    var onTabWillChange: ((StarterView.ScreenTab) -> Void)?
    
    // default selected tab
    @State private var selectedTab: Int = 0
    @State private var previousTab: Int = 0

    // avoid looped interactions - can't change while changing
    @State private var isChangingTab = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(StarterView.ScreenTab.allCases, id: \.rawValue) { screen in
                // placeholder
                Color.clear
                    .tabItem {
                        Label(screen.label, systemImage: screen.icon)
                    }
                    .tag(screen.rawValue)
            }
        }
        // ornament sizing
        .frame(width: 80, height: 450)
        .onAppear {
            selectedTab = currentScreen.rawValue
            previousTab = currentScreen.rawValue
        }
        // when another tab is selected
        .onChange(of: selectedTab) {
            guard !isChangingTab else { return }
            handleTabChange(previousTab, selectedTab)
            previousTab = selectedTab
        }
        .onChange(of: currentScreen) {
            if selectedTab != currentScreen.rawValue {
                // turn on the boolean
                // this stops onChange(selectedTab)
                isChangingTab = true
                selectedTab = currentScreen.rawValue
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
