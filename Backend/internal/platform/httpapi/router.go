package httpapi

import (
	"encoding/json"
	"net/http"
	"strings"
)

type AuthRoutes interface {
	Login(http.ResponseWriter, *http.Request)
	Refresh(http.ResponseWriter, *http.Request)
	Logout(http.ResponseWriter, *http.Request)
}

// ProductRoutes is the transport boundary for the authenticated catalog API.
// The concrete product handler performs bearer-token verification before each
// operation; keeping that boundary here prevents the composition root from
// coupling to the product package.
type ProductRoutes interface {
	List(http.ResponseWriter, *http.Request)
	Categories(http.ResponseWriter, *http.Request)
	Detail(http.ResponseWriter, *http.Request)
	Reviews(http.ResponseWriter, *http.Request)
	Comments(http.ResponseWriter, *http.Request)
	Stock(http.ResponseWriter, *http.Request)
	Inventory(http.ResponseWriter, *http.Request)
	RatingSummary(http.ResponseWriter, *http.Request)
}

// NewRouter accepts product routes as an optional argument to preserve the
// existing health/auth composition contract for callers that only expose auth.
func NewRouter(health http.Handler, auth AuthRoutes, products ...ProductRoutes) http.Handler {
	var product ProductRoutes
	if len(products) > 0 {
		product = products[0]
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/healthz":
			if r.Method != http.MethodGet {
				w.Header().Set("Allow", http.MethodGet)
				writeError(w, http.StatusMethodNotAllowed, "AUTH_METHOD_NOT_ALLOWED")
				return
			}
			if health == nil {
				http.NotFound(w, r)
				return
			}
			health.ServeHTTP(w, r)
		case "/v1/auth/login":
			routeAuth(w, r, auth, http.MethodPost, func(a AuthRoutes, w http.ResponseWriter, r *http.Request) { a.Login(w, r) })
		case "/v1/auth/refresh":
			routeAuth(w, r, auth, http.MethodPost, func(a AuthRoutes, w http.ResponseWriter, r *http.Request) { a.Refresh(w, r) })
		case "/v1/auth/logout":
			routeAuth(w, r, auth, http.MethodPost, func(a AuthRoutes, w http.ResponseWriter, r *http.Request) { a.Logout(w, r) })
		default:
			routeProduct(w, r, product)
		}
	})
}

func routeProduct(w http.ResponseWriter, r *http.Request, product ProductRoutes) {
	if product == nil {
		http.NotFound(w, r)
		return
	}
	switch r.URL.Path {
	case "/v1/products":
		product.List(w, r)
		return
	case "/v1/categories":
		product.Categories(w, r)
		return
	}
	const prefix = "/v1/products/"
	if !strings.HasPrefix(r.URL.Path, prefix) {
		http.NotFound(w, r)
		return
	}
	value := strings.TrimPrefix(r.URL.Path, prefix)
	parts := strings.Split(value, "/")
	if len(parts) == 1 && parts[0] != "" {
		product.Detail(w, r)
		return
	}
	if len(parts) != 2 || parts[0] == "" {
		http.NotFound(w, r)
		return
	}
	switch parts[1] {
	case "reviews":
		product.Reviews(w, r)
	case "comments":
		product.Comments(w, r)
	case "stock":
		product.Stock(w, r)
	case "inventory":
		product.Inventory(w, r)
	case "rating-summary":
		product.RatingSummary(w, r)
	default:
		http.NotFound(w, r)
	}
}

func routeAuth(w http.ResponseWriter, r *http.Request, auth AuthRoutes, method string, route func(AuthRoutes, http.ResponseWriter, *http.Request)) {
	if r.Method != method {
		w.Header().Set("Allow", method)
		writeError(w, http.StatusMethodNotAllowed, "AUTH_METHOD_NOT_ALLOWED")
		return
	}
	if auth == nil {
		writeError(w, http.StatusInternalServerError, "AUTH_INTERNAL")
		return
	}
	route(auth, w, r)
}

func writeError(w http.ResponseWriter, status int, code string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(struct {
		Code string `json:"code"`
	}{Code: code})
}
