package product

import (
	"context"
	"errors"
	"time"
)

// Review is the read model returned by the product detail review section.
// User identity is intentionally represented as an opaque ID; profile data is
// owned by the user module and is not coupled to the catalog boundary.
type Review struct {
	ID        string    `json:"id"`
	ProductID ProductID `json:"product_id"`
	UserID    string    `json:"user_id"`
	Rating    int       `json:"rating"`
	Title     string    `json:"title,omitempty"`
	Body      string    `json:"body"`
	CreatedAt time.Time `json:"created_at"`
}

// Comment is the read model returned by the product detail comment section.
type Comment struct {
	ID        string    `json:"id"`
	ProductID ProductID `json:"product_id"`
	UserID    string    `json:"user_id"`
	Body      string    `json:"body"`
	CreatedAt time.Time `json:"created_at"`
}

// Stock is a point-in-time inventory read model. The repository does not
// reserve inventory; checkout owns those transactional rules.
type Stock struct {
	ProductID ProductID `json:"product_id"`
	Available int       `json:"available"`
	UpdatedAt time.Time `json:"updated_at"`
}

// RatingSummary is the compact aggregate used by the product detail screen.
type RatingSummary struct {
	ProductID     ProductID `json:"product_id"`
	AverageRating float64   `json:"average_rating"`
	ReviewCount   int       `json:"review_count"`
}

var (
	ErrProductNotFound  = errors.New("product not found")
	ErrCategoryNotFound = errors.New("category not found")
)

// ProductRepository is the persistence boundary for the read-only catalog.
// Each detail section has its own method so callers can load and fail sections
// independently (for example, comments may be unavailable while stock loads).
type ProductRepository interface {
	List(context.Context, ProductQuery) (ProductPage, error)
	FindByID(context.Context, ProductID) (Product, error)
	ListCategories(context.Context) ([]Category, error)
	ListReviews(context.Context, ProductID) ([]Review, error)
	ListComments(context.Context, ProductID) ([]Comment, error)
	GetStock(context.Context, ProductID) (Stock, error)
}
