
import SwiftUI
import UIKit
import Darwin

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("testServerURL") private var testServerURL = ""
    @State private var path = ""
    @State private var status = "Ready"
    @State private var currentIPAddress = "Detecting..."
    @State private var launchCount = 0
    @State private var returnCount = 0
    @State private var isTesting = false
    @State private var activeTestTask: Task<Void, Never>?
    @State private var lastProcessedURI: String?
    @State private var nextRequestDebug = "-"
    @State private var continueRequestDebug = "-"
    @State private var isAwaitingReturn = false
    @State private var hasLeftForeground = false
    @State private var lastTriggerDate = Date.distantPast

    private let baseURL = "usaadeeplink://mobileapps.usaa.com"

    private var resolvedURL: String {
        resolveURL(for: path)
    }

    private func resolveURL(for input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.lowercased().hasPrefix("usaadeeplink://") {
            return trimmed
        }

        if trimmed.isEmpty {
            return baseURL + "/"
        }

        return baseURL + "/" + trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("DeepLink Bridge")
                    .font(.largeTitle.bold())

                TextField("Enter path", text: $path)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isTesting)

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
                .disabled(isTesting)

                Divider()

                TextField("Enter test server URL", text: $testServerURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isTesting)

                if isTesting {
                    Button(role: .destructive) {
                        stopTest(reason: "Test stopped by user")
                    } label: {
                        Label("Stop Test", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button {
                        startTest()
                    } label: {
                        Text("Begin Test")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Status: \(status)")
                    Text("Public IP: \(currentIPAddress)")
                    Text("Launch attempts: \(launchCount)")
                    Text("Returned to app: \(returnCount)")
                    Text("Scene phase: \(String(describing: scenePhase))")

                    Divider()

                    Text("HTTP Debug")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("/next:")
                            .font(.caption.bold())
                        Text(nextRequestDebug)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("/continue:")
                            .font(.caption.bold())
                        Text(continueRequestDebug)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
            }
            .padding()
        }
        .onAppear {
            refreshIPAddress()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase != .active {
                if isTesting && isAwaitingReturn {
                    hasLeftForeground = true
                }
            } else if newPhase == .active && oldPhase != .active {
                refreshIPAddress()
                returnCount += 1
                if isTesting {
                    let now = Date()
                    if isAwaitingReturn && hasLeftForeground && now.timeIntervalSince(lastTriggerDate) > 0.8 {
                        isAwaitingReturn = false
                        hasLeftForeground = false
                        lastTriggerDate = now
                        fetchAndLaunchNext()
                    }
                } else {
                    status = "Bridge active"
                }
            }
        }
    }

    private var parsedServerURL: URL? {
        let trimmed = testServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let fullURLString = trimmed.contains("://") ? trimmed : "http://" + trimmed
        return URL(string: fullURLString)
    }

    private func openDeepLink(urlString: String? = nil) {
        let target = urlString ?? resolvedURL
        guard let url = URL(string: target),
              url.scheme?.lowercased() == "usaadeeplink" else {
            stopTest(reason: "Invalid deep link: \(target)")
            return
        }

        launchCount += 1
        status = "Opening USAA..."

        if isTesting {
            isAwaitingReturn = true
            hasLeftForeground = false
            lastTriggerDate = Date()
        }

        UIApplication.shared.open(url, options: [:]) { success in
            DispatchQueue.main.async {
                if success {
                    status = "iOS accepted deep link (waiting to return)"
                } else {
                    stopTest(reason: "Failed to open deep link")
                }
            }
        }
    }

    private func startTest() {
        guard parsedServerURL != nil else {
            status = "Enter test server URL"
            return
        }

        lastProcessedURI = nil
        isAwaitingReturn = false
        hasLeftForeground = false
        lastTriggerDate = Date()
        isTesting = true
        fetchAndLaunchNext()
    }

    private func fetchAndLaunchNext() {
        guard isTesting else { return }
        guard activeTestTask == nil else { return }

        guard let serverURL = parsedServerURL else {
            stopTest(reason: "Invalid test server URL")
            return
        }

        let nextEndpointURL = serverURL.appendingPathComponent("next")
        let continueEndpointURL = serverURL.appendingPathComponent("continue")
        let quitEndpointURL = serverURL.appendingPathComponent("quit")
        status = "Calling test server (/next)..."

        activeTestTask = Task { @MainActor in
            defer {
                activeTestTask = nil
            }

            do {
                var request = URLRequest(url: nextEndpointURL)
                request.httpMethod = "GET"
                request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

                nextRequestDebug = "GET \(nextEndpointURL.absoluteString) -> In flight..."

                let (data, response) = try await URLSession.shared.data(for: request)

                try Task.checkCancellation()

                guard let httpResponse = response as? HTTPURLResponse else {
                    nextRequestDebug = "GET \(nextEndpointURL.absoluteString) -> Non-HTTP response"
                    stopTest(reason: "Invalid server response")
                    return
                }

                nextRequestDebug = "GET \(nextEndpointURL.absoluteString) -> HTTP \(httpResponse.statusCode)"

                // Check for 410 Gone: call /quit to kill the test server, then stop
                if httpResponse.statusCode == 410 {
                    status = "Received 410 (Gone). Calling /quit to stop server..."
                    var quitRequest = URLRequest(url: quitEndpointURL)
                    quitRequest.httpMethod = "POST"

                    continueRequestDebug = "POST \(quitEndpointURL.absoluteString) -> In flight..."

                    do {
                        let (_, quitResponse) = try await URLSession.shared.data(for: quitRequest)
                        if let quitHTTPResponse = quitResponse as? HTTPURLResponse {
                            continueRequestDebug = "POST \(quitEndpointURL.absoluteString) -> HTTP \(quitHTTPResponse.statusCode)"
                        } else {
                            continueRequestDebug = "POST \(quitEndpointURL.absoluteString) -> Non-HTTP response"
                        }
                    } catch {
                        // The server might terminate immediately when receiving /quit, closing the connection
                        continueRequestDebug = "POST \(quitEndpointURL.absoluteString) -> Sent (\(error.localizedDescription))"
                    }

                    stopTest(reason: "All tests completed (server stopped via /quit)")
                    return
                }

                // Stop if non-200 status code
                guard httpResponse.statusCode == 200 else {
                    stopTest(reason: "Server returned non-200 status (HTTP \(httpResponse.statusCode)). Stopped test.")
                    return
                }

                guard var uriString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !uriString.isEmpty else {
                    stopTest(reason: "All tests completed (empty response)")
                    return
                }

                // Strip surrounding double quotes if present (e.g. JSON string response)
                if uriString.hasPrefix("\"") && uriString.hasSuffix("\"") && uriString.count >= 2 {
                    uriString = String(uriString.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                }

                if uriString.isEmpty || uriString.lowercased() == "done" || uriString.lowercased() == "complete" {
                    stopTest(reason: "All tests completed")
                    return
                }

                // Stop if same URL as previously processed
                if let last = lastProcessedURI, last == uriString {
                    stopTest(reason: "Duplicate URI received (\(uriString)). Stopped test.")
                    return
                }

                lastProcessedURI = uriString

                // POST to /continue
                status = "Notifying test server (/continue)..."
                var continueRequest = URLRequest(url: continueEndpointURL)
                continueRequest.httpMethod = "POST"
                continueRequest.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
                continueRequest.httpBody = uriString.data(using: .utf8)

                continueRequestDebug = "POST \(continueEndpointURL.absoluteString) -> In flight..."

                let (_, continueResponse) = try await URLSession.shared.data(for: continueRequest)
                try Task.checkCancellation()

                guard let continueHTTPResponse = continueResponse as? HTTPURLResponse else {
                    continueRequestDebug = "POST \(continueEndpointURL.absoluteString) -> Non-HTTP response"
                    stopTest(reason: "Invalid /continue response")
                    return
                }

                continueRequestDebug = "POST \(continueEndpointURL.absoluteString) -> HTTP \(continueHTTPResponse.statusCode)"

                if !(200...299).contains(continueHTTPResponse.statusCode) {
                    stopTest(reason: "Error from /continue (HTTP \(continueHTTPResponse.statusCode)). Stopped test.")
                    return
                }

                let deepLink = resolveURL(for: uriString)
                openDeepLink(urlString: deepLink)
            } catch is CancellationError {
                stopTest(reason: "Test stopped")
            } catch {
                if activeTestTask?.isCancelled == false {
                    if nextRequestDebug.contains("In flight...") {
                        nextRequestDebug = "GET \(nextEndpointURL.absoluteString) -> Error: \(error.localizedDescription)"
                    } else if continueRequestDebug.contains("In flight...") {
                        continueRequestDebug = "POST \(continueEndpointURL.absoluteString) -> Error: \(error.localizedDescription)"
                    }
                }
                stopTest(reason: "Request failed: \(error.localizedDescription)")
            }
        }
    }

    private func stopTest(reason: String? = nil) {
        activeTestTask?.cancel()
        activeTestTask = nil
        isTesting = false
        isAwaitingReturn = false
        hasLeftForeground = false
        if let reason = reason {
            status = reason
        }
    }

    private func refreshIPAddress() {
        Task {
            let ip = await fetchPublicIPAddress()
            await MainActor.run {
                currentIPAddress = ip
            }
        }
    }

    private func fetchPublicIPAddress() async -> String {
        let providers = [
            "https://api.ipify.org",
            "https://icanhazip.com",
            "https://ifconfig.me/ip"
        ]

        for urlString in providers {
            guard let url = URL(string: urlString) else { continue }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 4
                request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                   let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !ip.isEmpty {
                    return ip
                }
            } catch {
                continue
            }
        }

        return "Unavailable"
    }
}

#Preview {
    ContentView()
}
