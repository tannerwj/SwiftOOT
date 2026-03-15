import XCTest
import OOTCore
import OOTDataModel
@testable import OOTUI

final class MessageOverlayTests: XCTestCase {
    func testMessageViewConstructsFromPresentation() {
        _ = MessageView(
            presentation: MessagePresentation(
                messageID: 0x1000,
                variant: .red,
                phase: .waitingForChoice,
                textRuns: [
                    MessageTextRun(text: "Do you want to hear a secret?", color: .white),
                ],
                icon: MessageIcon(rawValue: "warning"),
                choiceState: MessageChoiceState(
                    options: [
                        MessageChoiceOption(title: "Yes"),
                        MessageChoiceOption(title: "No"),
                    ],
                    selectedIndex: 1
                )
            )
        )
        _ = ActionPromptView(label: "Talk")
    }

    func testRootViewStateMappingRemainsStable() {
        XCTAssertEqual(OOTAppView.rootViewState(for: .boot), .boot)
        XCTAssertEqual(OOTAppView.rootViewState(for: .consoleLogo), .consoleLogo)
        XCTAssertEqual(OOTAppView.rootViewState(for: .titleScreen), .titleScreen)
        XCTAssertEqual(OOTAppView.rootViewState(for: .fileSelect), .fileSelect)
        XCTAssertEqual(OOTAppView.rootViewState(for: .gameplay), .gameplay)
    }
}
