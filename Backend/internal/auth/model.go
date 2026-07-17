package auth

import "time"

// UserID identifies a user across authentication boundaries.
type UserID string

// UserStatus describes whether a user may authenticate.
type UserStatus string

const (
	UserStatusActive   UserStatus = "active"
	UserStatusDisabled UserStatus = "disabled"
)

// User is the public authentication-domain view of a user.
type User struct {
	ID        UserID     `json:"id"`
	Email     string     `json:"email"`
	Status    UserStatus `json:"status"`
	CreatedAt time.Time  `json:"created_at"`
	UpdatedAt time.Time  `json:"updated_at"`
}

// CredentialRecord is private persistence data used to verify a login. Every
// field is explicitly excluded from JSON so the password hash cannot cross a
// transport boundary accidentally. Call PublicUser for the safe projection.
type CredentialRecord struct {
	ID           UserID     `json:"-"`
	Email        string     `json:"-"`
	Status       UserStatus `json:"-"`
	PasswordHash string     `json:"-"`
	CreatedAt    time.Time  `json:"-"`
	UpdatedAt    time.Time  `json:"-"`
}

// PublicUser removes credential material explicitly.
func (record CredentialRecord) PublicUser() User {
	return User{
		ID:        record.ID,
		Email:     record.Email,
		Status:    record.Status,
		CreatedAt: record.CreatedAt,
		UpdatedAt: record.UpdatedAt,
	}
}

// TokenPair carries issued secrets together with explicit, clock-independent
// expiry metadata. HTTP handlers remain responsible for transport mapping.
type TokenPair struct {
	AccessToken      string    `json:"-"`
	RefreshToken     string    `json:"-"`
	AccessExpiresAt  time.Time `json:"-"`
	RefreshExpiresAt time.Time `json:"-"`
}
