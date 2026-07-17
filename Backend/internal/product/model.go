package product

import (
	"errors"
	"strings"
	"time"
)

const (
	DefaultProductPage     = 1
	DefaultProductPageSize = 20
	MaxProductPageSize     = 100
)

var (
	ErrInvalidPage     = errors.New("product page must be greater than zero")
	ErrInvalidPageSize = errors.New("product page size is outside the allowed range")
	ErrInvalidSort     = errors.New("unsupported product sort")
)

type ProductID string
type CategoryID string

type ProductStatus string

const (
	ProductStatusActive   ProductStatus = "active"
	ProductStatusInactive ProductStatus = "inactive"
)

// Product is the transport-safe catalog representation. Price is represented
// in the smallest currency unit to avoid floating-point rounding at boundaries.
type Product struct {
	ID          ProductID     `json:"id"`
	CategoryID  CategoryID    `json:"category_id"`
	Name        string        `json:"name"`
	Description string        `json:"description"`
	Price       int64         `json:"price"`
	Currency    string        `json:"currency"`
	Stock       int           `json:"stock"`
	Status      ProductStatus `json:"status"`
	ImageURL    string        `json:"image_url,omitempty"`
	CreatedAt   time.Time     `json:"created_at"`
	UpdatedAt   time.Time     `json:"updated_at"`
}

type Category struct {
	ID        CategoryID `json:"id"`
	Name      string     `json:"name"`
	CreatedAt time.Time  `json:"created_at"`
	UpdatedAt time.Time  `json:"updated_at"`
}

type ProductSort string

const (
	ProductSortNewest          ProductSort = "newest"
	ProductSortPriceAscending  ProductSort = "price_asc"
	ProductSortPriceDescending ProductSort = "price_desc"
	ProductSortNameAscending   ProductSort = "name_asc"
	ProductSortNameDescending  ProductSort = "name_desc"
)

func (sort ProductSort) Valid() bool {
	switch sort {
	case ProductSortNewest, ProductSortPriceAscending, ProductSortPriceDescending, ProductSortNameAscending, ProductSortNameDescending:
		return true
	default:
		return false
	}
}

type ProductQuery struct {
	Page       int         `json:"page"`
	PageSize   int         `json:"page_size"`
	Search     string      `json:"search,omitempty"`
	CategoryID CategoryID  `json:"category_id,omitempty"`
	Sort       ProductSort `json:"sort"`
}

func (query ProductQuery) WithDefaults() ProductQuery {
	if query.Page <= 0 {
		query.Page = DefaultProductPage
	}
	if query.PageSize <= 0 {
		query.PageSize = DefaultProductPageSize
	}
	if query.Sort == "" {
		query.Sort = ProductSortNewest
	}
	query.Search = strings.TrimSpace(query.Search)
	return query
}

func (query ProductQuery) Validate() error {
	if query.Page <= 0 {
		return ErrInvalidPage
	}
	if query.PageSize <= 0 || query.PageSize > MaxProductPageSize {
		return ErrInvalidPageSize
	}
	if query.Sort != "" && !query.Sort.Valid() {
		return ErrInvalidSort
	}
	return nil
}

type ProductPage struct {
	Items    []Product `json:"items"`
	Page     int       `json:"page"`
	PageSize int       `json:"page_size"`
	Total    int       `json:"total"`
	HasNext  bool      `json:"has_next"`
}
