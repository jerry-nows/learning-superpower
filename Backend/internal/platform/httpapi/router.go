package httpapi

import (
	"encoding/json"
	"net/http"
)

type AuthRoutes interface {
	Login(http.ResponseWriter, *http.Request)
	Refresh(http.ResponseWriter, *http.Request)
	Logout(http.ResponseWriter, *http.Request)
}

func NewRouter(health http.Handler, auth AuthRoutes) http.Handler {
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
			http.NotFound(w, r)
		}
	})
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
