import SwiftUI

class ContentViewModel: ObservableObject, StreamControllerListener {
    @Published var statusMessage: String = "Idle"
    @Published var isRunning: Bool = false
    
    private let controller = StreamController()
    
    init() {
        controller.listener = self
    }
    
    func toggleServer() {
        if isRunning {
            controller.stopControl()
            isRunning = false
        } else {
            controller.startControl()
            isRunning = true
        }
    }
    
    // MARK: - StreamControllerListener
    func streamControllerDidUpdateStatus(_ controller: StreamController, status: String) {
        DispatchQueue.main.async {
            self.statusMessage = status
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("PhoneCam 4K60 HEVC Sender")
                .font(.title)
                .bold()
                .padding()
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Status:")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text(viewModel.statusMessage)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
            }
            .padding(.horizontal)
            
            Button(action: {
                viewModel.toggleServer()
            }) {
                Text(viewModel.isRunning ? "Stop Control Server" : "Start Control Server")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.isRunning ? Color.red : Color.blue)
                    .cornerRadius(10)
            }
            .padding()
            
            Spacer()
        }
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
