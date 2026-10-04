#if DEBUG
import SwiftUI
import WidgetKit

private struct HeadroomIdentityProbeEntry: TimelineEntry {
    let date: Date
    let record: CompanionIdentityProbeRecord?
}

private struct HeadroomIdentityProbeProvider: TimelineProvider {
    func placeholder(in context: Context) -> HeadroomIdentityProbeEntry {
        HeadroomIdentityProbeEntry(date: .now, record: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (HeadroomIdentityProbeEntry) -> Void) {
        guard !context.isPreview else {
            completion(placeholder(in: context))
            return
        }
        completion(sample())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HeadroomIdentityProbeEntry>) -> Void) {
        guard !context.isPreview else {
            completion(Timeline(entries: [placeholder(in: context)], policy: .never))
            return
        }
        let entry = sample()
        // A diagnostic installed only during the gate: preserve WidgetKit's budget;
        // user-requested reloads still require proof of a fresh provider invocation.
        completion(Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(15 * 60))))
    }

    private func sample() -> HeadroomIdentityProbeEntry {
        // No app-provided current-scope value: this process reads FileManager itself.
        let record = CompanionIdentityProbe.appGroup().sample(role: .widget)
        return HeadroomIdentityProbeEntry(date: record.time, record: record)
    }
}

struct HeadroomIdentityProbeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CompanionIdentityProbe.widgetKind, provider: HeadroomIdentityProbeProvider()) { entry in
            VStack(alignment: .leading) {
                Text("Identity Probe").font(.caption.weight(.semibold))
                if let record = entry.record {
                    Text("Widget #\(record.ordinal) · \(record.step.rawValue)")
                        .font(.caption2)
                    Text("\(record.availability.rawValue) · \(record.equality.rawValue)")
                        .font(.caption)
                    Text("\(record.archive.rawValue) · \(record.coordination.rawValue)")
                        .font(.caption2)
                    Text(record.time, format: .dateTime.hour().minute().second())
                        .font(.caption.monospacedDigit())
                } else {
                    Text("Preview · no identity sampled")
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Identity Probe · DEBUG")
        .description("Local candidate availability and archived equality. No usage data.")
        .supportedFamilies([.systemSmall])
    }
}
#endif
