package product

import (
	"encoding/json"
	"testing"
)

func TestProductQueryDefaultsAreDeterministic(t *testing.T) {
	query := ProductQuery{}.WithDefaults()
	if query.Page != DefaultProductPage || query.PageSize != DefaultProductPageSize {
		t.Fatalf("defaults = page %d size %d", query.Page, query.PageSize)
	}
	if query.Sort != ProductSortNewest {
		t.Fatalf("sort = %q, want %q", query.Sort, ProductSortNewest)
	}
}

func TestProductQueryRejectsInvalidPageSizes(t *testing.T) {
	for _, size := range []int{0, -1, MaxProductPageSize + 1} {
		if err := (ProductQuery{PageSize: size}).Validate(); err == nil {
			t.Errorf("page size %d was accepted", size)
		}
	}
}

func TestProductSortValuesAreStableJSONStrings(t *testing.T) {
	values := []ProductSort{ProductSortNewest, ProductSortPriceAscending, ProductSortPriceDescending, ProductSortNameAscending, ProductSortNameDescending}
	for _, value := range values {
		encoded, err := json.Marshal(value)
		if err != nil || string(encoded) != `"`+string(value)+`"` {
			t.Fatalf("sort %q encoded as %s (err %v)", value, encoded, err)
		}
	}
}
