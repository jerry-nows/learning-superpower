package auth

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"mime"
	"net/http"
	"strings"
)

const maxAuthBody = 16 << 10

// AuthService is the application boundary used by the HTTP transport.
type AuthService interface {
	Login(ctx context.Context, email, password string) (User, TokenPair, error)
	Refresh(ctx context.Context, opaque string) (User, TokenPair, error)
	Logout(ctx context.Context, userID UserID) error
}

// AccessTokenVerifier validates an access bearer token and its registered claims.
type AccessTokenVerifier interface {
	Verify(string) (AccessTokenClaims, error)
}

// Handler maps authentication application calls to stable HTTP contracts.
type Handler struct {
	service  AuthService
	verifier AccessTokenVerifier
}

func NewHandler(service AuthService, verifier AccessTokenVerifier) *Handler {
	return &Handler{service: service, verifier: verifier}
}

type loginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}
type refreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}
type userResponse struct {
	ID     UserID     `json:"id"`
	Email  string     `json:"email,omitempty"`
	Status UserStatus `json:"status"`
}
type tokenResponse struct {
	AccessToken      string `json:"access_token"`
	RefreshToken     string `json:"refresh_token"`
	AccessExpiresAt  string `json:"access_expires_at"`
	RefreshExpiresAt string `json:"refresh_expires_at"`
}
type authResponse struct {
	User   userResponse  `json:"user"`
	Tokens tokenResponse `json:"tokens"`
}
type errorResponse struct {
	Code      string `json:"code"`
	Message   string `json:"message"`
	Retryable bool   `json:"retryable"`
	TraceID   string `json:"trace_id"`
}

func (h *Handler) Login(w http.ResponseWriter, r *http.Request)   { h.login(w, r) }
func (h *Handler) Refresh(w http.ResponseWriter, r *http.Request) { h.refresh(w, r) }
func (h *Handler) Logout(w http.ResponseWriter, r *http.Request)  { h.logout(w, r) }

func (h *Handler) login(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodError(w, r, http.MethodPost)
		return
	}
	var in loginRequest
	if !readJSON(w, r, &in) || strings.TrimSpace(in.Email) == "" || in.Password == "" {
		writeError(w, r, http.StatusBadRequest, "AUTH_INVALID_REQUEST", false)
		return
	}
	u, t, err := h.service.Login(r.Context(), in.Email, in.Password)
	if err != nil {
		h.serviceError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, authResponse{toUser(u), toTokens(t)})
}
func (h *Handler) refresh(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodError(w, r, http.MethodPost)
		return
	}
	var in refreshRequest
	if !readJSON(w, r, &in) || strings.TrimSpace(in.RefreshToken) == "" {
		writeError(w, r, http.StatusBadRequest, "AUTH_INVALID_REQUEST", false)
		return
	}
	u, t, err := h.service.Refresh(r.Context(), in.RefreshToken)
	if err != nil {
		h.serviceError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, authResponse{toUser(u), toTokens(t)})
}
func (h *Handler) logout(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodError(w, r, http.MethodPost)
		return
	}
	parts := strings.Fields(r.Header.Get("Authorization"))
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") || parts[1] == "" || h.verifier == nil {
		writeError(w, r, http.StatusUnauthorized, "AUTH_UNAUTHORIZED", false)
		return
	}
	claims, err := h.verifier.Verify(parts[1])
	if err != nil || claims.UserID() == "" {
		writeError(w, r, http.StatusUnauthorized, "AUTH_UNAUTHORIZED", false)
		return
	}
	if err = h.service.Logout(r.Context(), claims.UserID()); err != nil {
		h.serviceError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func toUser(u User) userResponse { return userResponse{ID: u.ID, Email: u.Email, Status: u.Status} }
func toTokens(t TokenPair) tokenResponse {
	return tokenResponse{AccessToken: t.AccessToken, RefreshToken: t.RefreshToken, AccessExpiresAt: t.AccessExpiresAt.UTC().Format("2006-01-02T15:04:05Z07:00"), RefreshExpiresAt: t.RefreshExpiresAt.UTC().Format("2006-01-02T15:04:05Z07:00")}
}
func readJSON(w http.ResponseWriter, r *http.Request, dst any) bool {
	mediaType, params, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
	if err != nil || mediaType != "application/json" || (params["charset"] != "" && !strings.EqualFold(params["charset"], "utf-8")) {
		return false
	}
	body := http.MaxBytesReader(w, r.Body, maxAuthBody)
	dec := json.NewDecoder(body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		return false
	}
	var extra any
	if err := dec.Decode(&extra); err != io.EOF {
		return false
	}
	return true
}
func methodError(w http.ResponseWriter, r *http.Request, allow string) {
	w.Header().Set("Allow", allow)
	writeError(w, r, http.StatusMethodNotAllowed, "AUTH_METHOD_NOT_ALLOWED", false)
}
func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
func traceID(r *http.Request) string {
	id := r.Header.Get("X-Trace-ID")
	if len(id) >= 8 && len(id) <= 128 && strings.TrimSpace(id) == id {
		return id
	}
	b := make([]byte, 12)
	if _, err := rand.Read(b); err != nil {
		return "unknown"
	}
	return base64.RawURLEncoding.EncodeToString(b)
}
func writeError(w http.ResponseWriter, r *http.Request, status int, code string, retry bool) {
	writeJSON(w, status, errorResponse{Code: code, Message: "request failed", Retryable: retry, TraceID: traceID(r)})
}
func (h *Handler) serviceError(w http.ResponseWriter, r *http.Request, err error) {
	status, code, retry := http.StatusInternalServerError, "AUTH_INTERNAL", false
	var se *ServiceError
	if errors.As(err, &se) {
		code = "AUTH_" + strings.ToUpper(se.Code)
		retry = se.Retryable
		switch se.Code {
		case "authentication_failed", "refresh_rejected":
			status = http.StatusUnauthorized
		case "authentication_cancelled", "refresh_cancelled", "logout_cancelled", "token_issue_cancelled":
			status = http.StatusRequestTimeout
		case "repository_failed", "token_issue_failed":
			status = http.StatusInternalServerError
		case "logout_failed":
			status = http.StatusInternalServerError
		}
		if errors.Is(se, context.Canceled) || errors.Is(se, context.DeadlineExceeded) {
			status = http.StatusRequestTimeout
			retry = false
		}
	}
	writeError(w, r, status, code, retry)
}
