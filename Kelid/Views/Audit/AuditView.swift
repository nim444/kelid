import Charts
import SwiftUI

/// Audit detail pane: stat cards, a daily-activity chart, and the filterable
/// event stream — all backed by the tamper-evident hash chain.
struct AuditView: View {
    @State private var filter: AuditEvent.Category?
    @State private var query = ""

    private var audit: AuditLog { .shared }

    private var filtered: [AuditEvent] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return audit.events.reversed().filter { event in
            if let filter, event.category != filter { return false }
            if q.isEmpty { return true }
            return event.action.lowercased().contains(q)
                || event.detail.lowercased().contains(q)
                || event.category.title.lowercased().contains(q)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statsRow
                chartCard
                filterRow
                eventList
            }
            .padding(24)
        }
    }

    // MARK: - Stats

    private var todayCount: Int {
        audit.events.count { Calendar.current.isDateInToday($0.at) }
    }

    private var problemCount: Int {
        audit.events.count { $0.outcome == .failure || $0.outcome == .denied }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            statCard("Total Events", "\(audit.events.count)", "list.bullet.rectangle")
            statCard("Today", "\(todayCount)", "sun.max")
            statCard("Failures / Denied", "\(problemCount)", "exclamationmark.shield")
            chainCard
        }
    }

    private func statCard(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LinearGradient.kelidAccent)
                Text(title)
                    .font(.kelid(11, .medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private var chainCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: audit.chainValid ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(audit.chainValid ? .green : .red)
                Text("Hash Chain")
                    .font(.kelid(11, .medium))
                    .foregroundStyle(.secondary)
            }
            Text(audit.chainValid ? "Verified" : "BROKEN")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(audit.chainValid ? Color.primary : .red)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .help("Every event includes the previous event's hash — tampering with the log breaks the chain.")
    }

    // MARK: - Chart

    private struct DayCount: Identifiable {
        let day: Date
        let count: Int
        var id: Date { day }
    }

    private var daily: [DayCount] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var counts: [Date: Int] = [:]
        for event in audit.events {
            counts[calendar.startOfDay(for: event.at), default: 0] += 1
        }
        return (0..<14).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DayCount(day: day, count: counts[day] ?? 0)
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Activity")
                .font(.kelid(13, .semibold))
            Chart(daily) { item in
                BarMark(
                    x: .value("Day", item.day, unit: .day),
                    y: .value("Events", item.count)
                )
                .foregroundStyle(LinearGradient.kelidAccent)
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .font(.kelid(10, .regular))
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel().font(.kelid(10, .regular))
                }
            }
            .frame(height: 160)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    // MARK: - Filter

    private var filterRow: some View {
        HStack(spacing: 10) {
            Menu {
                Button("All categories") { filter = nil }
                Divider()
                ForEach(AuditEvent.Category.allCases) { category in
                    Button {
                        filter = category
                    } label: {
                        Label(category.title, systemImage: category.icon)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: filter?.icon ?? "line.3.horizontal.decrease.circle")
                        .font(.system(size: 12))
                    Text(filter?.title ?? "All categories")
                        .font(.kelid(12, .medium))
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                TextField("Search events", text: $query)
                    .textFieldStyle(.plain)
                    .font(.kelid(13, .regular))
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
        }
    }

    // MARK: - Events

    private var eventList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(audit.events.isEmpty ? "No events yet — they appear as you use Kelid." : "Nothing matches the filter.")
                        .font(.kelid(12, .regular))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            } else {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { index, event in
                    eventRow(event)
                    if index < filtered.count - 1 {
                        Divider().opacity(0.25).padding(.leading, 46)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func eventRow(_ event: AuditEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: event.category.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(LinearGradient.kelidAccent)
                .frame(width: 26, height: 26)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text(event.action)
                    .font(.kelid(13, .medium))
                if !event.detail.isEmpty {
                    Text(event.detail)
                        .font(.kelid(11, .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            outcomeChip(event.outcome)

            Text(event.at.formatted(.relative(presentation: .named)))
                .font(.kelid(11, .regular))
                .foregroundStyle(.tertiary)
                .frame(minWidth: 80, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func outcomeChip(_ outcome: AuditEvent.Outcome) -> some View {
        let (label, color): (String, Color) = switch outcome {
        case .success: ("ok", .green)
        case .failure: ("failed", .red)
        case .denied: ("denied", .orange)
        case .info: ("info", .secondary)
        }
        return Text(label)
            .font(.kelid(10, .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: .capsule)
    }
}
