import Foundation

struct ButtonRepeatContext: Equatable {
    let application: ForegroundApplication?
    let mappingRevision: UInt64
}

/// Authorizes each timer for one physical press, process and mapping revision.
/// A cancelled or released timer cannot become valid again after a new press,
/// even if an old callback was already queued or the user returns to the app.
struct ButtonRepeatState {
    struct Ticket: Equatable {
        let usage: UInt16
        fileprivate let identifier = UUID()
    }

    private var context: ButtonRepeatContext?
    private var tickets: [UInt16: Ticket] = [:]

    /// Returns true when the caller must also cancel its scheduled timers.
    mutating func synchronize(with current: ButtonRepeatContext) -> Bool {
        guard context != current else { return false }
        context = current
        cancelAll()
        return true
    }

    mutating func begin(usage: UInt16) -> Ticket? {
        guard context?.application != nil else { return nil }
        let ticket = Ticket(usage: usage)
        tickets[usage] = ticket
        return ticket
    }

    func canDeliver(_ ticket: Ticket) -> Bool { tickets[ticket.usage] == ticket }

    mutating func release(usage: UInt16) { tickets.removeValue(forKey: usage) }

    mutating func cancelAll() { tickets.removeAll() }
}
