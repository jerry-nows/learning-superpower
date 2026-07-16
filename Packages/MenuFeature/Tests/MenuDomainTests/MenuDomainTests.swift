@testable import MenuDomain
import Testing

@Test("MenuDomain module is available")
func menuDomainModuleIsAvailable() {
    #expect(MenuDomainModule.moduleName == "MenuDomain")
}

@Test("MenuFeature package exposes the domain library")
func menuFeatureDomainContractIsStable() {
    #expect(MenuDomainModule.moduleName.isEmpty == false)
}
