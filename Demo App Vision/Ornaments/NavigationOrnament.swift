import SwiftUI

struct NavigationOrnament: View {
    @Binding var currentScreen: StarterView.ScreenTab
    var onTabWillChange: ((StarterView.ScreenTab) -> Void)?
    
    @State private var selectedTab: Int = 0
    @State private var isChangingTab = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(StarterView.ScreenTab.allCases, id: \.rawValue) { screen in
                Color.clear
                    .tabItem {
                        Label(screen.label, systemImage: screen.icon)
                    }
                    .tag(screen.rawValue)
            }
        }
        .frame(width: 80, height: 450)
        .onAppear {
            selectedTab = currentScreen.rawValue
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            guard !isChangingTab else { return }
            handleTabChange(oldValue, newValue)
        }
        .onChange(of: currentScreen) { oldValue, newValue in
            if selectedTab != newValue.rawValue {
                isChangingTab = true
                selectedTab = newValue.rawValue
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isChangingTab = false
                }
            }
        }
    }
    
    private func handleTabChange(_ oldValue: Int, _ newValue: Int) {
        if let screenTab = StarterView.ScreenTab(rawValue: newValue) {
            if oldValue != newValue {
                onTabWillChange?(screenTab)
            }
        }
    }
}
