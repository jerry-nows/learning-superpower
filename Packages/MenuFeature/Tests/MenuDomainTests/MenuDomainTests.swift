import Testing
@testable import MenuDomain

@Test("MenuDomain module is available")
func menuDomainModuleIsAvailable() {
    #expect(MenuDomain.moduleName == "MenuDomain")
}

@Test("MenuFeature package exposes the domain library")
func menuFeatureDomainContractIsStable() {
    #expect(MenuDomain.moduleName.isEmpty == false)
}
