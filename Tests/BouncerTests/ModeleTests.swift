import Testing
@testable import BouncerCore

struct ModeleTests {
    /// Le cœur de la bascule par cycle de vie : quitter une app lui retire son pid, pas sa place
    /// dans la liste — sinon on n'aurait plus rien à relancer.
    @Test("Une app tuée reste dans la liste, sans pid")
    func appTueeResteDansLaListeSansPid() {
        var app = NotchAppInfo(bundleID: "com.example.notch", name: "Exemple",
                               support: .supported, pid: 1234, isHiddenByUs: false)
        #expect(app.estLancee)
        app.pid = nil
        #expect(app.id == "com.example.notch")
        #expect(app.estLancee == false)
    }

    /// Deux process du même bundleID (relance) sont la même app ; deux bundleIDs distincts ne le
    /// sont pas, même si le système recycle un pid entre les deux.
    @Test("L'identité d'une app ne dépend pas de son pid")
    func identiteIndependanteDuPid() {
        let avant = NotchAppInfo(bundleID: "com.example.notch", name: "Exemple",
                                 support: .supported, pid: 1234, isHiddenByUs: false)
        let apresRelance = NotchAppInfo(bundleID: "com.example.notch", name: "Exemple",
                                        support: .supported, pid: 9876, isHiddenByUs: false)
        let autre = NotchAppInfo(bundleID: "com.example.autre", name: "Autre",
                                 support: .supported, pid: 1234, isHiddenByUs: false)
        #expect(avant.id == apresRelance.id)
        #expect(avant.id != autre.id)
    }
}
