package api

import (
	"os"
	"regexp"
	"strings"
	"testing"

	"gopkg.in/yaml.v3"
)

func TestAuthenticationOpenAPIContract(t *testing.T) {
	data, err := os.ReadFile("openapi.yaml")
	if err != nil {
		t.Fatalf("read OpenAPI contract: %v", err)
	}
	assertNoSecrets(t, string(data))
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
		want := []string{"400", "401", "405", "408", "500"}
		if path == "/v1/auth/logout" {
			want = []string{"204", "401", "405", "408", "500"}
		} else {
			want = append([]string{"200"}, want...)
		}
		if len(responses) != len(want) {
			t.Fatalf("auth path %s response set mismatch: got %v want %v", path, mapKeys(responses), want)
		}
		for _, status := range want {
			if _, ok := responses[status]; !ok {
				t.Fatalf("auth path %s missing exact response %s", path, status)
			}
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

func mapKeys(values map[string]any) []string {
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	return keys
}

func assertNoSecrets(t *testing.T, document string) {
	t.Helper()
	for _, pattern := range []*regexp.Regexp{
		regexp.MustCompile(`-----BEGIN [A-Z0-9 ]+-----`),
		regexp.MustCompile(`[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}`),
		regexp.MustCompile(`(?i)(postgres(?:ql)?|mysql|redis|mongodb)(?:\+[^:]*)?://`),
	} {
		if pattern.MatchString(document) {
			t.Fatalf("OpenAPI examples contain a secret-like value matching %s", pattern)
		}
	}
	assignment := regexp.MustCompile(`(?im)^\s*(password|refresh_token|access_token|secret|api[_-]?key|private[_-]?key)\s*:\s*['"]?([^\s,'"{}]+)`)
	for _, match := range assignment.FindAllStringSubmatch(document, -1) {
		value := strings.ToLower(match[2])
		if strings.HasPrefix(value, "<redacted") || strings.HasPrefix(value, "<opaque") || strings.HasPrefix(value, "<trace") || value == "type" {
			continue
		}
		if len(value) >= 8 || value == "password" || value == "token" || value == "secret" {
			t.Fatalf("OpenAPI secret field %q contains non-redacted example", match[1])
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
