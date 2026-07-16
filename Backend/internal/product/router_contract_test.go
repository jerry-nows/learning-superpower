package product

import (
	"net/http"
	"testing"
)

// Keep the product transport surface explicit so the API composition root can
// wire all catalog sections without reaching into implementation details.
type productRouterContract interface {
	List(http.ResponseWriter, *http.Request)
	Categories(http.ResponseWriter, *http.Request)
	Detail(http.ResponseWriter, *http.Request)
	Reviews(http.ResponseWriter, *http.Request)
	Comments(http.ResponseWriter, *http.Request)
	Stock(http.ResponseWriter, *http.Request)
	Inventory(http.ResponseWriter, *http.Request)
	RatingSummary(http.ResponseWriter, *http.Request)
}

func TestProductHandlerSatisfiesRouterContract(t *testing.T) {
	var _ productRouterContract = (*Handler)(nil)
}
