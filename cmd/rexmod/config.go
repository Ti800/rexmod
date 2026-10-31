package main

import (
	"encoding/json"
	"os"
	"path/filepath"
)

// Config is ~/.config/rexmod/config.json, written by install.sh.
type Config struct {
	// NvimAppName runs the editor pane with NVIM_APPNAME set, for machines
	// where the bundled editor config lives next to the user's own.
	NvimAppName string `json:"nvim_appname,omitempty"`
}

func loadConfig() Config {
	var c Config
	home, err := os.UserHomeDir()
	if err != nil {
		return c
	}
	b, err := os.ReadFile(filepath.Join(home, ".config", "rexmod", "config.json"))
	if err == nil {
		_ = json.Unmarshal(b, &c)
	}
	return c
}

// nvimEnv is extra environment for every Neovim rexmod starts.
func nvimEnv() map[string]string {
	env := map[string]string{}
	if app := loadConfig().NvimAppName; app != "" {
		env["NVIM_APPNAME"] = app
	}
	return env
}
