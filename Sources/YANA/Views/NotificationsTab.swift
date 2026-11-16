import SwiftUI

struct NotificationsTab: View {
    @EnvironmentObject var notifs: NotificationsService

    var body: some View {
        if !notifs.hasAccess {
            PermissionCard(icon: "bell.badge", title: L("Notifications from all apps"),
                           message: L("To show notifications from WhatsApp, Telegram, Mail, iPhone calls and more in the notch, grant Full Disk Access."),
                           button: L("Open Settings")) { Permissions.openPane("Privacy_AllFiles") }
        } else if notifs.items.isEmpty {
            Text(L("No notifications")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(notifs.items) { n in
                        HStack(alignment: .top, spacing: 10) {
                            if let i = n.icon { Image(nsImage: i).resizable().frame(width: 26, height: 26) }
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(n.title.isEmpty ? n.appName : n.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                    Spacer()
                                    Text(n.appName + " · " + n.date.shortRelative).font(.system(size: 9)).foregroundStyle(.secondary)
                                }
                                let text = [n.subtitle, n.body].filter { !$0.isEmpty }.joined(separator: " · ")
                                if !text.isEmpty {
                                    Text(text).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                        .contentShape(Rectangle())
                        .onTapGesture { notifs.open(n) }
                    }
                }
            }
        }
    }
}
