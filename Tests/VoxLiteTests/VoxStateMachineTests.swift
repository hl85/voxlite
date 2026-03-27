import Testing
@testable import VoxLiteDomain

struct VoxStateMachineTests {
    @Test
    func transition_withValidChain_reachesDone() {
        let store = VoxStateMachine()

        #expect(store.transition(to: .recording))
        #expect(store.transition(to: .processing))
        #expect(store.transition(to: .injecting))
        #expect(store.transition(to: .done))
        #expect(store.current == .done)
    }

    @Test
    func transition_withInvalidPath_rejectsChange() {
        let store = VoxStateMachine()

        #expect(store.transition(to: .processing) == false)
        #expect(store.current == .idle)
    }
}
