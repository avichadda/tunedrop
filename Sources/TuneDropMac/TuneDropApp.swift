import AppKit
import Foundation
import Security
import Sparkle
import SwiftUI

private enum AudioFormat: String, CaseIterable, Identifiable {
    case mp3
    case m4a
    case flac
    case opus

    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

private enum CredentialStore {
    static let clientIDKey = "spotifyClientID"
    static let onboardingKey = "hasCompletedCredentialOnboarding"
    private static let service = "com.avichadda.tunedrop"
    private static let secretAccount = "spotify-client-secret"

    static func loadSecret() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: secretAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func saveSecret(_ secret: String) throws {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: secretAccount,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(secret.utf8),
        ]
        let updateStatus = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw CredentialStoreError(status: updateStatus)
        }

        var item = identity
        item.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CredentialStoreError(status: addStatus)
        }
    }
}

private struct CredentialStoreError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return "Could not save the client secret: \(message)"
        }
        return "Could not save the client secret (Keychain error \(status))."
    }
}

@MainActor
private final class UpdateManager {
    let updaterController: SPUStandardUpdaterController
    private var checkedAtLaunch = false

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkAtLaunch() {
        guard !checkedAtLaunch else { return }
        checkedAtLaunch = true
        updaterController.updater.checkForUpdatesInBackground()
    }

    func checkForUpdates() {
        updaterController.updater.checkForUpdates()
    }
}

@MainActor
private final class DownloadController: ObservableObject {
    @Published var spotifyURL = ""
    @Published var outputPath = NSString(string: "~/Music/TuneDrop").expandingTildeInPath
    @Published var format: AudioFormat = .mp3
    @Published var bitrate = 320
    @Published var overwrite = false
    @Published var clientID: String
    @Published var clientSecret: String
    @Published private(set) var isRunning = false
    @Published private(set) var status = "Ready"
    @Published private(set) var currentTrack = 0
    @Published private(set) var totalTracks = 0
    @Published private(set) var failures = 0
    @Published private(set) var logLines: [String] = []
    @Published private(set) var executablePath: String?

    private var process: Process?
    private var outputBuffer = ""

    init() {
        let environment = ProcessInfo.processInfo.environment
        clientID = UserDefaults.standard.string(forKey: CredentialStore.clientIDKey)
            ?? environment["tunedrop_client_id"]
            ?? ""
        clientSecret = CredentialStore.loadSecret()
            ?? environment["tunedrop_client_secret"]
            ?? ""
        executablePath = Self.findTuneDrop()
    }

    var canStart: Bool {
        !isRunning
            && hasCredentials
            && spotifyURL.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(
                "https://open.spotify.com/"
            )
            && !outputPath.isEmpty
    }

    var hasCredentials: Bool {
        !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var progress: Double {
        guard totalTracks > 0 else { return 0 }
        return Double(currentTrack) / Double(totalTracks)
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Download Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: outputPath)
        if panel.runModal() == .OK, let url = panel.url {
            outputPath = url.path
        }
    }

    func revealOutputDirectory() {
        let url = URL(fileURLWithPath: outputPath)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    func start() {
        guard canStart else { return }
        guard let executablePath = Self.findTuneDrop() else {
            executablePath = nil
            status = "TuneDrop CLI not found"
            appendLog("Install TuneDrop with Homebrew, then reopen the app.")
            return
        }

        self.executablePath = executablePath
        currentTrack = 0
        totalTracks = 0
        failures = 0
        logLines = []
        outputBuffer = ""
        status = "Starting..."

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        var environment = ProcessInfo.processInfo.environment
        let standardPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        environment["PATH"] = (standardPaths + [environment["PATH"] ?? ""])
            .joined(separator: ":")
        if !clientID.isEmpty {
            environment["tunedrop_client_id"] = clientID
        }
        if !clientSecret.isEmpty {
            environment["tunedrop_client_secret"] = clientSecret
        }
        process.environment = environment

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in
                self?.consume(data)
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in
                self?.consume(data)
            }
        }
        process.terminationHandler = { [weak self] completedProcess in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                self?.finish(exitCode: completedProcess.terminationStatus)
            }
        }

        do {
            try process.run()
            self.process = process
            isRunning = true
            status = "Resolving Spotify metadata..."
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            status = "Could not start TuneDrop"
            appendLog(error.localizedDescription)
        }
    }

    func cancel() {
        guard let process, process.isRunning else { return }
        status = "Cancelling..."
        process.terminate()
    }

    func saveCredentials() -> String? {
        let trimmedID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty, !trimmedSecret.isEmpty else {
            return "Enter both the Spotify client ID and client secret."
        }

        do {
            try CredentialStore.saveSecret(trimmedSecret)
            UserDefaults.standard.set(trimmedID, forKey: CredentialStore.clientIDKey)
            clientID = trimmedID
            clientSecret = trimmedSecret
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var arguments: [String] {
        var values = [
            "--output", outputPath,
            "--format", format.rawValue,
            "--bitrate", String(bitrate),
        ]
        if overwrite {
            values.append("--overwrite")
        }
        values.append(spotifyURL.trimmingCharacters(in: .whitespacesAndNewlines))
        return values
    }

    private func consume(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        outputBuffer += text.replacingOccurrences(of: "\r", with: "\n")
        let parts = outputBuffer.components(separatedBy: "\n")
        outputBuffer = parts.last ?? ""
        for line in parts.dropLast() where !line.isEmpty {
            handle(line)
        }
    }

    private func handle(_ line: String) {
        appendLog(line)

        if line.hasPrefix("Resolved "),
           let count = line.split(separator: " ").dropFirst().first.flatMap({ Int($0) }) {
            totalTracks = count
            status = "Ready to download \(count) track\(count == 1 ? "" : "s")"
        }

        guard line.hasPrefix("["),
              let closeBracket = line.firstIndex(of: "]"),
              let slash = line[..<closeBracket].firstIndex(of: "/"),
              let current = Int(line[line.index(after: line.startIndex)..<slash]),
              let total = Int(line[line.index(after: slash)..<closeBracket])
        else {
            if line.contains("failed:") {
                failures += 1
            }
            return
        }

        currentTrack = current
        totalTracks = total
        let description = line[line.index(after: closeBracket)...]
            .trimmingCharacters(in: .whitespaces)
        status = description
    }

    private func finish(exitCode: Int32) {
        if !outputBuffer.isEmpty {
            handle(outputBuffer)
            outputBuffer = ""
        }
        process = nil
        isRunning = false

        if exitCode == 0 {
            currentTrack = totalTracks
            status = "Download complete"
        } else if status == "Cancelling..." {
            status = "Download cancelled"
        } else {
            status = failures > 0
                ? "Finished with \(failures) failed track\(failures == 1 ? "" : "s")"
                : "TuneDrop exited with code \(exitCode)"
        }
    }

    private func appendLog(_ line: String) {
        logLines.append(line)
        if logLines.count > 400 {
            logLines.removeFirst(logLines.count - 400)
        }
    }

    private static func findTuneDrop() -> String? {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let workingDirectory = FileManager.default.currentDirectoryPath
        let candidates = [
            environment["TUNEDROP_EXECUTABLE"],
            "\(workingDirectory)/.venv/bin/tunedrop",
            "/opt/homebrew/bin/tunedrop",
            "/usr/local/bin/tunedrop",
            "\(home)/.local/bin/tunedrop",
        ].compactMap { $0 }

        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }
}

private struct RootView: View {
    @ObservedObject var controller: DownloadController
    @AppStorage(CredentialStore.onboardingKey) private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            ContentView(controller: controller)
        } else {
            CredentialView(controller: controller, isOnboarding: true) {
                hasCompletedOnboarding = true
            }
        }
    }
}

private struct CredentialView: View {
    @ObservedObject var controller: DownloadController
    let isOnboarding: Bool
    let onSaved: () -> Void
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: "key.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(isOnboarding ? "Connect TuneDrop to Spotify" : "Spotify Credentials")
                        .font(.largeTitle.bold())
                    Text("Spotify is used only to resolve track and playlist metadata.")
                        .foregroundStyle(.secondary)
                }
            }

            if isOnboarding {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Open the Spotify Developer Dashboard and create an app.", systemImage: "1.circle.fill")
                        Label("Enable the Web API for the app.", systemImage: "2.circle.fill")
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Add this redirect URI:", systemImage: "3.circle.fill")
                            Text("http://127.0.0.1:8888/callback")
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(.leading, 28)
                        }
                        Label("Copy the app's client ID and client secret below.", systemImage: "4.circle.fill")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                Link(
                    "Open Spotify Developer Dashboard",
                    destination: URL(string: "https://developer.spotify.com/dashboard")!
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                TextField("Client ID", text: $controller.clientID)
                    .textFieldStyle(.roundedBorder)
                SecureField("Client secret", text: $controller.clientSecret)
                    .textFieldStyle(.roundedBorder)
                Label(
                    "The client ID is saved in app preferences. The secret is encrypted in macOS Keychain.",
                    systemImage: "lock.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            Spacer()

            HStack {
                if !isOnboarding {
                    Button("Cancel", action: onSaved)
                }
                Spacer()
                Button(isOnboarding ? "Save and Continue" : "Save") {
                    if let error = controller.saveCredentials() {
                        errorMessage = error
                    } else {
                        errorMessage = nil
                        onSaved()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!controller.hasCredentials)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(minWidth: 620, minHeight: isOnboarding ? 560 : 300)
    }
}

private struct ContentView: View {
    @ObservedObject var controller: DownloadController
    @State private var showCredentials = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            form
            progress
            log
            actions
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 620)
        .sheet(isPresented: $showCredentials) {
            CredentialView(controller: controller, isOnboarding: false) {
                showCredentials = false
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text("TuneDrop")
                    .font(.largeTitle.bold())
                Text("Archive authorized Spotify tracks with native macOS controls.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var form: some View {
        Form {
            TextField("Spotify track, album, or playlist URL", text: $controller.spotifyURL)
                .textFieldStyle(.roundedBorder)

            HStack {
                TextField("Download folder", text: $controller.outputPath)
                    .textFieldStyle(.roundedBorder)
                Button("Choose...", action: controller.chooseOutputDirectory)
            }

            HStack {
                Picker("Format", selection: $controller.format) {
                    ForEach(AudioFormat.allCases) { format in
                        Text(format.label).tag(format)
                    }
                }
                .frame(width: 180)

                Picker("Bitrate", selection: $controller.bitrate) {
                    ForEach([128, 192, 256, 320], id: \.self) { bitrate in
                        Text("\(bitrate) kbps").tag(bitrate)
                    }
                }
                .frame(width: 190)

                Toggle("Replace existing files", isOn: $controller.overwrite)
            }

        }
        .formStyle(.grouped)
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(controller.status)
                    .lineLimit(1)
                Spacer()
                if controller.totalTracks > 0 {
                    Text("\(controller.currentTrack) / \(controller.totalTracks)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            ProgressView(value: controller.progress)
                .opacity(controller.totalTracks > 0 ? 1 : 0.35)
        }
    }

    private var log: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 3) {
                ForEach(Array(controller.logLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor))
        }
        .frame(minHeight: 180)
    }

    private var actions: some View {
        HStack {
            if let path = controller.executablePath {
                Text("CLI: \(path)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("TuneDrop CLI not found. Install it with Homebrew.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Spacer()
            Button("Credentials...") {
                showCredentials = true
            }
            .disabled(controller.isRunning)
            Button("Open Folder", action: controller.revealOutputDirectory)
            if controller.isRunning {
                Button("Cancel", role: .destructive, action: controller.cancel)
            } else {
                Button("Download", action: controller.start)
                    .buttonStyle(.borderedProminent)
                    .disabled(!controller.canStart)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

@main
private struct TuneDropApp: App {
    @StateObject private var controller = DownloadController()
    private let updateManager = UpdateManager()

    var body: some Scene {
        WindowGroup {
            RootView(controller: controller)
                .onAppear {
                    updateManager.checkAtLaunch()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 780, height: 680)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    updateManager.checkForUpdates()
                }
            }
        }
    }
}
