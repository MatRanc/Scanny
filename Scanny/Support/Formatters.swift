import Foundation

enum Formatters {
    static let rowDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static let titleDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f
    }()

    /// Default name for a freshly created scan, e.g. "Scan May 30, 1:45 PM".
    static func defaultDocumentTitle(date: Date = Date()) -> String {
        "Scan \(titleDate.string(from: date))"
    }

    static func pageCountLabel(_ count: Int) -> String {
        count == 1 ? "1 page" : "\(count) pages"
    }
}
