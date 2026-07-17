package backend_test

import (
	"encoding/json"
	"os/exec"
	"testing"

	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v5"
	"github.com/pressly/goose/v3"
	redis "github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/assert"
	"github.com/testcontainers/testcontainers-go"
	postgrescontainer "github.com/testcontainers/testcontainers-go/modules/postgres"
	rediscontainer "github.com/testcontainers/testcontainers-go/modules/redis"
	"golang.org/x/crypto/bcrypt"
)

var dependencyCompileContract = []any{
	(*pgx.Conn)(nil),
	(*redis.Client)(nil),
	goose.Up,
	jwt.New,
	assert.Equal,
	(*testcontainers.Container)(nil),
	postgrescontainer.Run,
	rediscontainer.Run,
	bcrypt.GenerateFromPassword,
}

func TestAuthenticationDependenciesArePinnedAsDirectRequirements(t *testing.T) {
	want := map[string]string{
		"github.com/golang-jwt/jwt/v5":                                 "v5.3.1",
		"github.com/jackc/pgx/v5":                                      "v5.10.0",
		"github.com/pressly/goose/v3":                                  "v3.27.2",
		"github.com/redis/go-redis/v9":                                 "v9.21.0",
		"github.com/stretchr/testify":                                  "v1.11.1",
		"github.com/testcontainers/testcontainers-go":                  "v0.43.0",
		"github.com/testcontainers/testcontainers-go/modules/postgres": "v0.43.0",
		"github.com/testcontainers/testcontainers-go/modules/redis":    "v0.43.0",
		"golang.org/x/crypto":                                          "v0.54.0",
	}

	command := exec.Command("go", "mod", "edit", "-json")
	output, err := command.Output()
	if err != nil {
		t.Fatalf("read go.mod: %v", err)
	}

	var module struct {
		Require []struct {
			Path     string
			Version  string
			Indirect bool
		}
	}
	if err := json.Unmarshal(output, &module); err != nil {
		t.Fatalf("decode go.mod: %v", err)
	}

	got := make(map[string]string, len(module.Require))
	for _, requirement := range module.Require {
		if !requirement.Indirect {
			got[requirement.Path] = requirement.Version
		}
	}

	for path, version := range want {
		if got[path] != version {
			t.Errorf("direct requirement %s = %q, want %q", path, got[path], version)
		}
	}

	if len(dependencyCompileContract) != len(want) {
		t.Fatalf("compile contract covers %d dependencies, want %d", len(dependencyCompileContract), len(want))
	}
}
