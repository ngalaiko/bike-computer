import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Group {
            if appModel.isDevicePaired {
                MainView()
            } else {
                SetupView()
            }
        }
        .task {
            await appModel.startReceiving()
        }
    }
}
