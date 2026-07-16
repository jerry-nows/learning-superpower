package product

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/vominhtri1049/learning-superpower/backend/internal/auth"
)

type handlerRepo struct {
	page       ProductPage
	item       Product
	categories []Category
	listErr    error
}

func (r handlerRepo) List(context.Context, ProductQuery) (ProductPage, error) {
	return r.page, r.listErr
}
func (r handlerRepo) FindByID(context.Context, ProductID) (Product, error) { return r.item, r.listErr }
func (r handlerRepo) ListCategories(context.Context) ([]Category, error) {
	return r.categories, r.listErr
}
func (r handlerRepo) ListReviews(context.Context, ProductID) ([]Review, error) {
	return []Review{}, nil
}
func (r handlerRepo) ListComments(context.Context, ProductID) ([]Comment, error) {
	return []Comment{}, nil
}
func (r handlerRepo) GetStock(context.Context, ProductID) (Stock, error) { return Stock{}, nil }

type productVerifier struct{ err error }

func (v productVerifier) Verify(string) (auth.AccessTokenClaims, error) {
	if v.err != nil {
		return auth.AccessTokenClaims{}, v.err
	}
	return auth.AccessTokenClaims{RegisteredClaims: jwt.RegisteredClaims{Subject: "u-1"}}, nil
}

func request(t *testing.T, h *Handler, method, path string) *httptest.ResponseRecorder {
	t.Helper()
	r := httptest.NewRequest(method, path, nil)
	r.Header.Set("Authorization", "Bearer access")
	w := httptest.NewRecorder()
	switch r.URL.Path {
	case "/v1/products":
		h.List(w, r)
	case "/v1/categories":
		h.Categories(w, r)
	default:
		h.Detail(w, r)
	}
	return w
}

func TestProductHandlerRequiresBearer(t *testing.T) {
	h := NewHandler(handlerRepo{}, productVerifier{})
	r := httptest.NewRequest(http.MethodGet, "/v1/products", nil)
	w := httptest.NewRecorder()
	h.List(w, r)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("status=%d body=%s", w.Code, w.Body)
	}
}

func TestProductHandlerListSuccessAndPagination(t *testing.T) {
	now := time.Unix(1, 0).UTC()
	h := NewHandler(handlerRepo{page: ProductPage{Items: []Product{{ID: "p-1", Name: "Phone", CreatedAt: now}}, Page: 2, PageSize: 1, Total: 3, HasNext: true}}, productVerifier{})
	w := request(t, h, http.MethodGet, "/v1/products?page=2&page_size=1&search=phone&sort=price_asc")
	if w.Code != http.StatusOK || w.Header().Get("Content-Type") != "application/json" {
		t.Fatalf("status=%d headers=%v", w.Code, w.Header())
	}
	var got ProductPage
	if err := json.NewDecoder(w.Body).Decode(&got); err != nil {
		t.Fatal(err)
	}
	if got.Page != 2 || got.PageSize != 1 || !got.HasNext || len(got.Items) != 1 {
		t.Fatalf("page=%+v", got)
	}
}

func TestProductHandlerInvalidQueryAndEmptyPage(t *testing.T) {
	h := NewHandler(handlerRepo{page: ProductPage{Items: []Product{}, Page: 1, PageSize: 20}}, productVerifier{})
	for _, path := range []string{"/v1/products?page=0", "/v1/products?page_size=101", "/v1/products?sort=bad", "/v1/products?page=nope"} {
		w := request(t, h, http.MethodGet, path)
		if w.Code != http.StatusBadRequest {
			t.Fatalf("%s status=%d", path, w.Code)
		}
	}
	w := request(t, h, http.MethodGet, "/v1/products?page=5")
	if w.Code != http.StatusOK || w.Body.String() == "" {
		t.Fatalf("empty status=%d body=%s", w.Code, w.Body)
	}
}

func TestProductHandlerDetailAndCategories(t *testing.T) {
	h := NewHandler(handlerRepo{item: Product{ID: "p-1", Name: "Phone"}, categories: []Category{{ID: "c-1", Name: "Tech"}}}, productVerifier{})
	w := request(t, h, http.MethodGet, "/v1/products/p-1")
	if w.Code != http.StatusOK || w.Body.String() == "" {
		t.Fatalf("detail status=%d", w.Code)
	}
	w = request(t, h, http.MethodGet, "/v1/categories")
	if w.Code != http.StatusOK || w.Body.String() == "" {
		t.Fatalf("categories status=%d", w.Code)
	}
}
