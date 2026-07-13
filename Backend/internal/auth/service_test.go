package auth

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"
)

type serviceUsers struct {
	record   CredentialRecord
	err      error
	gotEmail string
	gotCtx   context.Context
}

func (r *serviceUsers) FindByEmail(ctx context.Context, email string) (CredentialRecord, error) {
	r.gotEmail, r.gotCtx = email, ctx
	return r.record, r.err
}

type serviceSessions struct {
	created                         []RefreshSession
	rotateCurrent                   RefreshSession
	createErr, rotateErr, revokeErr error
	rotateDigest                    [32]byte
	revokeID                        UserID
	gotCtx                          context.Context
}

func (r *serviceSessions) Create(ctx context.Context, s RefreshSession) error {
	r.gotCtx = ctx
	r.created = append(r.created, s)
	return r.createErr
}
func (r *serviceSessions) Rotate(ctx context.Context, d [32]byte, s RefreshSession) (RefreshSession, error) {
	r.gotCtx = ctx
	r.rotateDigest = d
	if r.rotateErr != nil {
		return RefreshSession{}, r.rotateErr
	}
	return r.rotateCurrent, nil
}
func (r *serviceSessions) RevokeUser(ctx context.Context, id UserID) error {
	r.gotCtx = ctx
	r.revokeID = id
	if err := ctx.Err(); err != nil {
		return err
	}
	return r.revokeErr
}

type serviceVerifier struct {
	ok                   bool
	err                  error
	gotPassword, gotHash string
}

func (v *serviceVerifier) Verify(password, hash string) (bool, error) {
	v.gotPassword, v.gotHash = password, hash
	return v.ok, v.err
}

type serviceIssuer struct {
	issued IssuedAccessToken
	err    error
	ids    []UserID
}

func (i *serviceIssuer) Issue(id UserID) (IssuedAccessToken, error) {
	i.ids = append(i.ids, id)
	return i.issued, i.err
}

func testService(t *testing.T, u *serviceUsers, ss *serviceSessions, issuer *serviceIssuer, vf *serviceVerifier, refresh func() (RefreshToken, error), family func() (string, error)) *Service {
	t.Helper()
	s, err := NewService(ServiceConfig{Users: u, Sessions: ss, PasswordVerifier: vf, AccessTokenIssuer: issuer, RefreshTokenFactory: refresh, FamilyIDFactory: family, Clock: func() time.Time { return time.Unix(100, 0).UTC() }, RefreshLifetime: time.Hour})
	if err != nil {
		t.Fatal(err)
	}
	return s
}
func deterministicRefreshes() func() (RefreshToken, error) {
	n := byte(1)
	return func() (RefreshToken, error) {
		raw := make([]byte, 32)
		raw[0] = n
		n++
		tok, _ := NewRefreshToken(strings.NewReader(string(raw)))
		return tok, nil
	}
}

func TestServiceLoginLifecycleAndValidation(t *testing.T) {
	base := CredentialRecord{ID: "u1", Email: "User@Example.com", Status: UserStatusActive, PasswordHash: "hash"}
	cases := []struct {
		name               string
		rec                CredentialRecord
		userErr, verifyErr error
		ok                 bool
		wantCode           string
	}{
		{"unknown", base, ErrUserNotFound, nil, false, "authentication_failed"}, {"disabled", CredentialRecord{ID: "u1", Status: UserStatusDisabled}, nil, nil, false, "authentication_failed"}, {"wrong", base, nil, nil, false, "authentication_failed"}, {"malformed", base, nil, errors.New("bad hash"), false, "authentication_failed"}, {"success", base, nil, nil, true, ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			u := &serviceUsers{record: tc.rec, err: tc.userErr}
			v := &serviceVerifier{ok: tc.ok, err: tc.verifyErr}
			ss := &serviceSessions{}
			iss := &serviceIssuer{issued: IssuedAccessToken{Value: "access", ExpiresAt: time.Unix(160, 0)}}
			s := testService(t, u, ss, iss, v, deterministicRefreshes(), func() (string, error) { return "family-1", nil })
			user, pair, err := s.Login(context.Background(), " User@Example.COM ", "password")
			if tc.ok {
				if err != nil || user.ID != "u1" || pair.AccessToken != "access" {
					t.Fatalf("login = %#v %#v %v", user, pair, err)
				}
				if len(ss.created) != 1 || ss.created[0].FamilyID != "family-1" {
					t.Fatalf("session not created: %#v", ss.created)
				}
				return
			}
			if err == nil {
				t.Fatal("expected failure")
			}
			var se *ServiceError
			if !errors.As(err, &se) || se.Code != tc.wantCode {
				t.Fatalf("error=%v", err)
			}
			if strings.Contains(err.Error(), "password") || strings.Contains(err.Error(), "hash") {
				t.Fatal("secret leaked")
			}
			if u.gotEmail != "user@example.com" {
				t.Fatalf("email=%q", u.gotEmail)
			}
		})
	}
}

func TestServiceRefreshRotationAndRejectsInvalidOrReused(t *testing.T) {
	old, _ := NewRefreshToken(strings.NewReader(strings.Repeat("a", 32)))
	ss := &serviceSessions{rotateCurrent: RefreshSession{FamilyID: "fam", UserID: "u1", ExpiresAt: time.Unix(200, 0)}}
	iss := &serviceIssuer{issued: IssuedAccessToken{Value: "a", ExpiresAt: time.Unix(160, 0)}}
	s := testService(t, &serviceUsers{}, ss, iss, &serviceVerifier{}, deterministicRefreshes(), func() (string, error) { return "fam", nil })
	user, pair, err := s.Refresh(context.Background(), old.Encoded())
	if err != nil || user.ID != "u1" || pair.RefreshToken == old.Encoded() {
		t.Fatalf("refresh=%#v %#v %v", user, pair, err)
	}
	if ss.rotateDigest != old.Digest() {
		t.Fatal("rotation used wrong digest")
	}
	for _, in := range []string{"", "not-base64", " " + old.Encoded()} {
		if _, _, err := s.Refresh(context.Background(), in); !errors.Is(err, ErrRefreshRejected) {
			t.Errorf("input %q error=%v", in, err)
		}
	}
	ss.rotateErr = ErrRefreshTokenReuse
	if _, _, err := s.Refresh(context.Background(), old.Encoded()); !errors.Is(err, ErrRefreshRejected) {
		t.Fatalf("reuse error=%v", err)
	}
}

func TestServiceFailureMappingsLogoutContextAndNoSecrets(t *testing.T) {
	secret := "super-secret"
	u := &serviceUsers{err: errors.New(secret)}
	ss := &serviceSessions{}
	s := testService(t, u, ss, &serviceIssuer{}, &serviceVerifier{}, deterministicRefreshes(), func() (string, error) { return "f", nil })
	if _, _, err := s.Login(context.Background(), "a", secret); err == nil || strings.Contains(err.Error(), secret) {
		t.Fatalf("login leak: %v", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if err := s.Logout(ctx, "u1"); err == nil || !errors.Is(err, ErrLogoutFailed) {
		t.Fatalf("logout=%v", err)
	}
	if err := s.Logout(context.Background(), ""); !errors.Is(err, ErrLogoutFailed) {
		t.Fatalf("blank logout=%v", err)
	}
	ss.revokeErr = errors.New("db down")
	if err := s.Logout(context.Background(), "u1"); err == nil || !errors.Is(err, ErrLogoutFailed) {
		t.Fatalf("repo logout=%v", err)
	}
	if b, _ := json.Marshal(TokenPair{AccessToken: secret, RefreshToken: secret}); strings.Contains(string(b), secret) {
		t.Fatal("token serialized")
	}
}
