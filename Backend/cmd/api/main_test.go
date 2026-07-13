package main

import (
	"strings"
	"testing"
)

func TestParseAPIConfigRequiresSecretsAndUsesSafeDefaults(t *testing.T) {
	env := map[string]string{"DATABASE_URL": "postgres://db", "REDIS_URL": "redis://localhost", "JWT_SIGNING_KEY": "01234567890123456789012345678901", "JWT_ISSUER": "local", "JWT_AUDIENCE": "ios"}
	c, err := parseAPIConfig(func(k string) string { return env[k] })
	if err != nil {
		t.Fatalf("parse config: %v", err)
	}
	if c.port != "8080" || c.migrationsDir != "migrations" {
		t.Fatalf("unsafe defaults: %#v", c)
	}
}

func TestParseAPIConfigRejectsShortSigningKey(t *testing.T) {
	env := map[string]string{"DATABASE_URL": "postgres://db", "REDIS_URL": "redis://localhost", "JWT_SIGNING_KEY": "short", "JWT_ISSUER": "local", "JWT_AUDIENCE": "ios"}
	if _, err := parseAPIConfig(func(k string) string { return env[k] }); err == nil {
		t.Fatal("expected short JWT signing key to be rejected")
	}
}

func TestParseAPIConfigDoesNotExposeValuesInError(t *testing.T) {
	env := map[string]string{"DATABASE_URL": "postgres://dsn-secret", "JWT_SIGNING_KEY": "short", "JWT_ISSUER": "issuer-secret", "JWT_AUDIENCE": "audience-secret"}
	_, err := parseAPIConfig(func(k string) string { return env[k] })
	if err == nil {
		t.Fatal("expected invalid config")
	}
	for _, secret := range []string{"dsn-secret", "issuer-secret", "audience-secret"} {
		if strings.Contains(err.Error(), secret) {
			t.Fatalf("error leaked %q", secret)
		}
	}
}
