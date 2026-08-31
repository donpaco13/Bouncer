import XCTest
@testable import BouncerCore

final class ModeleTests: XCTestCase {
    /// Le cœur de la bascule par cycle de vie : quitter une app lui retire son pid, pas sa place
    /// dans la liste — sinon on n'aurait plus rien à relancer.
    func testAppTueeResteDansLaListeSansPid() {
        var app = NotchAppInfo(bundleID: "com.example.notch", name: "Exemple",
                               support: .supported, pid: 1234, isHiddenByUs: false)
        XCTAssertTrue(app.estLancee)
        app.pid = nil
        XCTAssertEqual(app.id, "com.example.notch")
        XCTAssertFalse(app.estLancee)
    }

    /// Deux process du même bundleID (relance) sont la même app ; deux bundleIDs distincts ne le
    /// sont pas, même si le système recycle un pid entre les deux.
    func testIdentiteIndependanteDuPid() {
        let avant = NotchAppInfo(bundleID: "com.example.notch", name: "Exemple",
                                 support: .supported, pid: 1234, isHiddenByUs: false)
        let apresRelance = NotchAppInfo(bundleID: "com.example.notch", name: "Exemple",
                                        support: .supported, pid: 9876, isHiddenByUs: false)
        let autre = NotchAppInfo(bundleID: "com.example.autre", name: "Autre",
                                 support: .supported, pid: 1234, isHiddenByUs: false)
        XCTAssertEqual(avant.id, apresRelance.id)
        XCTAssertNotEqual(avant.id, autre.id)
    }
}
