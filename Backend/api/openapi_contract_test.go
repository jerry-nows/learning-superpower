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
			Schemas   map[string]any `yaml:"schemas"`
			Responses map[string]any `yaml:"responses"`
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
		operation, ok := doc.Paths[path]
		if !ok {
			t.Fatalf("missing auth path %s", path)
		}
		post, ok := operation["post"].(map[string]any)
		if !ok {
			t.Fatalf("auth path %s must define POST", path)
		}
		for method := range operation {
			if method != "post" {
				t.Fatalf("auth path %s has undocumented method %s", path, method)
			}
		}
		responses, ok := post["responses"].(map[string]any)
		if !ok {
			t.Fatalf("auth path %s has no responses", path)
		}
		for _, status := range []string{"405", "500"} {
			if _, ok := responses[status]; !ok {
				t.Fatalf("auth path %s missing %s response", path, status)
			}
		}
		if _, forbidden := responses["503"]; forbidden {
			t.Fatalf("auth path %s must not advertise unsupported 503", path)
		}
		if path == "/v1/auth/logout" {
			if _, ok := post["security"]; !ok {
				t.Fatal("logout must require bearer security")
			}
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
	for _, ref := range refs(&root) {
		parts := strings.Split(strings.TrimPrefix(ref, "#/components/"), "/")
		if len(parts) != 2 || (parts[0] != "schemas" && parts[0] != "responses") {
			t.Fatalf("unsupported or unresolved OpenAPI ref %q", ref)
		}
		if parts[0] == "schemas" {
			if _, ok := doc.Components.Schemas[parts[1]]; !ok {
				t.Fatalf("unresolved schema ref %q", ref)
			}
		} else if _, ok := doc.Components.Responses[parts[1]]; !ok {
			t.Fatalf("unresolved response ref %q", ref)
		}
	}
}

func refs(node *yaml.Node) []string {
	var out []string
	if node == nil {
		return out
	}
	if node.Kind == yaml.ScalarNode && node.Tag == "!!str" && strings.HasPrefix(node.Value, "#/") {
		out = append(out, node.Value)
	}
	for _, child := range node.Content {
		out = append(out, refs(child)...)
	}
	return out
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
