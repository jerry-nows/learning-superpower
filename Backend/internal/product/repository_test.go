package product

import (
	"context"
	"reflect"
	"testing"
	"time"
)

type fakeProductRepository struct {
	page       ProductPage
	product    Product
	categories []Category
	reviews    []Review
	comments   []Comment
	stock      Stock
	err        error
}

func (f fakeProductRepository) List(context.Context, ProductQuery) (ProductPage, error) {
	return f.page, f.err
}
func (f fakeProductRepository) FindByID(context.Context, ProductID) (Product, error) {
	return f.product, f.err
}
func (f fakeProductRepository) ListCategories(context.Context) ([]Category, error) {
	return f.categories, f.err
}
func (f fakeProductRepository) ListReviews(context.Context, ProductID) ([]Review, error) {
	return f.reviews, f.err
}
func (f fakeProductRepository) ListComments(context.Context, ProductID) ([]Comment, error) {
	return f.comments, f.err
}
func (f fakeProductRepository) GetStock(context.Context, ProductID) (Stock, error) {
	return f.stock, f.err
}

var _ ProductRepository = fakeProductRepository{}

func TestProductRepositoryContractReturnsDeterministicEmptyResponses(t *testing.T) {
	repository := fakeProductRepository{}
	ctx := context.Background()
	page, err := repository.List(ctx, ProductQuery{Page: 1, PageSize: 20})
	if err != nil || !reflect.DeepEqual(page, ProductPage{}) {
		t.Fatalf("empty page = %#v, err %v", page, err)
	}
	categories, err := repository.ListCategories(ctx)
	if err != nil || categories != nil {
		t.Fatalf("empty categories = %#v, err %v", categories, err)
	}
	reviews, err := repository.ListReviews(ctx, "p1")
	if err != nil || reviews != nil {
		t.Fatalf("empty reviews = %#v, err %v", reviews, err)
	}
	comments, err := repository.ListComments(ctx, "p1")
	if err != nil || comments != nil {
		t.Fatalf("empty comments = %#v, err %v", comments, err)
	}
	stock, err := repository.GetStock(ctx, "p1")
	if err != nil || !reflect.DeepEqual(stock, Stock{}) {
		t.Fatalf("empty stock = %#v, err %v", stock, err)
	}
}

func TestProductRepositoryContractReturnsPopulatedResponses(t *testing.T) {
	now := time.Date(2026, time.July, 16, 10, 0, 0, 0, time.UTC)
	expected := fakeProductRepository{
		page:       ProductPage{Items: []Product{{ID: "p1", Name: "Coffee", Price: 42000, CreatedAt: now, UpdatedAt: now}}, Page: 1, PageSize: 1, Total: 1},
		product:    Product{ID: "p1", Name: "Coffee", Price: 42000, CreatedAt: now, UpdatedAt: now},
		categories: []Category{{ID: "c1", Name: "Drinks", CreatedAt: now, UpdatedAt: now}},
		reviews:    []Review{{ID: "r1", ProductID: "p1", UserID: "u1", Rating: 5, Body: "Great", CreatedAt: now}},
		comments:   []Comment{{ID: "m1", ProductID: "p1", UserID: "u1", Body: "Fresh", CreatedAt: now}},
		stock:      Stock{ProductID: "p1", Available: 7, UpdatedAt: now},
	}
	ctx := context.Background()
	page, _ := expected.List(ctx, ProductQuery{Page: 1, PageSize: 1})
	if !reflect.DeepEqual(page, expected.page) {
		t.Fatalf("page = %#v, want %#v", page, expected.page)
	}
	product, _ := expected.FindByID(ctx, "p1")
	if !reflect.DeepEqual(product, expected.product) {
		t.Fatalf("product = %#v, want %#v", product, expected.product)
	}
	categories, _ := expected.ListCategories(ctx)
	if !reflect.DeepEqual(categories, expected.categories) {
		t.Fatalf("categories = %#v, want %#v", categories, expected.categories)
	}
	reviews, _ := expected.ListReviews(ctx, "p1")
	comments, _ := expected.ListComments(ctx, "p1")
	stock, _ := expected.GetStock(ctx, "p1")
	if !reflect.DeepEqual(reviews, expected.reviews) || !reflect.DeepEqual(comments, expected.comments) || !reflect.DeepEqual(stock, expected.stock) {
		t.Fatalf("detail responses did not preserve deterministic values")
	}
}
