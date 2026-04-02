import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct BeamletProvider: TimelineProvider {
    func placeholder(in context: Context) -> BeamletEntry {
        BeamletEntry(date: Date(), files: [
            WidgetFile(senderName: "Sarah", type: "Photo", timeAgo: "2m ago"),
            WidgetFile(senderName: "Alex", type: "Message", timeAgo: "15m ago"),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (BeamletEntry) -> Void) {
        let files = loadRecentFiles()
        completion(BeamletEntry(date: Date(), files: files))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BeamletEntry>) -> Void) {
        let files = loadRecentFiles()
        let entry = BeamletEntry(date: Date(), files: files)
        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadRecentFiles() -> [WidgetFile] {
        guard let defaults = UserDefaults(suiteName: "group.com.beamlet.shared"),
              let data = defaults.data(forKey: "widgetRecentFiles"),
              let files = try? JSONDecoder().decode([WidgetFile].self, from: data) else {
            return []
        }
        return Array(files.prefix(4))
    }
}

// MARK: - Models

struct WidgetFile: Codable, Identifiable {
    var id: String { "\(senderName)-\(timeAgo)" }
    let senderName: String
    let type: String
    let timeAgo: String
}

struct BeamletEntry: TimelineEntry {
    let date: Date
    let files: [WidgetFile]
}

// MARK: - Widget Views

struct BeamletWidgetEntryView: View {
    var entry: BeamletEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        default:
            mediumView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "paperplane.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text("Beamlet")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            if entry.files.isEmpty {
                Spacer()
                Text("No recent files")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            } else {
                ForEach(entry.files.prefix(3)) { file in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(colorFor(file.senderName))
                            .frame(width: 20, height: 20)
                            .overlay(
                                Text(file.senderName.prefix(1).uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            )
                        VStack(alignment: .leading, spacing: 0) {
                            Text(file.senderName)
                                .font(.caption2.bold())
                                .lineLimit(1)
                            Text(file.type)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "paperplane.fill")
                    .foregroundStyle(.blue)
                Text("Beamlet")
                    .font(.headline)
                Spacer()
                Text(entry.files.isEmpty ? "" : "\(entry.files.count) recent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if entry.files.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("No recent files")
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                Spacer()
            } else {
                ForEach(entry.files.prefix(4)) { file in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(colorFor(file.senderName))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Text(file.senderName.prefix(1).uppercased())
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                            )
                        VStack(alignment: .leading, spacing: 1) {
                            Text(file.senderName)
                                .font(.subheadline.bold())
                            Text("\(file.type) · \(file.timeAgo)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func colorFor(_ name: String) -> Color {
        let colors: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .indigo, .mint]
        let hash = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return colors[abs(hash) % colors.count]
    }
}

// MARK: - Widget

@main
struct BeamletWidget: Widget {
    let kind: String = "BeamletWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BeamletProvider()) { entry in
            BeamletWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Beamlet")
        .description("See your recent received files.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
