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
	login  func(context.Context, string, string) (User, TokenPair, error)
	logout func(context.Context, UserID) error
}

func (s handlerService) Login(c context.Context, e, p string) (User, TokenPair, error) {
	return s.login(c, e, p)
}
func (s handlerService) Refresh(context.Context, string) (User, TokenPair, error) {
	return User{}, TokenPair{}, nil
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
