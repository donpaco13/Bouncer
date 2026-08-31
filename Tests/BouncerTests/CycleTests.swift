import Testing
@testable import BouncerCore

struct CycleTests {
    @Test("L'élément suivant d'un cycle en avant")
    func cibleSuivanteEnAvant() {
        let apps = ["a", "b", "c"]
        #expect(prochaineCible(dans: apps, depuis: "a", forward: true) == "b")
    }
}
