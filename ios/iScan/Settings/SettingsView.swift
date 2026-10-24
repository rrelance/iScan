import SwiftUI

struct SettingsView: View {
    @AppStorage("serverURL") private var serverURL = ""
    @AppStorage("reuseRoomSession") private var reuseRoomSession = false
    @StateObject private var discovery = ServerDiscovery()
    @Environment(\.dismiss) private var dismiss
    @State private var testResult: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if discovery.servers.isEmpty {
                        Label("Looking for the iScan server on this Wi-Fi…", systemImage: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(discovery.servers) { server in
                        Button {
                            serverURL = server.baseURL.absoluteString
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(server.name)
                                    Text(server.baseURL.absoluteString).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if serverURL == server.baseURL.absoluteString { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } header: {
                    Text("Discovered")
                } footer: {
                    Text("Run `npm run server` on your PC. It prints its address if it doesn't show up here.")
                }

                Section("PC address") {
                    TextField("http://192.168.1.20:8787", text: $serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Test connection") { Task { await test() } }
                        .disabled(URL(string: serverURL) == nil || serverURL.isEmpty)
                    if let testResult { Text(testResult).font(.callout) }
                }

                Section {
                    Toggle("Reuse RoomPlan session", isOn: $reuseRoomSession)
                } header: {
                    Text("Experimental")
                } footer: {
                    Text("Continues RoomPlan's AR session for the detail pass, which may keep both passes in one coordinate frame on iOS 16.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { discovery.start() }
            .onDisappear { discovery.stop() }
        }
    }

    private func test() async {
        guard let base = URL(string: serverURL) else { return }
        var request = URLRequest(url: base.appendingPathComponent("api/health"))
        request.timeoutInterval = 5
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let ok = (response as? HTTPURLResponse)?.statusCode == 200 && String(decoding: data, as: UTF8.self).contains("iscan")
            testResult = ok ? "Connected to iScan server." : "Something answered, but it isn't the iScan server."
        } catch {
            testResult = "Can't reach it. Check the address, that the server is running, and Windows Firewall."
        }
    }
}
