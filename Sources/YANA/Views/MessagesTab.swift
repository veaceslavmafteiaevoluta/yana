import SwiftUI

struct MessagesTab: View {
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var msgs: MessagesService
    @EnvironmentObject var contacts: ContactsService
    @StateObject private var draft = Box("")
    @FocusState private var focused: Bool

    var body: some View {
        if !msgs.hasAccess {
            PermissionCard(icon: "lock.shield", title: L("Full Disk Access required"),
                           message: L("To read SMS and iMessage, add YANA in System Settings › Privacy & Security › Full Disk Access, then restart the app."),
                           button: L("Open Settings")) { Permissions.openPane("Privacy_AllFiles") }
        } else {
            HStack(spacing: 12) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(msgs.conversations) { c in
                            HStack(spacing: 8) {
                                Avatar(name: c.title, size: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack {
                                        Text(c.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                        Spacer(minLength: 2)
                                        Text(c.last.date.shortRelative).font(.system(size: 9)).foregroundStyle(.secondary)
                                    }
                                    Text((c.last.isFromMe ? L("You: ") : "") + c.last.text)
                                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                if c.unread { Circle().fill(.blue).frame(width: 6, height: 6) }
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(msgs.selectedGuid == c.guid ? 0.12 : 0)))
                            .contentShape(Rectangle())
                            .onTapGesture { msgs.selectedGuid = c.guid }
                        }
                    }
                }
                .frame(width: 215)

                VStack(spacing: 6) {
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 4) {
                                ForEach(msgs.thread) { m in
                                    HStack {
                                        if m.isFromMe { Spacer(minLength: 40) }
                                        Text(m.text)
                                            .font(.system(size: 12))
                                            .padding(.horizontal, 10).padding(.vertical, 6)
                                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .fill(m.isFromMe ? (m.service == "iMessage" ? Color.blue : Color.green) : Color.white.opacity(0.14)))
                                            .textSelection(.enabled)
                                        if !m.isFromMe { Spacer(minLength: 40) }
                                    }
                                    .id(m.id)
                                }
                            }
                        }
                        .onAppear { proxy.scrollTo(msgs.thread.last?.id, anchor: .bottom) }
                        .onChange(of: msgs.thread) { _, t in proxy.scrollTo(t.last?.id, anchor: .bottom) }
                    }
                    HStack(spacing: 6) {
                        TextField(L("Reply…"), text: $draft.value)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(Color.white.opacity(0.1)))
                            .focused($focused)
                            .onSubmit(send)
                        IconButton(systemName: "arrow.up.circle.fill", size: 18, tint: .blue, action: send)
                        IconButton(systemName: "arrow.up.forward.app", size: 13, tint: .secondary) { msgs.openInMessages() }
                    }
                }
            }
            .onAppear {
                if let g = vm.pendingChatGuid { msgs.selectedGuid = g; vm.pendingChatGuid = nil }
            }
            .onChange(of: focused) { _, f in vm.keepOpen = f }
            .onDisappear { vm.keepOpen = false }
        }
    }

    private func send() {
        guard let g = msgs.selectedGuid else { return }
        msgs.send(draft.value, to: g)
        draft.value = ""
    }
}
