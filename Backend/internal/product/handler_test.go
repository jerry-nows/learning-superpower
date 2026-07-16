package product

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
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
	findErr    error
	reviews    []Review
	comments   []Comment
	stock      Stock
	sectionErr error
}

func (r handlerRepo) List(context.Context, ProductQuery) (ProductPage, error) {
	return r.page, r.listErr
}
func (r handlerRepo) FindByID(context.Context, ProductID) (Product, error) { return r.item, r.findErr }
func (r handlerRepo) ListCategories(context.Context) ([]Category, error) {
	return r.categories, r.listErr
}
func (r handlerRepo) ListReviews(context.Context, ProductID) ([]Review, error) {
	return r.reviews, r.sectionErr
}
func (r handlerRepo) ListComments(context.Context, ProductID) ([]Comment, error) {
	return r.comments, r.sectionErr
}
func (r handlerRepo) GetStock(context.Context, ProductID) (Stock, error) {
	return r.stock, r.sectionErr
}

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

func TestProductHandlerSectionsAndAliases(t *testing.T) {
	reviews := []Review{{ID: "r-1", Rating: 4}, {ID: "r-2", Rating: 2}}
	h := NewHandler(handlerRepo{reviews: reviews, comments: []Comment{{ID: "c-1"}}, stock: Stock{ProductID: "p-1", Available: 7}, categories: nil}, productVerifier{})
	cases := []struct {
		name string
		path string
		call func(http.ResponseWriter, *http.Request)
		want string
	}{
		{"reviews", "/v1/products/p-1/reviews", h.Reviews, "r-1"},
		{"comments", "/v1/products/p-1/comments", h.Comments, "c-1"},
		{"stock", "/v1/products/p-1/stock", h.Stock, "available"},
		{"inventory", "/v1/products/p-1/inventory", h.Inventory, "available"},
		{"rating", "/v1/products/p-1/rating-summary", h.RatingSummary, "average_rating"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			r := httptest.NewRequest(http.MethodGet, tc.path, nil)
			r.Header.Set("Authorization", "Bearer access")
			w := httptest.NewRecorder()
			tc.call(w, r)
			if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), tc.want) {
				t.Fatalf("status=%d body=%s", w.Code, w.Body)
			}
		})
	}
	w := request(t, h, http.MethodGet, "/v1/categories")
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"items":[]`) {
		t.Fatalf("categories=%s", w.Body)
	}
}

func TestProductHandlerRejectsMethodsAndMalformedPaths(t *testing.T) {
	h := NewHandler(handlerRepo{}, productVerifier{})
	for _, tc := range []struct {
		path string
		call func(http.ResponseWriter, *http.Request)
	}{
		{"/v1/products", h.List}, {"/v1/products/p/reviews", h.Reviews}, {"/v1/products/p/comments", h.Comments},
		{"/v1/products/p/stock", h.Stock}, {"/v1/products/p/inventory", h.Inventory}, {"/v1/products/p/rating-summary", h.RatingSummary}, {"/v1/categories", h.Categories},
	} {
		r := httptest.NewRequest(http.MethodPost, tc.path, nil)
		r.Header.Set("Authorization", "Bearer access")
		w := httptest.NewRecorder()
		tc.call(w, r)
		if w.Code != http.StatusMethodNotAllowed {
			t.Errorf("%s status=%d", tc.path, w.Code)
		}
	}
	for _, tc := range []struct {
		path string
		call func(http.ResponseWriter, *http.Request)
	}{
		{"/bad", h.Detail}, {"/v1/products/", h.Detail}, {"/v1/products/p/x", h.Detail}, {"/v1/products/p/reviews/x", h.Reviews},
		{"/v1/products/p/comments/x", h.Comments}, {"/v1/products/p/stock/x", h.Stock}, {"/v1/products/p/inventory/x", h.Inventory}, {"/v1/products/p/rating-summary/x", h.RatingSummary},
	} {
		r := httptest.NewRequest(http.MethodGet, tc.path, nil)
		r.Header.Set("Authorization", "Bearer access")
		w := httptest.NewRecorder()
		tc.call(w, r)
		if w.Code != http.StatusBadRequest {
			t.Errorf("%s status=%d", tc.path, w.Code)
		}
	}
}

func TestProductHandlerAuthorizationAndRepositoryErrors(t *testing.T) {
	badVerifier := NewHandler(handlerRepo{}, productVerifier{err: errors.New("expired")})
	r := httptest.NewRequest(http.MethodGet, "/v1/products", nil)
	r.Header.Set("Authorization", "Bearer access")
	w := httptest.NewRecorder()
	badVerifier.List(w, r)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("invalid token status=%d", w.Code)
	}
	for _, header := range []string{"", "Basic token", "Bearer"} {
		r := httptest.NewRequest(http.MethodGet, "/v1/products", nil)
		r.Header.Set("Authorization", header)
		w := httptest.NewRecorder()
		badVerifier.List(w, r)
		if w.Code != http.StatusUnauthorized {
			t.Errorf("header=%q status=%d", header, w.Code)
		}
	}
	for _, tc := range []struct {
		name string
		err  error
		want int
	}{{"notfound", ErrProductNotFound, http.StatusNotFound}, {"timeout", context.DeadlineExceeded, http.StatusRequestTimeout}, {"internal", errors.New("boom"), http.StatusInternalServerError}} {
		t.Run(tc.name, func(t *testing.T) {
			h := NewHandler(handlerRepo{listErr: tc.err}, productVerifier{})
			w := request(t, h, http.MethodGet, "/v1/products")
			if w.Code != tc.want {
				t.Fatalf("status=%d body=%s", w.Code, w.Body)
			}
		})
	}
	for _, tc := range []struct {
		name string
		call func(http.ResponseWriter, *http.Request)
		path string
	}{
		{"detail", func(w http.ResponseWriter, r *http.Request) {
			NewHandler(handlerRepo{findErr: errors.New("boom")}, productVerifier{}).Detail(w, r)
		}, "/v1/products/p-1"},
		{"categories", func(w http.ResponseWriter, r *http.Request) {
			NewHandler(handlerRepo{listErr: errors.New("boom")}, productVerifier{}).Categories(w, r)
		}, "/v1/categories"},
		{"reviews", func(w http.ResponseWriter, r *http.Request) {
			NewHandler(handlerRepo{sectionErr: errors.New("boom")}, productVerifier{}).Reviews(w, r)
		}, "/v1/products/p-1/reviews"},
		{"comments", func(w http.ResponseWriter, r *http.Request) {
			NewHandler(handlerRepo{sectionErr: errors.New("boom")}, productVerifier{}).Comments(w, r)
		}, "/v1/products/p-1/comments"},
		{"stock", func(w http.ResponseWriter, r *http.Request) {
			NewHandler(handlerRepo{sectionErr: errors.New("boom")}, productVerifier{}).Stock(w, r)
		}, "/v1/products/p-1/stock"},
		{"rating", func(w http.ResponseWriter, r *http.Request) {
			NewHandler(handlerRepo{sectionErr: errors.New("boom")}, productVerifier{}).RatingSummary(w, r)
		}, "/v1/products/p-1/rating-summary"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r := httptest.NewRequest(http.MethodGet, tc.path, nil)
			r.Header.Set("Authorization", "Bearer access")
			r.Header.Set("X-Trace-ID", "trace-1234")
			w := httptest.NewRecorder()
			tc.call(w, r)
			if w.Code != http.StatusInternalServerError {
				t.Fatalf("status=%d body=%s", w.Code, w.Body)
			}
		})
	}

	// A nil verifier and a verifier without a subject are both rejected.
	for _, verifier := range []AccessTokenVerifier{nil, productVerifierNoSubject{}} {
		h := NewHandler(handlerRepo{}, verifier)
		r := httptest.NewRequest(http.MethodGet, "/v1/products", nil)
		r.Header.Set("Authorization", "Bearer access")
		w := httptest.NewRecorder()
		h.List(w, r)
		if w.Code != http.StatusUnauthorized {
			t.Fatalf("verifier=%T status=%d", verifier, w.Code)
		}
	}
}

type productVerifierNoSubject struct{}

func (productVerifierNoSubject) Verify(string) (auth.AccessTokenClaims, error) {
	return auth.AccessTokenClaims{}, nil
}
