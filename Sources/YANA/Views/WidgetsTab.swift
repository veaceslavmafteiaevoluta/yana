import SwiftUI

struct WidgetsTab: View {
    @EnvironmentObject var weather: WeatherService
    @EnvironmentObject var timer: TimerService
    @StateObject private var custom = Box(10.0)

    var body: some View {
        HStack(spacing: 14) {
            // Weather
            VStack(alignment: .leading, spacing: 8) {
                if let t = weather.temperature {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(weather.city.isEmpty ? L("Weather") : weather.city).font(.system(size: 12, weight: .semibold))
                            Text("\(Int(t.rounded()))°").font(.system(size: 38, weight: .light))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Image(systemName: WeatherService.symbol(weather.code)).symbolRenderingMode(.multicolor).font(.system(size: 26))
                            Text(WeatherService.describe(weather.code)).font(.system(size: 11))
                            if let h = weather.high, let l = weather.low {
                                Text(L("H:%ld° L:%ld°", Int(h.rounded()), Int(l.rounded()))).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 0) {
                        ForEach(weather.hourly) { h in
                            VStack(spacing: 5) {
                                Text(h.time.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)))).font(.system(size: 10)).foregroundStyle(.secondary)
                                let hour = Calendar.current.component(.hour, from: h.time)
                                Image(systemName: WeatherService.symbol(h.code, night: hour < 7 || hour > 19))
                                    .symbolRenderingMode(.multicolor).font(.system(size: 14)).frame(height: 18)
                                Text("\(Int(h.temp.rounded()))°").font(.system(size: 11, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                } else if weather.denied {
                    PermissionCard(icon: "location.slash", title: L("Location not allowed"),
                                   message: L("Enable YANA in Location Services to see the weather."),
                                   button: L("Open Settings")) { Permissions.openPane("Privacy_LocationServices") }
                } else {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Color.blue.opacity(0.35), Color.blue.opacity(0.1)], startPoint: .top, endPoint: .bottom)))

            // Timer / Pomodoro
            VStack(spacing: 8) {
                if timer.isActive {
                    TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                        ZStack {
                            Circle().stroke(Color.white.opacity(0.12), lineWidth: 6)
                            Circle().trim(from: 0, to: max(0.001, 1 - timer.remaining(at: ctx.date) / max(1, timer.total)))
                                .stroke(Color.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 0) {
                                Text(formatTime(timer.remaining(at: ctx.date))).font(.system(size: 20, weight: .semibold)).monospacedDigit()
                                Text(timer.label).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 110, height: 110)
                    }
                    HStack(spacing: 12) {
                        IconButton(systemName: timer.isRunning ? "pause.fill" : "play.fill", size: 16, tint: .orange) { timer.togglePause() }
                        IconButton(systemName: "xmark", size: 14) { timer.stop() }
                    }
                } else {
                    SectionTitle(text: L("Timer"))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        preset("🍅 25", 25, L("Pomodoro"))
                        preset("☕️ 5", 5, L("Break"))
                        preset("1 min", 1, L("Timer"))
                        preset("15 min", 15, L("Timer"))
                    }
                    HStack(spacing: 6) {
                        Stepper(value: $custom.value, in: 1...180, step: 1) {
                            Text("\(Int(custom.value)) min").font(.system(size: 11)).monospacedDigit()
                        }
                        .controlSize(.small)
                        Button(L("Start")) { timer.start(minutes: custom.value) }.controlSize(.small)
                    }
                }
            }
            .frame(width: 210)
            .frame(maxHeight: .infinity)
        }
    }

    private func preset(_ title: String, _ min: Double, _ label: String) -> some View {
        Button { timer.start(minutes: min, label: label) } label: {
            Text(title).font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}
