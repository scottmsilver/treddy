import SwiftUI

struct HrmSection: View {
    @Environment(TreadmillStore.self) private var store

    var body: some View {
        Section {
            HStack {
                Text("Status")
                Spacer()
                Text(store.status.hrmConnected ? "Connected" : "Disconnected")
                    .foregroundStyle(store.status.hrmConnected ? .green : .secondary)
            }

            if !store.status.hrmDevice.isEmpty {
                HStack {
                    Text("Selected")
                    Spacer()
                    Text(store.status.hrmDevice)
                        .foregroundStyle(.secondary)
                }
            }

            Button("Scan for Devices") {
                Task { await store.scanHrmDevices() }
            }

            ForEach(store.hrmDevices) { device in
                Button {
                    Task { await store.selectHrmDevice(device) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name.isEmpty ? device.address : device.name)
                            Text(device.address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text("\(device.rssi) dBm")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if store.status.hrmConnected || !store.status.hrmDevice.isEmpty {
                Button("Forget Device", role: .destructive) {
                    Task { await store.forgetHrmDevice() }
                }
            }
        } header: {
            Text("Heart Rate Monitor")
                .accessibilityIdentifier("hrm-section-title")
        }
    }
}
