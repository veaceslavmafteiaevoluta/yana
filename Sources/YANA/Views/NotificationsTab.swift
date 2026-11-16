import SwiftUI

struct NotificationsTab: View {
    @EnvironmentObject var notifs: NotificationsService
    /// Apps whose stack is expanded.
    @StateObject private var expanded = Box<Set<String>>([])

    var body: some View {
        if !notifs.hasAccess {
            PermissionCard(icon: "bell.badge", title: L("Notifications from all apps"),
                           message: L("To show notifications from WhatsApp, Telegram, Mail, iPhone calls and more in the notch, grant Full Disk Access."),
                           button: L("Open Settings")) { Permissions.openPane("Privacy_AllFiles") }
        } else if notifs.visible.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "bell.slash").font(.system(size: 22)).foregroundStyle(.secondary)
                Text(L("No notifications")).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 6) {
                HStack {
                    SectionTitle(text: L("%ld notifications", notifs.visible.count))
                    Spacer()
                    Button(L("Clear all")) { withAnimation(.easeInOut(duration: 0.2)) { notifs.clearAll() } }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(notifs.groups, id: \.bundleID) { g in
                            group(g.bundleID, g.items)
                        }
                    }
                    .padding(.top, 4).padding(.leading, 4)   // room for the dismiss badge
                }
            }
        }
    }

    @ViewBuilder private func group(_ bundleID: String, _ items: [AppNotification]) -> some View {
        let open = expanded.value.contains(bundleID)
        if items.count > 1 && open {
            HStack(spacing: 6) {
                Text(items[0].appName).font(.system(size: 11, weight: .semibold))
                Spacer()
                Button(L("Show less")) { toggle(bundleID) }
                    .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                IconButton(systemName: "xmark", size: 8) {
                    withAnimation(.easeInOut(duration: 0.2)) { notifs.dismissAll(from: bundleID) }
                }
                .help(L("Clear notifications from this app"))
            }
            .padding(.horizontal, 4)
            ForEach(items) { NotificationRow(n: $0, stackCount: 0) }
        } else {
            NotificationRow(n: items[0], stackCount: items.count - 1) { toggle(bundleID) }
                .padding(.bottom, items.count > 1 ? 5 : 0)
        }
    }

    private func toggle(_ bundleID: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expanded.value.contains(bundleID) { expanded.value.remove(bundleID) } else { expanded.value.insert(bundleID) }
        }
    }
}

/// One notification card. With `stackCount > 0` it's the top of a collapsed stack of the same app.
private struct NotificationRow: View {
    @EnvironmentObject var notifs: NotificationsService
    let n: AppNotification
    var stackCount: Int
    var onExpand: (() -> Void)? = nil
    @StateObject private var hover = Box(false)

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let i = n.icon { Image(nsImage: i).resizable().frame(width: 26, height: 26) }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(n.title.isEmpty ? n.appName : n.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    if notifs.isMuted(n.bundleID) {
                        Image(systemName: "bell.slash.fill").font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(n.appName + " · " + n.date.shortRelative).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
                let text = [n.subtitle, n.body].filter { !$0.isEmpty }.joined(separator: " · ")
                if !text.isEmpty {
                    Text(text).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
                if stackCount > 0 {
                    Button { onExpand?() } label: {
                        Text(L("+%ld more", stackCount)).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 1)
                }
            }
        }
        .padding(8)
        .background(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                // Cards peeking out below = collapsed stack.
                if stackCount > 0 {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.04))
                        .padding(.horizontal, 10).offset(y: 5)
                }
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(hover.value ? 0.1 : 0.06))
            }
        }
        .overlay(alignment: .topLeading) {
            if hover.value {
                Button { withAnimation(.easeInOut(duration: 0.2)) { notifs.dismiss(n) } } label: {
                    Image(systemName: "xmark").font(.system(size: 7, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color(white: 0.3)))
                }
                .buttonStyle(.plain)
                .offset(x: -4, y: -4)
                .help(L("Dismiss"))
            }
        }
        .contentShape(Rectangle())
        .onHover { hover.value = $0 }
        .onTapGesture { notifs.open(n) }
        .contextMenu {
            Button(L("Open %@", n.appName)) { notifs.open(n) }
            Button(L("Copy text")) { notifs.copy(n) }
            Divider()
            Button(L("Dismiss")) { notifs.dismiss(n) }
            Button(L("Clear notifications from this app")) { notifs.dismissAll(from: n.bundleID) }
            Divider()
            Button(notifs.isMuted(n.bundleID) ? L("Show pop-ups from %@", n.appName) : L("Mute pop-ups from %@", n.appName)) {
                notifs.toggleMute(n.bundleID)
            }
        }
    }
}
