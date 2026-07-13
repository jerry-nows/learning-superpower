package auth

import (
	"context"
	"encoding/json"
	"github.com/golang-jwt/jwt/v5"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

type handlerService struct {
	login   func(context.Context, string, string) (User, TokenPair, error)
	refresh func(context.Context, string) (User, TokenPair, error)
	logout  func(context.Context, UserID) error
}

func (s handlerService) Login(c context.Context, e, p string) (User, TokenPair, error) {
	return s.login(c, e, p)
}
func (s handlerService) Refresh(c context.Context, token string) (User, TokenPair, error) {
	if s.refresh != nil {
		return s.refresh(c, token)
	}
	return User{}, TokenPair{}, nil
}

func TestHandlerRefreshStrictContentTypeAndServiceError(t *testing.T) {
	h := NewHandler(handlerService{refresh: func(context.Context, string) (User, TokenPair, error) {
		return User{}, TokenPair{}, &ServiceError{Code: "repository_failed", Retryable: true, cause: ErrRepository}
	}}, nil)
	for _, contentType := range []string{"application/json-malicious", "text/plain", ""} {
		r := httptest.NewRequest(http.MethodPost, "/refresh", strings.NewReader(`{"refresh_token":"opaque"}`))
		r.Header.Set("Content-Type", contentType)
		w := httptest.NewRecorder()
		h.Refresh(w, r)
		if w.Code != http.StatusBadRequest {
			t.Fatalf("content type %q status=%d", contentType, w.Code)
		}
	}
	r := httptest.NewRequest(http.MethodPost, "/refresh", strings.NewReader(`{"refresh_token":"opaque"}`))
	r.Header.Set("Content-Type", "application/json; charset=utf-8")
	r.Header.Set("X-Trace-ID", "trace-1234")
	w := httptest.NewRecorder()
	h.Refresh(w, r)
	if w.Code != http.StatusInternalServerError || !strings.Contains(w.Body.String(), `"retryable":true`) || !strings.Contains(w.Body.String(), `"trace_id":"trace-1234"`) || strings.Contains(w.Body.String(), "repository") {
		t.Fatalf("error response=%s", w.Body)
	}
}

func TestHandlerMethodErrorHasStableEnvelopeAndAllow(t *testing.T) {
	h := NewHandler(handlerService{}, nil)
	r := httptest.NewRequest(http.MethodGet, "/login", nil)
	r.Header.Set("X-Trace-ID", "trace-method")
	w := httptest.NewRecorder()
	h.Login(w, r)
	if w.Code != http.StatusMethodNotAllowed || w.Header().Get("Allow") != http.MethodPost || !strings.Contains(w.Body.String(), `"code":"AUTH_METHOD_NOT_ALLOWED"`) || !strings.Contains(w.Body.String(), `"trace_id":"trace-method"`) {
		t.Fatalf("status=%d headers=%v body=%s", w.Code, w.Header(), w.Body)
	}
}

func TestHandlerRejectsTrailingAndOversizedJSON(t *testing.T) {
	h := NewHandler(handlerService{login: func(context.Context, string, string) (User, TokenPair, error) { return User{}, TokenPair{}, nil }}, nil)
	for _, body := range []string{`{"email":"a","password":"p"}{}`, `{"email":"a","password":"` + strings.Repeat("x", maxAuthBody) + `"}`} {
		r := httptest.NewRequest(http.MethodPost, "/login", strings.NewReader(body))
		r.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		h.Login(w, r)
		if w.Code != http.StatusBadRequest {
			t.Fatalf("body status=%d", w.Code)
		}
	}
}

func TestHandlerMapsCancellationToNonRetryableTimeout(t *testing.T) {
	h := NewHandler(handlerService{login: func(context.Context, string, string) (User, TokenPair, error) {
		return User{}, TokenPair{}, &ServiceError{Code: "token_issue_cancelled", Retryable: true, cause: context.Canceled}
	}}, nil)
	r := httptest.NewRequest(http.MethodPost, "/login", strings.NewReader(`{"email":"a","password":"p"}`))
	r.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	h.Login(w, r)
	if w.Code != http.StatusRequestTimeout || strings.Contains(w.Body.String(), "context") || strings.Contains(w.Body.String(), "cancel") || strings.Contains(w.Body.String(), `"retryable":true`) {
		t.Fatalf("response=%s", w.Body)
	}
}
func (s handlerService) Logout(c context.Context, id UserID) error {
	if s.logout != nil {
		return s.logout(c, id)
	}
	return nil
}

type handlerVerifier struct{}

func (handlerVerifier) Verify(string) (AccessTokenClaims, error) {
	return AccessTokenClaims{RegisteredClaims: jwtClaims("u-1")}, nil
}
func jwtClaims(subject string) jwt.RegisteredClaims { return jwt.RegisteredClaims{Subject: subject} }

func TestHandlerLoginMapsSafeDTOAndRejectsUnknownFields(t *testing.T) {
	h := NewHandler(handlerService{login: func(context.Context, string, string) (User, TokenPair, error) {
		return User{ID: "u-1", Email: "a@example.com", Status: UserStatusActive}, TokenPair{AccessToken: "access-secret", RefreshToken: "refresh-secret", AccessExpiresAt: time.Unix(1, 0), RefreshExpiresAt: time.Unix(2, 0)}, nil
	}}, nil)
	r := httptest.NewRequest(http.MethodPost, "/login", strings.NewReader(`{"email":"a@example.com","password":"pw"}`))
	r.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	h.Login(w, r)
	if w.Code != http.StatusOK || strings.Contains(w.Body.String(), "password") {
		t.Fatalf("status/body: %d %s", w.Code, w.Body)
	}
	var got authResponse
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil || got.Tokens.AccessToken != "access-secret" {
		t.Fatalf("dto: %#v %v", got, err)
	}
	r = httptest.NewRequest(http.MethodPost, "/login", strings.NewReader(`{"email":"a","password":"p","extra":1}`))
	r.Header.Set("Content-Type", "application/json")
	w = httptest.NewRecorder()
	h.Login(w, r)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("unknown status=%d", w.Code)
	}
}

func TestHandlerLogoutRequiresBearerAndUsesClaims(t *testing.T) {
	called := false
	h := NewHandler(handlerService{login: func(context.Context, string, string) (User, TokenPair, error) { return User{}, TokenPair{}, nil }, logout: func(c context.Context, id UserID) error { called = id == "u-1"; return nil }}, handlerVerifier{})
	r := httptest.NewRequest(http.MethodPost, "/logout", nil)
	w := httptest.NewRecorder()
	h.Logout(w, r)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("status=%d", w.Code)
	}
	r = httptest.NewRequest(http.MethodPost, "/logout", nil)
	r.Header.Set("Authorization", "Bearer token")
	w = httptest.NewRecorder()
	h.Logout(w, r)
	if w.Code != http.StatusNoContent || !called {
		t.Fatalf("status=%d called=%v", w.Code, called)
	}
}
