package api

import (
	"os"
	"strings"
	"testing"

	"gopkg.in/yaml.v3"
)

func TestAuthenticationOpenAPIContract(t *testing.T) {
	data, err := os.ReadFile("openapi.yaml")
	if err != nil {
		t.Fatalf("read OpenAPI contract: %v", err)
	}
	if strings.Contains(strings.ToLower(string(data)), "password123") || strings.Contains(strings.ToLower(string(data)), "postgres://") {
		t.Fatal("OpenAPI examples must not contain real credentials or DSNs")
	}
	var doc struct {
		OpenAPI    string                    `yaml:"openapi"`
		Paths      map[string]map[string]any `yaml:"paths"`
		Components struct {
			Schemas map[string]any `yaml:"schemas"`
		} `yaml:"components"`
	}
	var root yaml.Node
	if err := yaml.Unmarshal(data, &root); err != nil {
		t.Fatalf("parse OpenAPI YAML node tree: %v", err)
	}
	if duplicate := duplicateMappingKey(&root); duplicate != "" {
		t.Fatalf("duplicate OpenAPI mapping key %q", duplicate)
	}
	if err := yaml.Unmarshal(data, &doc); err != nil {
		t.Fatalf("parse OpenAPI YAML: %v", err)
	}
	if doc.OpenAPI != "3.1.0" && doc.OpenAPI != "3.0.3" {
		t.Fatalf("unsupported OpenAPI version %q", doc.OpenAPI)
	}
	for _, path := range []string{"/v1/auth/login", "/v1/auth/refresh", "/v1/auth/logout"} {
		if _, ok := doc.Paths[path]; !ok {
			t.Fatalf("missing auth path %s", path)
		}
		if _, ok := doc.Paths[path]["post"]; !ok {
			t.Fatalf("auth path %s must define POST", path)
		}
	}
	for _, schema := range []string{"AuthResponse", "User", "Tokens", "ErrorResponse"} {
		if _, ok := doc.Components.Schemas[schema]; !ok {
			t.Fatalf("missing schema %s", schema)
		}
	}
	for _, field := range []string{"access_token", "refresh_token", "access_expires_at", "refresh_expires_at"} {
		if !strings.Contains(string(data), field) {
			t.Fatalf("contract missing token field %s", field)
		}
	}
	description := strings.ToLower(string(data))
	if !strings.Contains(description, "60 seconds") || !strings.Contains(description, "256-bit") || !strings.Contains(description, "bearer") {
		t.Fatal("contract must document token lifetime, opaque 256-bit refresh token and bearer logout")
	}
}

func duplicateMappingKey(node *yaml.Node) string {
	if node == nil {
		return ""
	}
	if node.Kind == yaml.MappingNode {
		seen := make(map[string]struct{}, len(node.Content)/2)
		for i := 0; i+1 < len(node.Content); i += 2 {
			key := node.Content[i].Value
			if _, ok := seen[key]; ok {
				return key
			}
			seen[key] = struct{}{}
		}
	}
	for _, child := range node.Content {
		if duplicate := duplicateMappingKey(child); duplicate != "" {
			return duplicate
		}
	}
	return ""
}
