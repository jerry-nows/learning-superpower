@testable import MenuDomain
import Testing

@Test("product identity remains stable when display data changes")
func productIdentityIsStable() {
    let first = Product(id: "p-1", categoryID: "fashion", name: "Old name", price: 100)
    let second = Product(id: first.id, categoryID: first.categoryID, name: "New name", price: 200)

    #expect(first.id == second.id)
    #expect(first.id == "p-1")
}

@Test("detail sections start as skeleton and transition independently")
func detailSectionTransitionsAreSkeletonReady() {
    let pending: DetailSectionState<Product> = .skeleton
    let product = Product(id: "p-1", categoryID: "home", name: "Lamp", price: 500)
    let loaded: DetailSectionState<Product> = .loaded(product)
    let failed: DetailSectionState<Product> = .failed("offline")

    #expect(pending.isSkeleton)
    #expect(!loaded.isSkeleton)
    #expect(!failed.isSkeleton)
    #expect(loaded == .loaded(product))
}
