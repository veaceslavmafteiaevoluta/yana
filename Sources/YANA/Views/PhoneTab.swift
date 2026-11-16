import SwiftUI

struct PhoneTab: View {
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var calls: CallService
    @EnvironmentObject var contacts: ContactsService
    @StateObject private var number = Box("")
    @FocusState private var focused: Bool

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "+", "0", "⌫"]

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if !calls.hasAccess {
                    PermissionCard(icon: "phone.badge.waveform", title: L("Recent calls"),
                                   message: L("Grant Full Disk Access to see your iPhone calls."),
                                   button: L("Open Settings")) { Permissions.openPane("Privacy_AllFiles") }
                } else if calls.recents.isEmpty {
                    Text(L("No recent calls")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 2) {
                            ForEach(calls.recents) { c in
                                let name = contacts.displayName(for: c.address)
                                HStack(spacing: 8) {
                                    Image(systemName: c.outgoing ? "phone.arrow.up.right" : (c.missed ? "phone.down" : "phone.arrow.down.left"))
                                        .foregroundStyle(c.missed ? .red : .secondary)
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(name).font(.system(size: 12, weight: .semibold)).foregroundStyle(c.missed ? .red : .white).lineLimit(1)
                                        Text((c.isFaceTime ? "FaceTime" : L("Mobile")) + (c.duration > 0 ? " · \(formatTime(c.duration))" : ""))
                                            .font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(c.date.shortRelative).font(.system(size: 10)).foregroundStyle(.secondary)
                                    IconButton(systemName: "phone.fill", size: 11, tint: .green) { calls.call(c.address) }
                                }
                                .padding(.horizontal, 6).padding(.vertical, 3)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 6) {
                TextField(L("Number"), text: $number.value)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .medium)).monospacedDigit()
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .focused($focused)
                    .onSubmit { calls.call(number.value) }
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 6), count: 3), spacing: 5) {
                    ForEach(keys, id: \.self) { k in
                        Button {
                            if k == "⌫" { if !number.value.isEmpty { number.value.removeLast() } } else { number.value.append(k) }
                        } label: {
                            Text(k).font(.system(size: 14, weight: .medium))
                                .frame(width: 44, height: 24)
                                .background(Capsule().fill(Color.white.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 8) {
                    Button { calls.call(number.value) } label: {
                        Label(L("Call"), systemImage: "phone.fill").font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 5)
                            .background(Capsule().fill(Color.green))
                    }.buttonStyle(.plain)
                    Button { calls.call(number.value, faceTimeAudio: true) } label: {
                        Image(systemName: "video.fill").font(.system(size: 11))
                            .padding(.vertical, 6).padding(.horizontal, 10)
                            .background(Capsule().fill(Color.white.opacity(0.15)))
                    }.buttonStyle(.plain).help(L("FaceTime Audio"))
                }
            }
            .frame(width: 160)
        }
        .onChange(of: focused) { _, f in vm.keepOpen = f }
        .onDisappear { vm.keepOpen = false }
    }
}
