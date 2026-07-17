-- +goose Up
CREATE TABLE categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    slug TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT categories_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT categories_slug_not_blank CHECK (btrim(slug) <> '')
);

CREATE UNIQUE INDEX categories_slug_unique_idx ON categories (slug);

CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id UUID NOT NULL,
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    price BIGINT NOT NULL,
    currency TEXT NOT NULL DEFAULT 'VND',
    stock INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'active',
    image_url TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT products_category_fk FOREIGN KEY (category_id) REFERENCES categories (id) ON DELETE RESTRICT,
    CONSTRAINT products_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT products_price_non_negative CHECK (price >= 0),
    CONSTRAINT products_stock_non_negative CHECK (stock >= 0),
    CONSTRAINT products_status_check CHECK (status IN ('active', 'inactive')),
    CONSTRAINT products_currency_not_blank CHECK (btrim(currency) <> '')
);

CREATE INDEX products_category_idx ON products (category_id);
CREATE INDEX products_status_idx ON products (status);
CREATE INDEX products_created_at_idx ON products (created_at DESC);
CREATE INDEX products_name_search_idx ON products (lower(name));

-- +goose Down
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS categories;
