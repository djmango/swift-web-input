import Testing
@testable import SwiftWebInput

struct SwiftWebInputTests {
    @Test func testWebInputViewModelInitialState() {
        let viewModel = WebInputViewModel()
        #expect(viewModel.text == "")
        #expect(viewModel.height == 52)
    }

    @Test func testWebInputViewModelClearText() {
        let viewModel = WebInputViewModel()
        viewModel.text = "Test text"
        viewModel.clearText()
        #expect(viewModel.text == "")
    }

    @MainActor
    @Test func testSwiftWebInputViewInitialization() {
        let viewModel = WebInputViewModel()
        let view = SwiftWebInputView(webInputViewModel: viewModel, onSubmit: {}, inputPlaceholder: "Enter text")
        #expect(view.getWebInputViewModelForTesting() === viewModel)
        #expect(view.getInputPlaceholderForTesting() == "Enter text")
    }
}
