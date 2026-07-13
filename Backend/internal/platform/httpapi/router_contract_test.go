package httpapi

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

type authRoutesSpy struct{ login, refresh, logout int }

func (s *authRoutesSpy) Login(w http.ResponseWriter, r *http.Request) {
	s.login++
	w.Header().Set("Content-Type", "application/json")
	_, _ = w.Write([]byte(`{"route":"login"}`))
}
func (s *authRoutesSpy) Refresh(w http.ResponseWriter, r *http.Request) {
	s.refresh++
	w.Header().Set("Content-Type", "application/json")
	_, _ = w.Write([]byte(`{"route":"refresh"}`))
}
func (s *authRoutesSpy) Logout(w http.ResponseWriter, r *http.Request) {
	s.logout++
	w.WriteHeader(http.StatusNoContent)
}

func TestRouterComposesHealthAndAuthRoutes(t *testing.T) {
	spy := new(authRoutesSpy)
	router := NewRouter(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"status":"ok"}`))
	}), spy)
	for _, tc := range []struct{ path, want string }{{"/v1/auth/login", "login"}, {"/v1/auth/refresh", "refresh"}} {
		w := httptest.NewRecorder()
		router.ServeHTTP(w, httptest.NewRequest(http.MethodPost, tc.path, strings.NewReader(`{}`)))
		if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"route":"`+tc.want+`"`) {
			t.Fatalf("%s: status=%d body=%s", tc.path, w.Code, w.Body.String())
		}
	}
	w := httptest.NewRecorder()
	router.ServeHTTP(w, httptest.NewRequest(http.MethodPost, "/v1/auth/logout", nil))
	if w.Code != http.StatusNoContent || spy.logout != 1 {
		t.Fatalf("logout status=%d calls=%d", w.Code, spy.logout)
	}
	w = httptest.NewRecorder()
	router.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"status":"ok"`) {
		t.Fatalf("health status=%d body=%s", w.Code, w.Body.String())
	}
}

func TestRouterRejectsWrongMethodsAndUnknownOrTrailingRoutes(t *testing.T) {
	router := NewRouter(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) }), new(authRoutesSpy))
	for _, tc := range []struct{ method, path, allow string }{{http.MethodGet, "/v1/auth/login", http.MethodPost}, {http.MethodGet, "/v1/auth/refresh", http.MethodPost}, {http.MethodGet, "/v1/auth/logout", http.MethodPost}} {
		w := httptest.NewRecorder()
		router.ServeHTTP(w, httptest.NewRequest(tc.method, tc.path, nil))
		if w.Code != http.StatusMethodNotAllowed || w.Header().Get("Allow") != tc.allow || w.Header().Get("Content-Type") != "application/json" {
			t.Fatalf("%s %s: status=%d allow=%q content-type=%q", tc.method, tc.path, w.Code, w.Header().Get("Allow"), w.Header().Get("Content-Type"))
		}
	}
	for _, path := range []string{"/v1/auth/login/", "/v1/auth/login/extra", "/v1/auth", "/v1/authentication/login", "/unknown"} {
		w := httptest.NewRecorder()
		router.ServeHTTP(w, httptest.NewRequest(http.MethodPost, path, nil))
		if w.Code != http.StatusNotFound {
			t.Fatalf("%s: status=%d", path, w.Code)
		}
	}
}

func TestRouterHealthRejectsWrongMethodsAtBoundary(t *testing.T) {
	router := NewRouter(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Fatalf("health handler must not receive %s", r.Method)
	}), new(authRoutesSpy))
	for _, method := range []string{http.MethodPost, http.MethodPut} {
		w := httptest.NewRecorder()
		router.ServeHTTP(w, httptest.NewRequest(method, "/healthz", nil))
		if w.Code != http.StatusMethodNotAllowed || w.Header().Get("Allow") != http.MethodGet || w.Header().Get("Content-Type") != "application/json" || !strings.Contains(w.Body.String(), `"code":"AUTH_METHOD_NOT_ALLOWED"`) {
			t.Fatalf("%s /healthz: status=%d allow=%q content-type=%q body=%s", method, w.Code, w.Header().Get("Allow"), w.Header().Get("Content-Type"), w.Body.String())
		}
	}
}

func TestRouterNilAuthDoesNotPanic(t *testing.T) {
	router := NewRouter(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) }), nil)
	for _, path := range []string{"/v1/auth/login", "/v1/auth/refresh", "/v1/auth/logout"} {
		w := httptest.NewRecorder()
		router.ServeHTTP(w, httptest.NewRequest(http.MethodPost, path, nil))
		if w.Code != http.StatusServiceUnavailable || w.Header().Get("Content-Type") != "application/json" {
			t.Fatalf("%s: status=%d content-type=%q", path, w.Code, w.Header().Get("Content-Type"))
		}
	}
}
