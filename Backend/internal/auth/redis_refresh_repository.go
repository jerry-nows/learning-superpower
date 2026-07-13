package auth

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"reflect"
	"strconv"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
)

type redisSessionClient interface {
	Eval(context.Context, string, []string, ...interface{}) *redis.Cmd
	HSet(context.Context, string, ...interface{}) *redis.IntCmd
	PExpire(context.Context, string, time.Duration) *redis.BoolCmd
	SAdd(context.Context, string, ...interface{}) *redis.IntCmd
}

type RedisRefreshRepository struct {
	client  redisSessionClient
	timeout time.Duration
}

const refreshReplayGrace = 24 * time.Hour

func NewRedisRefreshRepository(client redisSessionClient, operationTimeout time.Duration) (*RedisRefreshRepository, error) {
	if client == nil || (reflect.ValueOf(client).Kind() == reflect.Ptr && reflect.ValueOf(client).IsNil()) {
		return nil, errors.New("redis refresh repository client must not be nil")
	}
	if operationTimeout <= 0 {
		operationTimeout = 2 * time.Second
	}
	return &RedisRefreshRepository{client: client, timeout: operationTimeout}, nil
}

func digestKey(d [sha256.Size]byte) string { return "auth:refresh:session:" + hex.EncodeToString(d[:]) }
func familyKey(f string) string            { return "auth:refresh:family:" + f }
func familyStateKey(f string) string       { return "auth:refresh:family-state:" + f }
func userKey(u UserID) string              { return "auth:refresh:user:" + string(u) }

func (r *RedisRefreshRepository) opctx(ctx context.Context) (context.Context, context.CancelFunc) {
	return context.WithTimeout(ctx, r.timeout)
}

func validSession(s RefreshSession, now time.Time) bool {
	return strings.TrimSpace(s.FamilyID) != "" && strings.TrimSpace(string(s.UserID)) != "" && s.ExpiresAt.After(now) && s.TokenDigest != [sha256.Size]byte{}
}

const createLua = `local k=KEYS[1]; local fk=KEYS[2]; local uk=KEYS[3]; local now=tonumber(ARGV[1]); local exp=tonumber(ARGV[2]); local digest=ARGV[3]; local family=ARGV[4]; local user=ARGV[5]; if redis.call('EXISTS',k)==1 then return 2 end; local ttl=math.floor((exp-now)+0.999); local retention=ttl+86400000; redis.call('HSET',k,'family_id',family,'user_id',user,'expires_at',exp,'state','active'); redis.call('PEXPIRE',k,retention); redis.call('SADD',fk,digest); redis.call('PEXPIRE',fk,retention); redis.call('SADD',uk,family); redis.call('PEXPIRE',uk,retention); return 1`

func (r *RedisRefreshRepository) Create(ctx context.Context, s RefreshSession) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	now := time.Now().UTC()
	if !validSession(s, now) {
		return errors.Join(ErrRepository, errors.New("invalid refresh session"))
	}
	c, cancel := r.opctx(ctx)
	defer cancel()
	result, err := r.client.Eval(c, createLua, []string{digestKey(s.TokenDigest), familyKey(s.FamilyID), userKey(s.UserID)}, now.UnixMilli(), s.ExpiresAt.UTC().UnixMilli(), hex.EncodeToString(s.TokenDigest[:]), s.FamilyID, string(s.UserID)).Result()
	if err != nil {
		return mapRedisError(c, err)
	}
	if code, ok := redisInt(result); !ok || code == 2 {
		return ErrRepository
	}
	return nil
}

const rotateLua = `
local old = KEYS[1]
local now = tonumber(ARGV[1])
local replacement = ARGV[2]
local replacement_exp = ARGV[3]
local replacement_ttl = tonumber(ARGV[4])
if redis.call('EXISTS', old) == 0 then return {0} end
local family = redis.call('HGET', old, 'family_id')
local user = redis.call('HGET', old, 'user_id')
local famset = 'auth:refresh:family:' .. (family or '')
local famstate = 'auth:refresh:family-state:' .. (family or '')
local exp = tonumber(redis.call('HGET', old, 'expires_at') or '0')
local state = redis.call('HGET', old, 'state') or 'revoked'
local revoked = redis.call('GET', famstate)
local function revoke()
  redis.call('SET', famstate, 'revoked', 'PX', 86400000)
  for _, d in ipairs(redis.call('SMEMBERS', famset)) do local sk='auth:refresh:session:' .. d; if redis.call('EXISTS',sk)==1 then redis.call('HSET',sk,'state','revoked'); redis.call('PEXPIRE',sk,86400000) end end
  redis.call('PEXPIRE', famset, 86400000)
  redis.call('PEXPIRE', 'auth:refresh:user:' .. (user or ''), 86400000)
end
if exp <= now then revoke(); return {2} end
if revoked == 'revoked' then revoke(); return {4} end
if state ~= 'active' then revoke(); return {3} end
local nk = 'auth:refresh:session:' .. replacement
if redis.call('EXISTS', nk)==1 then return {5} end
redis.call('HSET', old, 'state', 'consumed')
redis.call('HSET', nk, 'family_id', family, 'user_id', user, 'expires_at', replacement_exp, 'state', 'active')
redis.call('PEXPIRE', nk, math.floor(replacement_ttl + 0.999) + 86400000)
redis.call('SADD', famset, replacement)
redis.call('PEXPIRE', famset, math.floor(replacement_ttl + 0.999) + 86400000)
redis.call('PEXPIRE', 'auth:refresh:user:' .. user, math.floor(replacement_ttl + 0.999) + 86400000)
return {1, family, user, replacement_exp}
`

func (r *RedisRefreshRepository) Rotate(ctx context.Context, presented [sha256.Size]byte, replacement RefreshSession) (RefreshSession, error) {
	now := time.Now().UTC()
	if presented == [sha256.Size]byte{} || replacement.TokenDigest == [sha256.Size]byte{} || replacement.TokenDigest == presented || !replacement.ExpiresAt.After(now) {
		return RefreshSession{}, errors.Join(ErrRepository, errors.New("invalid refresh rotation"))
	}
	c, cancel := r.opctx(ctx)
	defer cancel()
	d := hex.EncodeToString(presented[:])
	rd := hex.EncodeToString(replacement.TokenDigest[:])
	// Family/user are authoritative from the old record; placeholders are not trusted.
	ttlMs := float64(replacement.ExpiresAt.Sub(now).Microseconds()) / 1000
	res, err := r.client.Eval(c, rotateLua, []string{digestKey(presented)}, now.UnixMilli(), rd, replacement.ExpiresAt.UTC().UnixMilli(), strconv.FormatFloat(ttlMs, 'f', 3, 64)).Result()
	if err != nil {
		return RefreshSession{}, mapRedisError(c, err)
	}
	vals, ok := res.([]interface{})
	if !ok || len(vals) == 0 {
		return RefreshSession{}, ErrRepository
	}
	code, ok := redisInt(vals[0])
	if !ok {
		return RefreshSession{}, ErrRepository
	}
	switch code {
	case 0:
		return RefreshSession{}, ErrRefreshSessionNotFound
	case 2:
		return RefreshSession{}, ErrRefreshSessionExpired
	case 3:
		return RefreshSession{}, ErrRefreshTokenReuse
	case 4:
		return RefreshSession{}, ErrRefreshFamilyRevoked
	case 5:
		return RefreshSession{}, ErrRepository
	}
	if code != 1 || len(vals) < 4 {
		return RefreshSession{}, ErrRepository
	}
	fam, ok1 := vals[1].(string)
	usr, ok2 := vals[2].(string)
	exp, ok3 := redisInt(vals[3])
	if !ok1 || !ok2 || !ok3 || fam == "" || usr == "" {
		return RefreshSession{}, ErrRepository
	}
	_ = d
	return RefreshSession{FamilyID: fam, UserID: UserID(usr), TokenDigest: replacement.TokenDigest, ExpiresAt: time.UnixMilli(exp).UTC()}, nil
}

const revokeUserLua = `local fams=redis.call('SMEMBERS',KEYS[1]); redis.call('PEXPIRE',KEYS[1],86400000); for _,f in ipairs(fams) do local sk='auth:refresh:family:'..f; redis.call('SET','auth:refresh:family-state:'..f,'revoked','PX',86400000); redis.call('PEXPIRE',sk,86400000); for _,d in ipairs(redis.call('SMEMBERS',sk)) do local dk='auth:refresh:session:'..d; if redis.call('EXISTS',dk)==1 then redis.call('HSET',dk,'state','revoked'); redis.call('PEXPIRE',dk,86400000) end end end; return 1`

func (r *RedisRefreshRepository) RevokeUser(ctx context.Context, id UserID) error {
	if strings.TrimSpace(string(id)) == "" {
		return ErrRepository
	}
	c, cancel := r.opctx(ctx)
	defer cancel()
	if _, err := r.client.Eval(c, revokeUserLua, []string{userKey(id)}).Result(); err != nil {
		return mapRedisError(c, err)
	}
	return nil
}

func redisInt(v interface{}) (int64, bool) {
	switch n := v.(type) {
	case int64:
		return n, true
	case int:
		return int64(n), true
	case string:
		x, e := strconv.ParseInt(n, 10, 64)
		return x, e == nil
	case []byte:
		x, e := strconv.ParseInt(string(n), 10, 64)
		return x, e == nil
	}
	return 0, false
}
func mapRedisError(ctx context.Context, err error) error {
	if ctx.Err() != nil {
		return ctx.Err()
	}
	return ErrRepository
}

var _ RefreshSessionRepository = (*RedisRefreshRepository)(nil)
var _ = redis.NewScript
