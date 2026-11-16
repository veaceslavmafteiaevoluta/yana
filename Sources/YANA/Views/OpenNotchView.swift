import SwiftUI
import UniformTypeIdentifiers

struct OpenNotchView: View {
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var battery: BatteryService
    @EnvironmentObject var shelf: ShelfStore
    @StateObject private var dropTargeted = Box(false)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(NotchTab.allCases) { t in
                    Button { withAnimation(.easeInOut(duration: 0.2)) { vm.tab = t } } label: {
                        Image(systemName: t.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(vm.tab == t ? .white : .white.opacity(0.45))
                            .frame(width: 25, height: 24)
                            .background(Capsule().fill(Color.white.opacity(vm.tab == t ? 0.16 : 0)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(t.title)
                }
                Spacer(minLength: vm.notchSize.width + 10)
                HStack(spacing: 8) {
                    TimelineView(.everyMinute) { ctx in
                        Text(ctx.date, format: .dateTime.hour().minute())
                            .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    }
                    if battery.hasBattery {
                        HStack(spacing: 3) {
                            Text("\(battery.level)%").font(.system(size: 11, weight: .medium)).monospacedDigit()
                            Image(systemName: battery.icon)
                                .foregroundStyle(battery.pluggedIn ? .green : (battery.level <= 20 ? .red : .white))
                        }
                    }
                }
                .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .frame(height: vm.notchSize.height)

            Group {
                switch vm.tab {
                case .home: HomeTab()
                case .notifications: NotificationsTab()
                case .widgets: WidgetsTab()
                case .messages: MessagesTab()
                case .phone: PhoneTab()
                case .audio: AudioTab()
                case .shelf: ShelfTab()
                case .system: SystemTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, vm.previewPinned ? 6 : 16)

            if vm.previewPinned {
                Button { vm.endPreview() } label: {
                    Label(L("End preview"), systemImage: "xmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.16)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .frame(height: 24)
                .padding(.bottom, 16)
            }
        }
        .foregroundStyle(.white)
        .background {
            if vm.tab == .audio || vm.tab == .home {
                AmbientGlow(anchor: vm.tab == .home ? UnitPoint(x: 0.15, y: 0.55) : UnitPoint(x: 0.3, y: 0.4))
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: vm.tab)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted.value) { providers in
            vm.tab = .shelf
            return shelf.handle(providers: providers)
        }
        .onChange(of: dropTargeted.value) { _, t in if t { vm.tab = .shelf } }
    }
}
