import Testing
@testable import XiaomiRemoteBridgeMac

@Suite("Application-aware button repeats")
struct ButtonRepeatStateTests {
    private func context(process: Int32 = 101, revision: UInt64 = 0) -> ButtonRepeatContext {
        ButtonRepeatContext(
            application: ForegroundApplication(processIdentifier: process, bundleIdentifier: "example.player", displayName: "Player"),
            mappingRevision: revision
        )
    }

    @Test func switchingInstancesAndReturningCannotResumeAnOldPress() throws {
        var repeats = ButtonRepeatState()
        _ = repeats.synchronize(with: context())
        let oldPressResult = repeats.begin(usage: RemoteButton.right.hidUsage)
        let oldPress = try #require(oldPressResult)
        #expect(repeats.canDeliver(oldPress))
        let switched = repeats.synchronize(with: context(process: 102))
        #expect(switched)
        #expect(!repeats.canDeliver(oldPress))
        _ = repeats.synchronize(with: context())
        #expect(!repeats.canDeliver(oldPress))
        let newPressResult = repeats.begin(usage: RemoteButton.right.hidUsage)
        let newPress = try #require(newPressResult)
        #expect(repeats.canDeliver(newPress))
        #expect(!repeats.canDeliver(oldPress))
    }

    @Test func mappingChangesAndExplicitCancellationRevokeQueuedCallbacks() throws {
        var repeats = ButtonRepeatState()
        _ = repeats.synchronize(with: context())
        let originalResult = repeats.begin(usage: RemoteButton.back.hidUsage)
        let original = try #require(originalResult)
        let unchanged = repeats.synchronize(with: context())
        #expect(!unchanged)
        #expect(repeats.canDeliver(original))
        _ = repeats.synchronize(with: context(revision: 1))
        #expect(!repeats.canDeliver(original))
        let updatedResult = repeats.begin(usage: RemoteButton.back.hidUsage)
        let updated = try #require(updatedResult)
        repeats.cancelAll()
        #expect(!repeats.canDeliver(updated))
    }

    @Test func releaseAndRepressInvalidateOnlyThatPhysicalPress() throws {
        var repeats = ButtonRepeatState()
        _ = repeats.synchronize(with: context())
        let rightResult = repeats.begin(usage: RemoteButton.right.hidUsage)
        let right = try #require(rightResult)
        let volumeResult = repeats.begin(usage: RemoteButton.volumeUp.hidUsage)
        let volume = try #require(volumeResult)
        repeats.release(usage: RemoteButton.right.hidUsage)
        let newRightResult = repeats.begin(usage: RemoteButton.right.hidUsage)
        let newRight = try #require(newRightResult)
        #expect(!repeats.canDeliver(right))
        #expect(repeats.canDeliver(volume))
        #expect(repeats.canDeliver(newRight))
    }

    @Test func unknownForegroundCannotAuthorizeRepeatingAnOldAction() throws {
        var repeats = ButtonRepeatState()
        _ = repeats.synchronize(with: context())
        let ticketResult = repeats.begin(usage: RemoteButton.up.hidUsage)
        let ticket = try #require(ticketResult)
        _ = repeats.synchronize(with: ButtonRepeatContext(application: nil, mappingRevision: 0))
        #expect(!repeats.canDeliver(ticket))
        let unknownPress = repeats.begin(usage: RemoteButton.up.hidUsage)
        #expect(unknownPress == nil)
    }
}
