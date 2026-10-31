package main

import (
	"encoding/json"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// The editor pane starts Neovim without a shell, because a fish login shell
// alone costs most of a second. To keep the user's PATH and tool variables,
// the login environment is read once with a clean environment and cached.

const loginEnvTTL = 24 * time.Hour

var loginEnvSkip = map[string]bool{
	"PWD": true, "OLDPWD": true, "SHLVL": true, "_": true, "TERM": true, "COLORTERM": true,
	"TERM_PROGRAM": true, "TERM_PROGRAM_VERSION": true, "TMUX": true, "TMUX_PANE": true,
	"SHELL_SESSION_ID": true,
}

// loginEnvAllowed keeps the variables tools and language servers need and
// drops everything else, so tokens never reach a command line or the cache.
func loginEnvAllowed(k string) bool {
	u := strings.ToUpper(k)
	for _, bad := range []string{"KEY", "TOKEN", "SECRET", "PASSWORD", "PASSWD", "CREDENTIAL", "AUTH"} {
		if strings.Contains(u, bad) {
			return false
		}
	}
	switch k {
	case "PATH", "MANPATH", "LANG", "LC_ALL", "LC_CTYPE", "EDITOR", "VISUAL", "NVIM_APPNAME", "GOPATH", "GOROOT",
		"GOBIN", "PNPM_HOME", "BUN_INSTALL", "NVM_DIR", "NVM_BIN", "NVM_INC", "HOMEBREW_PREFIX", "SSH_AUTH_SOCK":
		return true
	}
	return strings.HasPrefix(k, "XDG_") || strings.HasPrefix(k, "LC_") || strings.HasSuffix(k, "_HOME") ||
		strings.HasPrefix(k, "ANDROID_") || strings.HasPrefix(k, "CARGO_") || strings.HasPrefix(k, "RUSTUP_")
}

func loginShell() string {
	if u, err := user.Current(); err == nil {
		out, err := exec.Command("/usr/bin/dscl", ".", "-read", "/Users/"+u.Username, "UserShell").Output()
		if err == nil {
			if f := strings.Fields(string(out)); len(f) == 2 {
				return f[1]
			}
		}
	}
	if s := os.Getenv("SHELL"); s != "" {
		return s
	}
	return "/bin/zsh"
}

func loginEnvPath() string { return filepath.Join(cacheDir(), "login-env.json") }

func refreshLoginEnv() (map[string]string, error) {
	home, _ := os.UserHomeDir()
	u, _ := user.Current()
	name := ""
	if u != nil {
		name = u.Username
	}
	sh := loginShell()
	cmd := exec.Command(sh, "-l", "-c", "/usr/bin/env")
	cmd.Env = []string{"HOME=" + home, "USER=" + name, "LOGNAME=" + name, "SHELL=" + sh,
		"TMPDIR=" + os.TempDir(), "PATH=/usr/bin:/bin:/usr/sbin:/sbin", "TERM=xterm-256color"}
	cmd.Dir = home
	out, err := cmd.Output()
	if err != nil {
		return nil, err
	}
	env := map[string]string{}
	for _, line := range strings.Split(string(out), "\n") {
		k, v, ok := strings.Cut(line, "=")
		if !ok || k == "" || strings.ContainsAny(k, " \t") || loginEnvSkip[k] || !loginEnvAllowed(k) {
			continue
		}
		env[k] = v
	}
	if env["PATH"] == "" {
		return nil, os.ErrNotExist
	}
	_ = writeJSONAtomic(loginEnvPath(), env)
	_ = os.Chmod(loginEnvPath(), 0o600)
	return env, nil
}

func loginEnv() map[string]string {
	if fi, err := os.Stat(loginEnvPath()); err == nil && time.Since(fi.ModTime()) < loginEnvTTL {
		if b, err := os.ReadFile(loginEnvPath()); err == nil {
			var env map[string]string
			if json.Unmarshal(b, &env) == nil && env["PATH"] != "" {
				return env
			}
		}
	}
	env, err := refreshLoginEnv()
	if err != nil {
		return map[string]string{"PATH": os.Getenv("PATH")}
	}
	return env
}

// envArgs renders the login environment as KEY=VALUE arguments for env(1).
func envArgs(extra map[string]string) []string {
	env := loginEnv()
	for k, v := range extra {
		env[k] = v
	}
	keys := make([]string, 0, len(env))
	for k := range env {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	args := make([]string, 0, len(keys))
	for _, k := range keys {
		args = append(args, k+"="+env[k])
	}
	return args
}

// lookPathIn finds a program on the given PATH.
func lookPathIn(path, name string) string {
	for _, dir := range filepath.SplitList(path) {
		p := filepath.Join(dir, name)
		if fi, err := os.Stat(p); err == nil && !fi.IsDir() && fi.Mode()&0o111 != 0 {
			return p
		}
	}
	return ""
}
