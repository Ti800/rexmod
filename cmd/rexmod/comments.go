package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"syscall"
	"time"
)

// Comment is a review note the user left on a line or a range of a file.
type Comment struct {
	ID        string `json:"id"`
	File      string `json:"file"` // relative to the repo root
	Line      int    `json:"line"`
	EndLine   int    `json:"end_line"`
	Text      string `json:"text"`
	Snippet   string `json:"snippet,omitempty"`
	CreatedAt string `json:"created_at"`
	SentAt    string `json:"sent_at,omitempty"`
	// TargetBlock is the Rex pane of the agent the note is for: the agent
	// in the editor's tab. Empty when the note was made outside Rex.
	TargetBlock string `json:"target_block,omitempty"`
}

// outsideRex stands for an agent not running in a Rex pane: it matches only
// notes made outside Rex (no TargetBlock).
const outsideRex = "outside-rex"

// For reports whether the note belongs to the agent in Rex pane block. An
// empty block means any agent; outsideRex only matches notes with no pane.
func (c Comment) For(block string) bool {
	return c.TargetBlock == "" || block == "" || c.TargetBlock == block
}

func (c Comment) Pending() bool { return c.SentAt == "" }

func (c Comment) Range() string {
	if c.EndLine > c.Line {
		return fmt.Sprintf("%d-%d", c.Line, c.EndLine)
	}
	return fmt.Sprintf("%d", c.Line)
}

type commentStore struct {
	repo string
	path string
	lock *os.File
}

func openComments(repo string) (*commentStore, error) {
	sd, err := stateDir(repo)
	if err != nil {
		return nil, err
	}
	lf, err := os.OpenFile(filepath.Join(sd, "comments.lock"), os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		return nil, err
	}
	if err := syscall.Flock(int(lf.Fd()), syscall.LOCK_EX); err != nil {
		lf.Close()
		return nil, err
	}
	return &commentStore{repo: repo, path: filepath.Join(sd, "comments.json"), lock: lf}, nil
}

func (s *commentStore) Close() {
	if s.lock != nil {
		_ = syscall.Flock(int(s.lock.Fd()), syscall.LOCK_UN)
		s.lock.Close()
	}
}

func (s *commentStore) Load() []Comment {
	b, err := os.ReadFile(s.path)
	if err != nil {
		return nil
	}
	var cs []Comment
	_ = json.Unmarshal(b, &cs)
	return cs
}

func (s *commentStore) Save(cs []Comment) error {
	if cs == nil {
		cs = []Comment{}
	}
	sort.SliceStable(cs, func(i, j int) bool {
		if cs[i].File != cs[j].File {
			return cs[i].File < cs[j].File
		}
		return cs[i].Line < cs[j].Line
	})
	return writeJSONAtomic(s.path, cs)
}

func newID() string {
	b := make([]byte, 4)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

// relToRepo turns a path (absolute or relative to cwd) into a repo-relative one.
func relToRepo(repo, file string) string {
	abs := file
	if !filepath.IsAbs(abs) {
		wd, _ := os.Getwd()
		abs = filepath.Join(wd, file)
	}
	if real, err := filepath.EvalSymlinks(abs); err == nil {
		abs = real
	}
	rr := repo
	if real, err := filepath.EvalSymlinks(repo); err == nil {
		rr = real
	}
	if rel, err := filepath.Rel(rr, abs); err == nil && !strings.HasPrefix(rel, "..") {
		return rel
	}
	return file
}

func readSnippet(repo, rel string, from, to int) string {
	b, err := os.ReadFile(filepath.Join(repo, rel))
	if err != nil {
		return ""
	}
	lines := strings.Split(string(b), "\n")
	if from < 1 {
		from = 1
	}
	if to < from {
		to = from
	}
	if to-from > 60 {
		to = from + 60
	}
	if from > len(lines) {
		return ""
	}
	if to > len(lines) {
		to = len(lines)
	}
	return strings.Join(lines[from-1:to], "\n")
}

func addComment(repo, file string, line, end int, text, snippet, target string) (*Comment, error) {
	text = strings.TrimSpace(text)
	if text == "" {
		return nil, fmt.Errorf("empty comment")
	}
	if end < line {
		end = line
	}
	rel := relToRepo(repo, file)
	if snippet == "" {
		snippet = readSnippet(repo, rel, line, end)
	}
	c := Comment{
		ID: newID(), File: rel, Line: line, EndLine: end, Text: text,
		Snippet:     snippet,
		CreatedAt:   time.Now().Format(time.RFC3339),
		TargetBlock: target,
	}
	s, err := openComments(repo)
	if err != nil {
		return nil, err
	}
	defer s.Close()
	cs := append(s.Load(), c)
	return &c, s.Save(cs)
}

func langFor(file string) string {
	ext := strings.TrimPrefix(filepath.Ext(file), ".")
	switch ext {
	case "ts", "tsx", "js", "jsx", "go", "rs", "py", "rb", "lua", "swift", "kt", "java", "c", "h", "cpp", "md", "json", "yaml", "yml", "toml", "sh", "css", "html", "sql":
		return ext
	}
	return ""
}

// formatComments renders comments as a prompt an agent can act on.
func formatComments(cs []Comment) string {
	var b strings.Builder
	b.WriteString("Review comments I left on the code (file:line, the code, then my comment). Address each one:\n")
	for i, c := range cs {
		fmt.Fprintf(&b, "\n%d. %s:%s\n", i+1, c.File, c.Range())
		if c.Snippet != "" {
			fmt.Fprintf(&b, "```%s\n%s\n```\n", langFor(c.File), c.Snippet)
		}
		fmt.Fprintf(&b, "Comment: %s\n", c.Text)
	}
	return b.String()
}

// takePending returns the pending comments for the agent in Rex pane block
// (all of them when block is empty) and marks them sent.
func takePending(repo, block string) ([]Comment, error) {
	s, err := openComments(repo)
	if err != nil {
		return nil, err
	}
	defer s.Close()
	cs := s.Load()
	var pending []Comment
	now := time.Now().Format(time.RFC3339)
	for i := range cs {
		if cs[i].Pending() && cs[i].For(block) {
			pending = append(pending, cs[i])
			cs[i].SentAt = now
		}
	}
	if len(pending) == 0 {
		return nil, nil
	}
	return pending, s.Save(cs)
}

// editorTarget finds the agent pane for a note made in the editor: the
// agent in the editor pane's tab. It reads the tab from the environment the
// editor runs in (REXMOD_* when rexmod opened it, REX_* in any Rex pane).
func editorTarget() string {
	if s, w := os.Getenv("REXMOD_SESSION"), os.Getenv("REXMOD_WINDOW"); s != "" {
		if t, err := resolveTarget(s, w); err == nil {
			return t.AgentBlockID
		}
	}
	s, b := os.Getenv("REX_SESSION"), os.Getenv("REX_BLOCK")
	if s == "" || b == "" {
		return ""
	}
	v, err := sessionView(s)
	if err != nil {
		return ""
	}
	for _, w := range v.Windows {
		for _, blk := range w.blocks() {
			if blk.BlockID == b || strings.HasSuffix(blk.BlockID, b) {
				if t, err := resolveTarget(s, w.WindowID); err == nil {
					return t.AgentBlockID
				}
			}
		}
	}
	return ""
}
