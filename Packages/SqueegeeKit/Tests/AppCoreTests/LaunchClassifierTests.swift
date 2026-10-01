import AppCore
import Testing

@Suite("LaunchClassifier")
struct LaunchClassifierTests {
    // MARK: - classify

    @Test func descriptorAbsentClassifiesAsUser() {
        let kind = LaunchClassifier.classify(loginItemDescriptorValue: nil)
        #expect(kind == .user)
    }

    @Test func descriptorTrueClassifiesAsLoginItem() {
        let kind = LaunchClassifier.classify(loginItemDescriptorValue: true)
        #expect(kind == .loginItem)
    }

    @Test func descriptorFalseClassifiesAsUser() {
        let kind = LaunchClassifier.classify(loginItemDescriptorValue: false)
        #expect(kind == .user)
    }

    // MARK: - shouldShowWindow

    @Test func userLaunchShowsWindow() {
        #expect(LaunchClassifier.shouldShowWindow(for: .user))
    }

    @Test func loginItemLaunchHidesWindow() {
        #expect(!LaunchClassifier.shouldShowWindow(for: .loginItem))
    }
}
