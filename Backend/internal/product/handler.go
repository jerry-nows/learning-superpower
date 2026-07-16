package product

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"github.com/vominhtri1049/learning-superpower/backend/internal/auth"
)

// AccessTokenVerifier is the authentication boundary shared by catalog routes.
type AccessTokenVerifier interface {
	Verify(string) (auth.AccessTokenClaims, error)
}

// Handler maps catalog reads to stable HTTP contracts.
type Handler struct {
	repository ProductRepository
	verifier   AccessTokenVerifier
}

func NewHandler(repository ProductRepository, verifier AccessTokenVerifier) *Handler {
	return &Handler{repository: repository, verifier: verifier}
}

type productError struct {
	Code      string `json:"code"`
	Message   string `json:"message"`
	Retryable bool   `json:"retryable"`
	TraceID   string `json:"trace_id"`
}

func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	if !h.authorize(w, r) {
		return
	}
	if r.Method != http.MethodGet {
		methodError(w, r)
		return
	}
	query, err := parseProductQuery(r)
	if err != nil {
		writeError(w, r, http.StatusBadRequest, "PRODUCT_INVALID_QUERY", false)
		return
	}
	page, err := h.repository.List(r.Context(), query)
	if err != nil {
		h.repositoryError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, page)
}

func (h *Handler) Detail(w http.ResponseWriter, r *http.Request) {
	if !h.authorize(w, r) {
		return
	}
	if r.Method != http.MethodGet {
		methodError(w, r)
		return
	}
	id, ok := productIDFromPath(r.URL.Path, "")
	if !ok {
		writeError(w, r, http.StatusBadRequest, "PRODUCT_INVALID_ID", false)
		return
	}
	item, err := h.repository.FindByID(r.Context(), ProductID(id))
	if err != nil {
		h.repositoryError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, item)
}

// Reviews serves the reviews section independently from the product detail.
// A failure here only affects this response; callers can still load comments,
// stock, and the product itself through their separate endpoints.
func (h *Handler) Reviews(w http.ResponseWriter, r *http.Request) {
	if !h.authorize(w, r) {
		return
	}
	if r.Method != http.MethodGet {
		methodError(w, r)
		return
	}
	id, ok := productIDFromPath(r.URL.Path, "/reviews")
	if !ok {
		writeError(w, r, http.StatusBadRequest, "PRODUCT_INVALID_ID", false)
		return
	}
	items, err := h.repository.ListReviews(r.Context(), ProductID(id))
	if err != nil {
		h.repositoryError(w, r, err)
		return
	}
	if items == nil {
		items = []Review{}
	}
	writeJSON(w, http.StatusOK, items)
}

// Comments serves the comments section independently from reviews and stock.
func (h *Handler) Comments(w http.ResponseWriter, r *http.Request) {
	if !h.authorize(w, r) {
		return
	}
	if r.Method != http.MethodGet {
		methodError(w, r)
		return
	}
	id, ok := productIDFromPath(r.URL.Path, "/comments")
	if !ok {
		writeError(w, r, http.StatusBadRequest, "PRODUCT_INVALID_ID", false)
		return
	}
	items, err := h.repository.ListComments(r.Context(), ProductID(id))
	if err != nil {
		h.repositoryError(w, r, err)
		return
	}
	if items == nil {
		items = []Comment{}
	}
	writeJSON(w, http.StatusOK, items)
}

// Stock serves the current inventory section independently. The endpoint is
// deliberately read-only; reservation and checkout rules belong elsewhere.
func (h *Handler) Stock(w http.ResponseWriter, r *http.Request) {
	if !h.authorize(w, r) {
		return
	}
	if r.Method != http.MethodGet {
		methodError(w, r)
		return
	}
	id, ok := productIDFromPath(r.URL.Path, "/stock")
	if !ok {
		writeError(w, r, http.StatusBadRequest, "PRODUCT_INVALID_ID", false)
		return
	}
	stock, err := h.repository.GetStock(r.Context(), ProductID(id))
	if err != nil {
		h.repositoryError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, stock)
}

// productIDFromPath validates the exact detail route shape. An empty suffix
// parses /v1/products/{id}; a non-empty suffix parses /v1/products/{id}{suffix}.
func productIDFromPath(path, suffix string) (string, bool) {
	prefix := "/v1/products/"
	if !strings.HasPrefix(path, prefix) {
		return "", false
	}
	value := strings.TrimPrefix(path, prefix)
	if suffix != "" {
		if !strings.HasSuffix(value, suffix) {
			return "", false
		}
		value = strings.TrimSuffix(value, suffix)
	}
	if value == "" || strings.Contains(value, "/") || strings.TrimSpace(value) != value {
		return "", false
	}
	return value, true
}

func (h *Handler) Categories(w http.ResponseWriter, r *http.Request) {
	if !h.authorize(w, r) {
		return
	}
	if r.Method != http.MethodGet {
		methodError(w, r)
		return
	}
	items, err := h.repository.ListCategories(r.Context())
	if err != nil {
		h.repositoryError(w, r, err)
		return
	}
	if items == nil {
		items = []Category{}
	}
	writeJSON(w, http.StatusOK, struct {
		Items []Category `json:"items"`
	}{items})
}

func (h *Handler) authorize(w http.ResponseWriter, r *http.Request) bool {
	parts := strings.Fields(r.Header.Get("Authorization"))
	if h.verifier == nil || len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") || strings.TrimSpace(parts[1]) == "" {
		writeError(w, r, http.StatusUnauthorized, "PRODUCT_UNAUTHORIZED", false)
		return false
	}
	claims, err := h.verifier.Verify(parts[1])
	if err != nil || claims.UserID() == "" {
		writeError(w, r, http.StatusUnauthorized, "PRODUCT_UNAUTHORIZED", false)
		return false
	}
	return true
}

func parseProductQuery(r *http.Request) (ProductQuery, error) {
	values := r.URL.Query()
	query := ProductQuery{Page: DefaultProductPage, PageSize: DefaultProductPageSize, Sort: ProductSortNewest, Search: values.Get("search"), CategoryID: CategoryID(values.Get("category_id"))}
	var err error
	if raw := values.Get("page"); raw != "" {
		query.Page, err = strconv.Atoi(raw)
		if err != nil {
			return ProductQuery{}, ErrInvalidPage
		}
	}
	if raw := values.Get("page_size"); raw != "" {
		query.PageSize, err = strconv.Atoi(raw)
		if err != nil {
			return ProductQuery{}, ErrInvalidPageSize
		}
	}
	if raw := values.Get("sort"); raw != "" {
		query.Sort = ProductSort(raw)
	}
	return query, query.Validate()
}

func (h *Handler) repositoryError(w http.ResponseWriter, r *http.Request, err error) {
	status, code, retry := http.StatusInternalServerError, "PRODUCT_INTERNAL", true
	if errors.Is(err, ErrProductNotFound) || errors.Is(err, ErrCategoryNotFound) {
		status, code, retry = http.StatusNotFound, "PRODUCT_NOT_FOUND", false
	}
	if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
		status, code, retry = http.StatusRequestTimeout, "PRODUCT_TIMEOUT", false
	}
	writeError(w, r, status, code, retry)
}

func methodError(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Allow", http.MethodGet)
	writeError(w, r, http.StatusMethodNotAllowed, "PRODUCT_METHOD_NOT_ALLOWED", false)
}
func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}
func writeError(w http.ResponseWriter, r *http.Request, status int, code string, retry bool) {
	writeJSON(w, status, productError{Code: code, Message: "request failed", Retryable: retry, TraceID: traceID(r)})
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
