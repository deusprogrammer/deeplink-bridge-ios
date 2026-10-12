
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var path = ""
    @State private var status = "Ready"
    @State private var launchCount = 0
    @State private var returnCount = 0

    private let baseURL = "usaadeeplink://mobileapps.usaa.com"

    private var resolvedURL: String {
        let input = path.trimmingCharacters(in: .whitespacesAndNewlines)

        if input.lowercased().hasPrefix("usaadeeplink://") {
            return input
        }

        if input.isEmpty {
            return baseURL + "/"
        }

        return baseURL + "/" + input.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("DeepLink Bridge")
                .font(.largeTitle.bold())

            TextField("Enter path", text: $path)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text("Resolved URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(resolvedURL)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                openDeepLink()
            } label: {
                Label("Launch USAA", systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Status: \(status)")
                Text("Launch attempts: \(launchCount)")
                Text("Returned to app: \(returnCount)")
                Text("Scene phase: \(String(describing: scenePhase))")
            }
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .padding()
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active && oldPhase != .active {
                returnCount += 1
                status = "Bridge active"
            }
        }
    }

    private func openDeepLink() {
        guard let url = URL(string: resolvedURL),
              url.scheme?.lowercased() == "usaadeeplink" else {
            status = "Invalid deep link"
            return
        }

        launchCount += 1
        status = "Opening USAA..."

        UIApplication.shared.open(url, options: [:]) { success in
            DispatchQueue.main.async {
                status = success
                    ? "iOS accepted deep link"
                    : "Failed to open deep link"
            }
        }
    }
}

#Preview {
    ContentView()
}
