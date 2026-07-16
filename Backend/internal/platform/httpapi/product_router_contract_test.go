package httpapi

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

type productRoutesSpy struct{ calls []string }

func (s *productRoutesSpy) mark(name string, w http.ResponseWriter) {
	s.calls = append(s.calls, name)
	w.WriteHeader(http.StatusAccepted)
}
func (s *productRoutesSpy) List(w http.ResponseWriter, _ *http.Request) { s.mark("list", w) }
func (s *productRoutesSpy) Categories(w http.ResponseWriter, _ *http.Request) {
	s.mark("categories", w)
}
func (s *productRoutesSpy) Detail(w http.ResponseWriter, _ *http.Request)    { s.mark("detail", w) }
func (s *productRoutesSpy) Reviews(w http.ResponseWriter, _ *http.Request)   { s.mark("reviews", w) }
func (s *productRoutesSpy) Comments(w http.ResponseWriter, _ *http.Request)  { s.mark("comments", w) }
func (s *productRoutesSpy) Stock(w http.ResponseWriter, _ *http.Request)     { s.mark("stock", w) }
func (s *productRoutesSpy) Inventory(w http.ResponseWriter, _ *http.Request) { s.mark("inventory", w) }
func (s *productRoutesSpy) RatingSummary(w http.ResponseWriter, _ *http.Request) {
	s.mark("rating-summary", w)
}

func TestRouterProductRouteContracts(t *testing.T) {
	spy := new(productRoutesSpy)
	router := NewRouter(nil, nil, spy)
	cases := []struct {
		path string
		want string
	}{
		{"/v1/products", "list"},
		{"/v1/categories", "categories"},
		{"/v1/products/p-1", "detail"},
		{"/v1/products/p-1/reviews", "reviews"},
		{"/v1/products/p-1/comments", "comments"},
		{"/v1/products/p-1/stock", "stock"},
		{"/v1/products/p-1/inventory", "inventory"},
		{"/v1/products/p-1/rating-summary", "rating-summary"},
	}
	for _, tc := range cases {
		w := httptest.NewRecorder()
		router.ServeHTTP(w, httptest.NewRequest(http.MethodGet, tc.path, nil))
		if w.Code != http.StatusAccepted {
			t.Fatalf("%s status=%d", tc.path, w.Code)
		}
		if got := spy.calls[len(spy.calls)-1]; got != tc.want {
			t.Fatalf("%s routed to %q, want %q", tc.path, got, tc.want)
		}
	}
}

func TestRouterRejectsUnknownProductRouteShapes(t *testing.T) {
	router := NewRouter(nil, nil, new(productRoutesSpy))
	for _, path := range []string{
		"/v1/products/",
		"/v1/products/p-1/unknown",
		"/v1/products/p-1/reviews/extra",
		"/v1/categories/extra",
	} {
		w := httptest.NewRecorder()
		router.ServeHTTP(w, httptest.NewRequest(http.MethodGet, path, nil))
		if w.Code != http.StatusNotFound {
			t.Fatalf("%s status=%d, want 404", path, w.Code)
		}
	}
}
