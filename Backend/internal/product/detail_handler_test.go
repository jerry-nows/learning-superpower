package product

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

type detailHandlerRepo struct {
	reviews     []Review
	comments    []Comment
	stock       Stock
	reviewsErr  error
	commentsErr error
	stockErr    error
}

func (r detailHandlerRepo) List(context.Context, ProductQuery) (ProductPage, error) {
	return ProductPage{}, nil
}
func (r detailHandlerRepo) FindByID(context.Context, ProductID) (Product, error) {
	return Product{}, nil
}
func (r detailHandlerRepo) ListCategories(context.Context) ([]Category, error) { return nil, nil }
func (r detailHandlerRepo) ListReviews(context.Context, ProductID) ([]Review, error) {
	return r.reviews, r.reviewsErr
}
func (r detailHandlerRepo) ListComments(context.Context, ProductID) ([]Comment, error) {
	return r.comments, r.commentsErr
}
func (r detailHandlerRepo) GetStock(context.Context, ProductID) (Stock, error) {
	return r.stock, r.stockErr
}

func detailRequest(t *testing.T, h http.HandlerFunc, method, path string) *httptest.ResponseRecorder {
	t.Helper()
	r := httptest.NewRequest(method, path, nil)
	r.Header.Set("Authorization", "Bearer access")
	w := httptest.NewRecorder()
	h(w, r)
	return w
}

func TestProductDetailSectionHandlersReturnIndependentSuccessResponses(t *testing.T) {
	now := time.Unix(1, 0).UTC()
	h := NewHandler(detailHandlerRepo{
		reviews:  []Review{{ID: "r1", ProductID: "p1", Rating: 5, Body: "great", CreatedAt: now}},
		comments: []Comment{{ID: "c1", ProductID: "p1", Body: "fresh", CreatedAt: now}},
		stock:    Stock{ProductID: "p1", Available: 7, UpdatedAt: now},
	}, productVerifier{})

	reviews := detailRequest(t, h.Reviews, http.MethodGet, "/v1/products/p1/reviews")
	if reviews.Code != http.StatusOK {
		t.Fatalf("reviews status=%d body=%s", reviews.Code, reviews.Body)
	}
	var gotReviews []Review
	if err := json.NewDecoder(reviews.Body).Decode(&gotReviews); err != nil || len(gotReviews) != 1 {
		t.Fatalf("reviews=%+v err=%v", gotReviews, err)
	}

	comments := detailRequest(t, h.Comments, http.MethodGet, "/v1/products/p1/comments")
	if comments.Code != http.StatusOK {
		t.Fatalf("comments status=%d body=%s", comments.Code, comments.Body)
	}
	var gotComments []Comment
	if err := json.NewDecoder(comments.Body).Decode(&gotComments); err != nil || len(gotComments) != 1 {
		t.Fatalf("comments=%+v err=%v", gotComments, err)
	}

	stock := detailRequest(t, h.Stock, http.MethodGet, "/v1/products/p1/stock")
	var gotStock Stock
	if stock.Code != http.StatusOK || json.NewDecoder(stock.Body).Decode(&gotStock) != nil || gotStock.Available != 7 {
		t.Fatalf("stock status=%d value=%+v", stock.Code, gotStock)
	}
	inventory := detailRequest(t, h.Inventory, http.MethodGet, "/v1/products/p1/inventory")
	if inventory.Code != http.StatusOK {
		t.Fatalf("inventory alias status=%d body=%s", inventory.Code, inventory.Body)
	}
	summary := detailRequest(t, h.RatingSummary, http.MethodGet, "/v1/products/p1/rating-summary")
	var gotSummary RatingSummary
	if summary.Code != http.StatusOK || json.NewDecoder(summary.Body).Decode(&gotSummary) != nil || gotSummary.ReviewCount != 1 || gotSummary.AverageRating != 5 {
		t.Fatalf("summary status=%d value=%+v", summary.Code, gotSummary)
	}
}

func TestProductDetailSectionHandlersRequireAuthorization(t *testing.T) {
	h := NewHandler(detailHandlerRepo{}, productVerifier{})
	sections := []struct {
		name string
		h    http.HandlerFunc
		path string
	}{
		{"reviews", h.Reviews, "/v1/products/p1/reviews"},
		{"comments", h.Comments, "/v1/products/p1/comments"},
		{"stock", h.Stock, "/v1/products/p1/stock"},
		{"inventory", h.Inventory, "/v1/products/p1/inventory"},
		{"rating-summary", h.RatingSummary, "/v1/products/p1/rating-summary"},
	}
	for _, section := range sections {
		t.Run(section.name, func(t *testing.T) {
			r := httptest.NewRequest(http.MethodGet, section.path, nil)
			w := httptest.NewRecorder()
			section.h(w, r)
			if w.Code != http.StatusUnauthorized {
				t.Fatalf("status=%d body=%s", w.Code, w.Body)
			}
		})
	}
}

func TestProductDetailSectionFailureDoesNotAffectOtherSections(t *testing.T) {
	h := NewHandler(detailHandlerRepo{
		reviews:     []Review{{ID: "r1"}},
		commentsErr: errors.New("comments unavailable"),
		stock:       Stock{ProductID: "p1", Available: 2},
	}, productVerifier{})

	comments := detailRequest(t, h.Comments, http.MethodGet, "/v1/products/p1/comments")
	if comments.Code != http.StatusInternalServerError {
		t.Fatalf("comments status=%d body=%s", comments.Code, comments.Body)
	}
	var failure productError
	if err := json.NewDecoder(comments.Body).Decode(&failure); err != nil || failure.Code != "PRODUCT_INTERNAL" {
		t.Fatalf("failure=%+v err=%v", failure, err)
	}

	reviews := detailRequest(t, h.Reviews, http.MethodGet, "/v1/products/p1/reviews")
	if reviews.Code != http.StatusOK {
		t.Fatalf("reviews should remain available: status=%d", reviews.Code)
	}
	stock := detailRequest(t, h.Stock, http.MethodGet, "/v1/products/p1/stock")
	if stock.Code != http.StatusOK {
		t.Fatalf("stock should remain available: status=%d", stock.Code)
	}
}

func TestProductDetailSectionHandlersValidatePathAndMethod(t *testing.T) {
	h := NewHandler(detailHandlerRepo{}, productVerifier{})
	if got := detailRequest(t, h.Stock, http.MethodGet, "/v1/products/p1/stock/extra"); got.Code != http.StatusBadRequest {
		t.Fatalf("invalid path status=%d", got.Code)
	}
	if got := detailRequest(t, h.Reviews, http.MethodPost, "/v1/products/p1/reviews"); got.Code != http.StatusMethodNotAllowed {
		t.Fatalf("method status=%d", got.Code)
	}
}
