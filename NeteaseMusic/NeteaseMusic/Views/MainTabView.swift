import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var selectedTab = 0
    @State private var showLogin = false
    @State private var searchAutoFocus = false
    @Namespace private var animation
    
    // 记录已访问过的 tab，用于懒加载
    @State private var loadedTabs: Set<Int> = [0, 1]
    
    // 搜索模式
    @State private var isSearchMode = false
    
    // Tab 配置
    private let tabs: [(Int, AnyView)] = [
        (0, AnyView(DiscoverView())),
        (1, AnyView(NewDiscoveryView())),
        (2, AnyView(LibraryView())),
        (3, AnyView(SettingsView()))
    ]
    
    // 键盘预热
    @State private var keyboardWarmedUp = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // 内容区域
            ZStack {
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, tabContent in
                    if loadedTabs.contains(index) {
                        NavigationStack {
                            tabContent.1
                        }
                        .opacity(selectedTab == index ? 1 : 0)
                        .zIndex(selectedTab == index ? 1 : 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .bottom)
            .onChange(of: selectedTab) { _, newTab in
                loadedTabs.insert(newTab)
            }
            
            // 底部导航栏
            VStack(spacing: 0) {
                CustomTabBar(
                    selectedTab: $selectedTab,
                    isSearchMode: $isSearchMode,
                    animation: animation
                )
                .zIndex(0)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: selectedTab)
            
            // 隐藏的键盘预热 TextField
            if !keyboardWarmedUp {
                KeyboardWarmer(didWarmUp: $keyboardWarmedUp)
            }
        }
        .ignoresSafeArea(.keyboard)
        .fullScreenCover(isPresented: $isSearchMode) {
            FullScreenSearchView(
                isSearchMode: $isSearchMode,
                previousTabIcon: ["house.fill", "square.grid.2x2", "person.fill", "gearshape.fill"][selectedTab]
            )
        }
        .task {
            await preWarmData()
        }
    }
    
    // ⬅ 改动4: 预热数据
    private func preWarmData() async {
        //  优化: 并发预热多个数据源
        async let hotSearch: () = Task.detached(priority: .utility) {
            _ = try? await MusicService.shared.getHotSearch()
        }.value
        
        async let banners: () = Task.detached(priority: .utility) {
            _ = try? await MusicService.shared.getBanners()
        }.value
        
        async let personalized: () = Task.detached(priority: .utility) {
            _ = try? await MusicService.shared.getPersonalized()
        }.value
        
        // 并发执行所有预热任务
        _ = await (hotSearch, banners, personalized)
    }
}

// MARK: - 键盘预热器
private struct KeyboardWarmer: View {
    @Binding var didWarmUp: Bool
    @FocusState private var isFocused: Bool
    
    var body: some View {
        TextField("", text: .constant(""))
            .focused($isFocused)
            .frame(width: 0, height: 0)
            .opacity(0)
            .onAppear {
                // 短暂激活键盘然后立即收起
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isFocused = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isFocused = false
                        didWarmUp = true
                    }
                }
            }
    }
}
