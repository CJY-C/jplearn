import SwiftUI
import LearningCore

@main struct JPLearnApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: AppModel?
    @State private var startupError: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if let model = model {
                    MainView().environmentObject(model)
                } else if let message = startupError {
                    VStack(spacing: 20) {
                        Image(systemName: "externaldrive.badge.exclamationmark").font(.largeTitle)
                        Text("暂时无法打开学习资料").font(.title2)
                        Text(message).font(.callout).foregroundColor(.secondary)
                        Text("本机文件会保留，请重试或检查备份。").font(.footnote)
                        Button("重试", action: load)
                    }.padding(28)
                } else { ProgressView("正在准备课程…") }
            }
            .task { if model == nil { load() } }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    Task { await model?.sync() }
                } else { model?.speech.stop() }
            }
        }
    }

    @MainActor private func load() {
        do {
            let loaded = try AppModel()
            model = loaded
            startupError = nil
            Task { await loaded.sync() }
        }
        catch { startupError = error.localizedDescription }
    }
}

struct MainView: View {
    @EnvironmentObject private var model: AppModel
    @State private var settings = false
    var body: some View {
        TabView {
            NavigationView {
                TodayView().toolbar { settingsButton }
            }.navigationViewStyle(.stack)
                .tabItem { Label("今天", systemImage: "sun.max") }
            NavigationView {
                CourseView().toolbar { settingsButton }
            }.navigationViewStyle(.stack)
                .tabItem { Label("课程", systemImage: "square.stack") }
            NavigationView {
                LibraryView().toolbar { settingsButton }
            }.navigationViewStyle(.stack)
                .tabItem { Label("资料", systemImage: "books.vertical") }
        }
        .sheet(isPresented: $settings) { NavigationView { SettingsView() }.navigationViewStyle(.stack) }
        .alert("操作未完成", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("好", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
    private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("设置")
        }
    }
}
