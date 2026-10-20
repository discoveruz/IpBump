import IpBumpCore
import SwiftUI

/// The Settings window, laid out like System Settings' TCP/IP page.
struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel
    let height: CGFloat
    @FocusState private var focused: SettingsForm.Field?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Network service", selection: $model.form.service) {
                        ForEach(model.services, id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: model.form.service) { model.serviceChanged() }
                    if !model.status.isEmpty { hint(model.status) }
                } header: {
                    Text("Edit IP settings").font(.title2.weight(.semibold)).padding(.bottom, 4)
                }

                Section("IPv4") {
                    field("IP address", $model.form.ip, .ip)
                    field("Subnet mask", $model.form.mask, .mask)
                    field("Router", $model.form.router, .router)
                    field("Preferred DNS", $model.form.dns1, .dns1)
                    field("Alternate DNS", $model.form.dns2, .dns2)
                    Button("Use the service's current values") { model.useCurrentValues() }
                }

                Section {
                    field("From", $model.form.rangeStart, .rangeStart, placeholder: model.form.rangePlaceholders.from)
                    field("To", $model.form.rangeEnd, .rangeEnd, placeholder: model.form.rangePlaceholders.to)
                } header: {
                    Text("Free address search")
                } footer: {
                    hint("Click Change IP now in the IpBump menu to move to an address nobody is using. "
                        + "Limit the search here, or leave both empty to use the whole network.")
                }

                Section {
                    Toggle("Let AI agents (Claude, Gemini) change the IP", isOn: $model.form.allowAgents)
                    ForEach(model.agents) { row in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.agent.name)
                                Text(row.connected ? "Connected" : "Not connected")
                                    .font(.caption).foregroundStyle(row.connected ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                            }
                            Spacer()
                            Button(row.connected ? "Disconnect" : "Connect") { model.toggle(row) }
                                .accessibilityLabel("\(row.connected ? "Disconnect" : "Connect") \(row.agent.name)")
                        }
                    }
                    if let agentHint = model.agentHint { hint(agentHint) }
                } header: {
                    Text("AI agents")
                } footer: {
                    hint("A connected agent changes the IP when you ask it to. "
                        + "Claude Code also does it by itself when its connection is refused.")
                }

                Section {
                    Toggle("Show the full address in the menu bar", isOn: $model.form.showFullAddress)
                } header: {
                    Text("Menu bar")
                } footer: {
                    hint("Off shows only its last number. Click it for the menu; Option-click it for a new address.")
                }

                Section("Notifications") {
                    Toggle("Show a notification after each change", isOn: $model.form.showNotifications)
                }

                Section {
                    HStack {
                        hint("IpBump \(Version.current)  ·  settings are saved for your Mac account only")
                        Spacer()
                        if Uninstaller.available { Button("Uninstall IpBump…") { Uninstaller.run() } }
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(model.busy)

            VStack(spacing: 12) {
                if let error = model.error {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                        Text(error).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityElement(children: .combine)
                }
                HStack {
                    Spacer()
                    Button("Cancel") { model.close() }.keyboardShortcut(.cancelAction)
                    Button(model.busy ? "Applying…" : "Save") { Task { await model.save() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.busy)
                }
            }
            .padding(20)
        }
        .frame(width: 480, height: height)
        .onChange(of: model.problemField) { focused = model.problemField }
    }

    func field(_ label: String, _ text: Binding<String>, _ which: SettingsForm.Field, placeholder: String = "") -> some View {
        TextField(label, text: text, prompt: Text(placeholder))
            .focused($focused, equals: which)
    }

    func hint(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
