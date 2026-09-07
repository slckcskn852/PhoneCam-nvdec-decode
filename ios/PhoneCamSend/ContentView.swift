import SwiftUI
import AVFoundation
import Network

class ContentViewModel: ObservableObject, StreamControllerListener {
    @Published var statusMessage = "Open PhoneCam Receiver on your computer."
    @Published var isRunning = false
    private let controller = StreamController()
    private var requestGeneration = 0
    init() { controller.listener = self }

    private func withCamera(_ action: @escaping () -> Void) {
        requestGeneration += 1
        let token = requestGeneration
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self, self.requestGeneration == token else { return }
                if granted { action(); self.isRunning = true }
                else { self.statusMessage = "Enable camera permission in Settings to stream." }
            }
        }
    }
    func connect(to endpoint: NWEndpoint) {
        withCamera { [weak self] in self?.controller.connect(to: endpoint) }
    }
    func connect(code: String) {
        guard let address = ReceiverAddress.parse(code), let port = NWEndpoint.Port(rawValue: address.port) else {
            statusMessage = "Check the PC code shown on your computer, or enter its IP address (optionally followed by :port)."
            return
        }
        connect(to: .hostPort(host: .init(address.host), port: port))
    }
    func toggleServer() {
        if isRunning { stop() }
        else { withCamera { [weak self] in self?.controller.startControl() } }
    }
    func stop() {
        requestGeneration += 1
        controller.stopControl()
        isRunning = false
        statusMessage = "Disconnected. Your camera is off."
    }
    func streamControllerDidUpdateStatus(_ controller: StreamController, status: String) {
        DispatchQueue.main.async { self.statusMessage = status }
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = ContentViewModel()
    @StateObject private var browser = ReceiverBrowser()
    @State private var code = ""
    @State private var searching = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("PhoneCam").font(.largeTitle).bold()
                Text("Open PhoneCam Receiver on your computer, then find it below.")
                Button("Find my computer") { searching = true; browser.start() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                if searching {
                    Text(browser.message).font(.footnote).foregroundColor(.secondary)
                    ForEach(browser.computers) { computer in
                        Button { viewModel.connect(to: computer.endpoint); browser.stop(); searching = false } label: {
                            Label(computer.name, systemImage: "desktopcomputer").frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.bordered)
                    }
                }
                TextField("PC code or computer IP address", text: $code)
                    .textFieldStyle(.roundedBorder).textInputAutocapitalization(.characters)
                    .autocorrectionDisabled().submitLabel(.go)
                    .onSubmit { connectWithCode() }
                Button("Connect with code") { connectWithCode() }.buttonStyle(.bordered)
                Text(viewModel.statusMessage)
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground)).cornerRadius(10)
                if viewModel.isRunning {
                    Button("Stop connection", role: .destructive) { viewModel.stop() }.buttonStyle(.bordered)
                }
                Text("Selecting a computer starts your camera. Streaming stops when you leave this app. Use your main home network; guest Wi-Fi may block connections.")
                    .font(.footnote).foregroundColor(.secondary)
                DisclosureGroup("Advanced connection options") {
                    VStack(alignment: .leading, spacing: 12) {
                        Button(viewModel.isRunning ? "Stop receiver access" : "Allow receiver access") { viewModel.toggleServer() }
                        Text("Allows a receiver on this network to start your camera using the phone’s IP address. For manual TCP or UDP connections.")
                            .font(.footnote).foregroundColor(.secondary)
                    }.padding(.top)
                }
            }.padding(24)
        }
        .onChange(of: viewModel.isRunning) { running in UIApplication.shared.isIdleTimerDisabled = running }
        .onChange(of: scenePhase) { phase in
            if phase == .background { browser.stop(); searching = false; viewModel.stop() }
        }
    }
    private func connectWithCode() { browser.stop(); searching = false; viewModel.connect(code: code) }
}
