package product

import (
	"context"
	"errors"
	"fmt"
	"reflect"
	"strings"

	"github.com/jackc/pgx/v5"
)

type productRows interface {
	pgx.Rows
}

type productQueryer interface {
	Query(context.Context, string, ...any) (pgx.Rows, error)
	QueryRow(context.Context, string, ...any) pgx.Row
}

// PostgresProductRepository is the PostgreSQL adapter for the catalog read model.
// Values are always passed as query arguments; only the sort expression is selected
// from the fixed allow-list below.
type PostgresProductRepository struct{ db productQueryer }

func NewPostgresProductRepository(db productQueryer) (*PostgresProductRepository, error) {
	if db == nil || (reflect.ValueOf(db).Kind() == reflect.Ptr && reflect.ValueOf(db).IsNil()) {
		return nil, errors.New("product repository database must not be nil")
	}
	return &PostgresProductRepository{db: db}, nil
}

const productColumns = `id, category_id, name, description, price, currency, stock, status, image_url, created_at, updated_at`

var productSortSQL = map[ProductSort]string{
	ProductSortNewest:          "created_at DESC, id DESC",
	ProductSortPriceAscending:  "price ASC, id ASC",
	ProductSortPriceDescending: "price DESC, id DESC",
	ProductSortNameAscending:   "lower(name) ASC, id ASC",
	ProductSortNameDescending:  "lower(name) DESC, id DESC",
}

func (r *PostgresProductRepository) List(ctx context.Context, query ProductQuery) (ProductPage, error) {
	query = query.WithDefaults()
	if err := query.Validate(); err != nil {
		return ProductPage{}, err
	}
	sortExpr, ok := productSortSQL[query.Sort]
	if !ok {
		return ProductPage{}, ErrInvalidSort
	}
	where := []string{"status = 'active'"}
	args := make([]any, 0, 4)
	if query.Search != "" {
		args = append(args, "%"+query.Search+"%")
		where = append(where, fmt.Sprintf("(name ILIKE $%d OR description ILIKE $%d)", len(args), len(args)))
	}
	if query.CategoryID != "" {
		args = append(args, string(query.CategoryID))
		where = append(where, fmt.Sprintf("category_id = $%d", len(args)))
	}
	whereSQL := strings.Join(where, " AND ")
	countSQL := "SELECT count(*) FROM products WHERE " + whereSQL
	var total int
	if err := r.db.QueryRow(ctx, countSQL, args...).Scan(&total); err != nil {
		return ProductPage{}, mapProductRepositoryError(ctx, err)
	}
	page := ProductPage{Items: []Product{}, Page: query.Page, PageSize: query.PageSize, Total: total}
	if total == 0 {
		return page, nil
	}
	offset := int64(query.Page-1) * int64(query.PageSize)
	itemsSQL := "SELECT " + productColumns + " FROM products WHERE " + whereSQL + " ORDER BY " + sortExpr + fmt.Sprintf(" LIMIT $%d OFFSET $%d", len(args)+1, len(args)+2)
	args = append(args, query.PageSize, offset)
	rows, err := r.db.Query(ctx, itemsSQL, args...)
	if err != nil {
		return ProductPage{}, mapProductRepositoryError(ctx, err)
	}
	defer rows.Close()
	for rows.Next() {
		item, scanErr := scanProduct(rows)
		if scanErr != nil {
			return ProductPage{}, mapProductRepositoryError(ctx, scanErr)
		}
		page.Items = append(page.Items, item)
	}
	if err := rows.Err(); err != nil {
		return ProductPage{}, mapProductRepositoryError(ctx, err)
	}
	page.HasNext = query.Page*query.PageSize < total
	return page, nil
}

func (r *PostgresProductRepository) FindByID(ctx context.Context, id ProductID) (Product, error) {
	if strings.TrimSpace(string(id)) == "" {
		return Product{}, ErrProductNotFound
	}
	row := r.db.QueryRow(ctx, "SELECT "+productColumns+" FROM products WHERE id = $1 AND status = 'active'", string(id))
	item, err := scanProduct(row)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Product{}, ErrProductNotFound
		}
		return Product{}, mapProductRepositoryError(ctx, err)
	}
	return item, nil
}

func (r *PostgresProductRepository) ListCategories(ctx context.Context) ([]Category, error) {
	rows, err := r.db.Query(ctx, "SELECT id, name, created_at, updated_at FROM categories ORDER BY lower(name) ASC, id ASC")
	if err != nil {
		return nil, mapProductRepositoryError(ctx, err)
	}
	defer rows.Close()
	categories := make([]Category, 0)
	for rows.Next() {
		var category Category
		if err := rows.Scan(&category.ID, &category.Name, &category.CreatedAt, &category.UpdatedAt); err != nil {
			return nil, mapProductRepositoryError(ctx, err)
		}
		categories = append(categories, category)
	}
	if err := rows.Err(); err != nil {
		return nil, mapProductRepositoryError(ctx, err)
	}
	return categories, nil
}

// Reviews and comments are independent detail sections. Their persistence tables
// are introduced by the detail phase; returning an empty section here keeps the
// catalog adapter usable while preserving section-level failure isolation.
func (r *PostgresProductRepository) ListReviews(context.Context, ProductID) ([]Review, error) {
	return []Review{}, nil
}

func (r *PostgresProductRepository) ListComments(context.Context, ProductID) ([]Comment, error) {
	return []Comment{}, nil
}

func (r *PostgresProductRepository) GetStock(ctx context.Context, id ProductID) (Stock, error) {
	var stock Stock
	var productID string
	err := r.db.QueryRow(ctx, "SELECT id, stock, updated_at FROM products WHERE id = $1 AND status = 'active'", string(id)).Scan(&productID, &stock.Available, &stock.UpdatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Stock{}, ErrProductNotFound
		}
		return Stock{}, mapProductRepositoryError(ctx, err)
	}
	stock.ProductID = ProductID(productID)
	return stock, nil
}

type productScanner interface{ Scan(...any) error }

func scanProduct(row productScanner) (Product, error) {
	var item Product
	err := row.Scan(&item.ID, &item.CategoryID, &item.Name, &item.Description, &item.Price, &item.Currency, &item.Stock, &item.Status, &item.ImageURL, &item.CreatedAt, &item.UpdatedAt)
	return item, err
}

func mapProductRepositoryError(ctx context.Context, err error) error {
	if ctx.Err() != nil {
		return ctx.Err()
	}
	return fmt.Errorf("product repository: %w", err)
}

var _ ProductRepository = (*PostgresProductRepository)(nil)
